// Sprint 20 (1.3.0): the Hunter, the Mayor, the Framer and the Watcher online; the 1.3.0 gate for Avenger and Shadows;
// migration 0014; old phones get a role they know (C1); the profile counts the new roles (C8).
import { runDurableObjectAlarm, runInDurableObject } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_RULES } from '@mafia/engine';
import { MODES_BUILD, ROLES13_BUILD } from '@mafia/protocol';
import { profile, type SGame } from '../src/stats.ts';
import { sum } from '../src/wifi.ts';
import { setup } from './helpers.ts';
import { account, api, connect, DB, roomStub, type Sock } from './live.ts';

beforeEach(async () => { await setup(); });

async function table(n: number, builds: number[] = []) {
  const accts = await Promise.all(Array.from({ length: n }, (_, i) => account('T' + (i + 1) + 'x' + Math.random().toString(36).slice(2, 6))));
  const { json } = await api('POST', '/v1/rooms', accts[0].token);
  const players: Sock[] = [];
  for (const [i, a] of accts.entries()) {
    players.push(await connect(`/v1/rooms/${json.code}/ws?v=${builds[i] ?? ROLES13_BUILD}`, a.token));
    await players.at(-1)!.until(() => players.at(-1)!.room, 'room');
  }
  await players[0].until(() => players[0].room?.members.length === n, n + ' members');
  return { players, code: json.code as string, accts };
}
const OFF = { ...DEFAULT_RULES, reveal: false };
const setupMsg = (mode: string, mafia: number, rules: object = OFF) => ({ t: 'setup', buzzMax: 3, rules, counts: { mafia, detective: 1 }, mode });

/** Deals and starts; returns the players by role. */
async function start(players: Sock[], mode: string, mafia: number, rules: object = OFF) {
  const [host] = players;
  host.send(setupMsg(mode, mafia, rules));
  await host.until(() => host.room.mode === mode, 'mode');
  host.send({ t: 'deal' });
  await Promise.all(players.map(p => p.until(() => p.view?.phase === 'deal', 'deal')));
  host.send({ t: 'start' });
  await Promise.all(players.map(p => p.until(() => p.view?.phase === 'night', 'night')));
  const by = (r: string) => players.filter(p => p.view.role === r);
  return { by, one: (r: string) => by(r)[0] };
}
/** Everyone picks: the given seat for these players, else their first open option (or nothing). */
async function night(players: Sock[], picks: Map<Sock, number>, frame?: number) {
  for (const p of players) {
    if (p.view.ph !== 'night') continue;
    const no = p.view.night, choice = picks.get(p) ?? (no.key === 'none' ? null : no.opts.find((o: any) => !o.disabled).seat);
    p.send({ t: 'night', choice, day: p.view.day, ...(no.frame && frame != null ? { frame } : {}) });
    await p.until(() => p.view.ph !== 'night', 'night pick');
  }
}

describe('the 1.3.0 gate (C1)', () => {
  it('Avenger and Shadows need 1.3.0 on every seat; Classic still deals with a 1.2.1 phone', async () => {
    expect(ROLES13_BUILD).toBe(100023);
    const { players } = await table(6, [ROLES13_BUILD, ROLES13_BUILD, ROLES13_BUILD, ROLES13_BUILD, ROLES13_BUILD, 100022]);
    const [host] = players;
    host.send(setupMsg('avenger', 2));
    await host.until(() => host.room.mode === 'avenger', 'mode');
    host.send({ t: 'deal' });
    await host.until(() => host.got(m => m.t === 'err' && m.error === 'old_app'), 'old_app');
    expect(host.view).toBeNull();
    host.send(setupMsg('classic', 1));
    await host.until(() => host.room.mode === 'classic', 'classic');
    host.send({ t: 'deal' });
    await host.until(() => host.view?.phase === 'deal', 'Classic deals');
  });
});

describe('the Hunter online', () => {
  it('killed at night he aims, the others wait, his shot lands and the day goes on (E-H1-H3)', async () => {
    const { players } = await table(6);
    const g = await start(players, 'avenger', 2);
    expect(players.map(p => p.view.role).sort()).toEqual(['citizen', 'detective', 'doctor', 'hunter', 'mafia', 'mafia']);
    const hunter = g.one('hunter'), doc = g.one('doctor'), [m1, m2] = g.by('mafia');
    await night(players, new Map([[m1, hunter.view.seat], [m2, hunter.view.seat], [doc, doc.view.seat]]));
    await hunter.until(() => hunter.view.ph === 'hunt', 'his aim');
    expect(hunter.view.huntOpts).not.toContain(hunter.view.seat);
    expect(players[0].view.phase).toBe('morning');
    await doc.until(() => doc.view.hunt?.seat === hunter.view.seat, 'everyone sees "the Hunter is aiming"');
    // the host can't start the day yet ("Continue anyway" is in the next describe: it holds fire for him)
    const host = players[0];
    host.send({ t: 'startDay' });
    await host.until(() => host.got(m => m.t === 'err' && m.error === 'hunt'), 'hunt');
    hunter.send({ t: 'hunt', choice: m1.view.seat });
    await doc.until(() => doc.view.hunted?.seat === m1.view.seat, 'the shot');
    expect(doc.view.hunted).toEqual({ by: hunter.view.seat, seat: m1.view.seat, role: null });
    expect(doc.view.roster[m1.view.seat].alive).toBe(false);
    host.send({ t: 'startDay' });
    await host.until(() => host.view.phase === 'day', 'day');
  });

  it('the Hunter\'s aim runs out with the night timer: he holds fire (§8 D)', async () => {
    const { players, code } = await table(6);
    const g = await start(players, 'avenger', 2, { ...OFF, nightT: 30 });
    const hunter = g.one('hunter'), doc = g.one('doctor'), [m1, m2] = g.by('mafia');
    await night(players, new Map([[m1, hunter.view.seat], [m2, hunter.view.seat], [doc, doc.view.seat]]));
    await hunter.until(() => hunter.view.ph === 'hunt', 'his aim');
    expect(hunter.view.timer.end).toBeGreaterThan(Date.now());
    await runInDurableObject(roomStub(code), async (_o, state) => {
      const st = await state.storage.get<any>('room'); st.game.hunt.endsAt = Date.now() - 1; await state.storage.put('room', st);
    });
    expect(await runDurableObjectAlarm(roomStub(code))).toBe(true);
    await doc.until(() => doc.view.hunt === null, 'held fire');
    expect(doc.view.hunted).toEqual({ by: hunter.view.seat, seat: null, role: null });
  });

  it('kicking the aiming Hunter: he holds fire and the game goes on (E-X5)', async () => {
    const { players, accts } = await table(6);
    players[0].send({ ...setupMsg('avenger', 2), kick: 'any' });
    await players[0].until(() => players[0].room.kick === 'any', 'kick rule');
    const g = await start(players, 'avenger', 2);
    const hunter = g.one('hunter'), doc = g.one('doctor'), [m1, m2] = g.by('mafia');
    if (hunter === players[0]) return;  // the host can't kick himself; the engine test covers it
    await night(players, new Map([[m1, hunter.view.seat], [m2, hunter.view.seat], [doc, doc.view.seat]]));
    await hunter.until(() => hunter.view.ph === 'hunt', 'his aim');
    players[0].send({ t: 'kick', uid: accts[players.indexOf(hunter)].id });
    await doc.until(() => doc.view.hunt === null, 'held fire');
  });
});

describe('[Quin Q1, Q4] nobody waits forever for the Hunter', () => {
  async function aiming() {
    const t = await table(6);
    players0 = t.players;
    const g = await start(t.players, 'avenger', 2);
    const hunter = g.one('hunter'), doc = g.one('doctor'), [m1, m2] = g.by('mafia');
    await night(t.players, new Map([[m1, hunter.view.seat], [m2, hunter.view.seat], [doc, doc.view.seat]]));
    await hunter.until(() => hunter.view.ph === 'hunt', 'his aim');
    return { ...t, hunter, doc };
  }
  let players0: Sock[] = [];
  it('the aiming Hunter leaves the room: he holds fire, and the host can start the day', async () => {
    const { hunter, doc } = await aiming();
    if (hunter === players0[0]) return;  // the host leaving hands the room on; the engine and Wi-Fi tests cover it
    hunter.send({ t: 'leave' });
    await doc.until(() => doc.view.hunt === null, 'held fire');
    expect(doc.view.hunted).toEqual({ by: hunter.view.seat, seat: null, role: null });
  });
  it('the Hunter is online but never answers: the host goes on (the app asks first), he holds fire', async () => {
    const { hunter, doc } = await aiming();
    if (hunter === players0[0]) return;
    players0[0].send({ t: 'continue' });
    await doc.until(() => doc.view.hunt === null, 'held fire');
  });
});

describe('the Mayor, the Framer and the Watcher online', () => {
  it('the Mayor reveals by day and every phone shows it', async () => {
    const { players } = await table(7);
    const g = await start(players, 'avenger', 2);
    const mayor = g.one('mayor');
    await night(players, new Map());
    const host = players[0];
    await host.until(() => host.view.phase === 'morning' || host.view.phase === 'end', 'morning');
    if (host.view.phase === 'end' || !mayor.view.alive || host.view.hunt) return;  // the dice killed him or the Hunter: covered by the engine tests
    host.send({ t: 'startDay' });
    await host.until(() => host.view.phase === 'day', 'day');
    mayor.send({ t: 'reveal' });
    await host.until(() => host.view.mayors?.includes(mayor.view.seat), 'revealed');
  });

  it('the Framer frames, the Detective reads Mafia in the morning, the Watcher sees the visitors', async () => {
    const { players } = await table(8);
    const g = await start(players, 'shadows', 2);
    expect(players.map(p => p.view.role).sort()).toEqual(['citizen', 'citizen', 'detective', 'doctor', 'mafia', 'mafia', 'sniper', 'watcher']);
    const [a, b] = g.by('mafia'), framer = a.view.framer === a.view.seat ? a : b, det = g.one('detective'), w = g.one('watcher'), doc = g.one('doctor');
    const cit = g.by('citizen');
    expect(a.view.framer).toBe(framer.view.seat);
    expect(framer.view.night.frame).toContain(cit[1].view.seat);
    await night(players, new Map([[a, cit[0].view.seat], [b, cit[0].view.seat], [doc, doc.view.seat], [det, cit[1].view.seat], [w, cit[1].view.seat]]), cit[1].view.seat);
    await det.until(() => det.view.phase === 'morning', 'morning');
    expect(det.view.check).toEqual({ seat: cit[1].view.seat, mafia: true });
    expect(framer.view.framed).toEqual({ seat: cit[1].view.seat, hit: true });
    expect(w.view.watch).toEqual([{ seat: cit[1].view.seat, visitors: [framer.view.seat, det.view.seat].sort((x, y) => x - y) }]);
  });
});

describe('saved, counted and readable by old phones (migration 0014, C1, C8)', () => {
  it('history takes the new roles; a 1.2.1 phone gets Citizen in `role`, 1.3.0 the real one in `role2`', async () => {
    const a = await account('Hx' + Math.random().toString(36).slice(2, 6));
    await DB().batch([
      DB().prepare("INSERT INTO games (id, host_id, winner, days, rules, log, stats, played_at) VALUES ('h1', ?, 'citizens', 1, '{}', '[]', '{}', 1)").bind(a.id),
      DB().prepare("INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES ('h1', 0, ?, 'A', 'hunter', 0), ('h1', 1, NULL, 'B', 'mayor', 1), ('h1', 2, NULL, 'C', 'watcher', 1), ('h1', 3, NULL, 'D', 'mafia', 0)").bind(a.id),
    ]);
    await expect(DB().prepare("INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES ('h1', 4, NULL, 'E', 'nope', 1)").run()).rejects.toThrow();
    const list = (await api('GET', '/v1/games', a.token)).json.games;
    expect(list[0]).toMatchObject({ role: 'citizen', role2: 'hunter' });
    const page = (await api('GET', '/v1/games/h1', a.token)).json.players;
    expect(page.map((p: any) => [p.role, p.role2])).toEqual([['citizen', 'hunter'], ['citizen', 'mayor'], ['citizen', 'watcher'], ['mafia', 'mafia']]);
  });

  it('the profile counts the new roles on the town\'s side (a Hunter game used to throw)', () => {
    const g = (winner: SGame['winner'], role: any): SGame => ({ id: Math.random() + '', source: 'online', playedAt: 1, winner, days: 1,
      seats: ['mafia', role, 'citizen', 'citizen'].map((r: any, i) => ({ key: 'p' + i, userId: null, name: 'p' + i, role: r, alive: true })),
      ev: { first: null, kills: [], outs: [], saves: [], caught: [] } });
    const me = profile([g('citizens', 'hunter'), g('mafia', 'mayor'), g('citizens', 'watcher')], 'p1');
    expect([me.roles.hunter, me.roles.mayor, me.roles.watcher]).toEqual([[1, 1], [1, 0], [1, 1]]);
    expect(me.side).toEqual([3, 2]);
    expect(['mafia', 'doctor', 'detective', 'citizen']).toContain(me.best);
  });

  it('a Wi-Fi note and the Wi-Fi tab give a 1.2.1 phone a role it knows (role2: the real one)', () => {
    const rec = JSON.stringify({ names: ['A', 'B', 'C', 'D'], roles: ['hunter', 'mafia', 'watcher', 'citizen'], winner: 'citizens' });
    expect(sum(rec, 0)).toEqual({ players: 4, winner: 'citizens', role: 'citizen', role2: 'hunter' });
    expect(sum(rec, 1)).toMatchObject({ role: 'mafia', role2: 'mafia' });
    expect(sum(rec, null)).toMatchObject({ role: null, role2: null });
  });

  it('MODES_BUILD is unchanged: 1.1.0+ phones still play the old modes', () => { expect(MODES_BUILD).toBe(100019); });
});
