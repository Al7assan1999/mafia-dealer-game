// Sprint 21 (1.4.0): the Serial Killer, Cupid and the Silencer online; the 1.4.0 gate for Lovers and Lone Wolves;
// migration 0015 (the new endings and roles saved); phones before 1.4.0 get a result and a role they know (D3); stats
// per seat (D8); the old modes' Mafia ranges dealt as the host chose (R10).
import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_RULES } from '@mafia/engine';
import { ROLES13_BUILD, ROLES14_BUILD } from '@mafia/protocol';
import { board, profile, type SGame } from '../src/stats.ts';
import { sum } from '../src/wifi.ts';
import { setup } from './helpers.ts';
import { account, api, connect, DB, type Sock } from './live.ts';

beforeEach(async () => { await setup(); });

async function table(n: number, builds: number[] = []) {
  const accts = await Promise.all(Array.from({ length: n }, (_, i) => account('W' + (i + 1) + 'x' + Math.random().toString(36).slice(2, 6))));
  const { json } = await api('POST', '/v1/rooms', accts[0].token);
  const players: Sock[] = [];
  for (const [i, a] of accts.entries()) {
    players.push(await connect(`/v1/rooms/${json.code}/ws?v=${builds[i] ?? ROLES14_BUILD}`, a.token));
    await players.at(-1)!.until(() => players.at(-1)!.room, 'room');
  }
  await players[0].until(() => players[0].room?.members.length === n, n + ' members');
  return players;
}
const OFF = { ...DEFAULT_RULES, reveal: false };
async function start(players: Sock[], mode: string, mafia: number) {
  const [host] = players;
  host.send({ t: 'setup', buzzMax: 3, rules: OFF, counts: { mafia, detective: 1 }, mode });
  await host.until(() => host.room.mode === mode && host.room.counts.mafia === mafia, 'setup');
  host.send({ t: 'deal' });
  await Promise.all(players.map(p => p.until(() => p.view?.phase === 'deal', 'deal')));
  host.send({ t: 'start' });
  await Promise.all(players.map(p => p.until(() => p.view?.phase === 'night', 'night')));
  return (r: string) => players.filter(p => p.view.role === r);
}
async function night(players: Sock[], picks: Map<Sock, object>) {
  for (const p of players) {
    if (p.view.ph !== 'night') continue;
    const no = p.view.night, def = { choice: no.key === 'none' ? null : no.opts.find((o: any) => !o.disabled).seat };
    p.send({ t: 'night', day: p.view.day, ...def, ...(picks.get(p) ?? {}) });
    await p.until(() => p.view.ph !== 'night', 'night pick');
  }
}

describe('the 1.4.0 gate (D6) and the old modes\' ranges (R10)', () => {
  it('Lovers and Lone Wolves need 1.4.0 on every seat; Avenger still deals with a 1.3.1 phone', async () => {
    expect(ROLES14_BUILD).toBe(100025);
    const players = await table(8, [ROLES14_BUILD, ROLES14_BUILD, ROLES14_BUILD, ROLES14_BUILD, ROLES14_BUILD, ROLES14_BUILD, ROLES14_BUILD, 100024]);
    const [host] = players;
    host.send({ t: 'setup', buzzMax: 3, rules: OFF, counts: { mafia: 2, detective: 1 }, mode: 'lovers' });
    await host.until(() => host.room.mode === 'lovers', 'mode');
    host.send({ t: 'deal' });
    await host.until(() => host.got(m => m.t === 'err' && m.error === 'old_app'), 'old_app');
    expect(ROLES13_BUILD).toBeLessThan(100024);
    host.send({ t: 'setup', buzzMax: 3, rules: OFF, counts: { mafia: 2, detective: 1 }, mode: 'avenger' });
    await host.until(() => host.room.mode === 'avenger', 'avenger');
    host.send({ t: 'deal' });
    await host.until(() => host.view?.phase === 'deal', 'Avenger deals');
  });

  it('the Sniper mode deals the count the host chose inside its range (10 players: 2, not the old 3)', async () => {
    const players = await table(10);
    const by = await start(players, 'sniper', 2);
    expect(by('mafia')).toHaveLength(2);
  });

  it('[Quin Q6] the count is dealt by the build that chose it: a 1.4.0 host picks 2, drops, and a 1.3.1 phone that takes over still deals 2', async () => {
    const players = await table(10, [ROLES14_BUILD, 100024, ...Array(8).fill(ROLES14_BUILD)]);
    const [host, old] = players;
    host.send({ t: 'setup', buzzMax: 3, rules: OFF, counts: { mafia: 2, detective: 1 }, mode: 'sniper' });
    await host.until(() => host.room.mode === 'sniper' && host.room.counts.mafia === 2, 'setup');
    host.ws.close();
    await old.until(() => old.room.members.some((m: any) => m.host && m.uid === old.me?.uid) || old.room.members.findIndex((m: any) => m.host) === 1, 'he holds the controls');
    old.send({ t: 'deal' });
    const rest = players.slice(1);
    await Promise.all(rest.map(p => p.until(() => p.view?.phase === 'deal', 'deal')));
    const m = rest.find(p => p.view.role === 'mafia')!;
    expect(m.view.mates.length + 1).toBe(2);
  });
});

describe('Cupid and the Silencer online', () => {
  it('Cupid links two; each lover learns the other\'s name and side (R4)', async () => {
    const players = await table(8);
    const by = await start(players, 'lovers', 2);
    const cupid = by('cupid')[0], cits = by('citizen');
    expect(cupid.view.night.key).toBe('cupid');
    await night(players, new Map([[cupid, { choice: cits[0].view.seat, pair: cits[1].view.seat }]]));
    await cits[0].until(() => cits[0].view.phase !== 'night', 'morning');
    if (!cits[0].view.alive || !cits[1].view.alive) return;  // the Mafia's first pick killed one (covered by the engine tests)
    expect(cits[0].view.lover).toEqual({ seat: cits[1].view.seat, side: 'town' });
  });

  it('the Silencer: the morning names who can\'t vote; his vote is refused', async () => {
    const players = await table(11);
    const by = await start(players, 'lonewolves', 3);
    const mafia = by('mafia'), sil = mafia.find(p => p.view.silencer === p.view.seat)!;
    expect(sil.view.night.silence).toBeDefined();
    const target = by('citizen')[0];
    await night(players, new Map([[sil, { silence: target.view.seat }]]));
    const host = players[0];
    await host.until(() => host.view.phase === 'morning' || host.view.phase === 'end', 'morning');
    if (host.view.phase === 'end' || !target.view.alive || host.view.hunt) return;
    expect(host.view.silenced).toBe(target.view.seat);
    host.send({ t: 'startDay' }); await host.until(() => host.view.phase === 'day', 'day');
    host.send({ t: 'startVote', open: false }); await host.until(() => host.view.phase === 'vote', 'vote');
    expect(target.view.ph).toBe('voted');
    target.send({ t: 'vote', choice: 0, id: target.view.voteId });
    await target.until(() => target.got(m => m.t === 'err' && m.error === 'done'), 'refused');
  });
});

describe('saved, counted and readable by older phones (migration 0015, D3, D8)', () => {
  it('a Serial Killer win and a Cupid seat are saved; a phone before 1.4.0 reads "citizens" and Citizen, 1.4.0 the real ones', async () => {
    const a = await account('Kx' + Math.random().toString(36).slice(2, 6));
    await DB().batch([
      DB().prepare("INSERT INTO games (id, host_id, winner, days, rules, log, stats, played_at) VALUES ('k1', ?, 'killer', 2, '{}', '[]', '{}', 1)").bind(a.id),
      DB().prepare("INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES ('k1', 0, ?, 'A', 'killer', 1), ('k1', 1, NULL, 'B', 'cupid', 0), ('k1', 2, NULL, 'C', 'mafia', 0)").bind(a.id),
      DB().prepare("INSERT INTO games (id, host_id, winner, days, rules, log, stats, played_at) VALUES ('d1', NULL, 'draw', 2, '{}', '[]', '{}', 2), ('l1', NULL, 'lovers', 2, '{}', '[]', '{}', 3)"),
    ]);
    await expect(DB().prepare("INSERT INTO games (id, winner, days, rules, log, stats, played_at) VALUES ('x1', 'nope', 1, '{}', '[]', '{}', 1)").run()).rejects.toThrow();
    const list = (await api('GET', '/v1/games', a.token)).json.games;
    expect(list[0]).toMatchObject({ winner: 'citizens', winner2: 'killer', role: 'citizen', role2: 'killer' });
    const page = (await api('GET', '/v1/games/k1', a.token)).json;
    expect([page.winner, page.winner2]).toEqual(['citizens', 'killer']);
    expect(page.players.map((p: any) => p.role)).toEqual(['citizen', 'citizen', 'mafia']);
    const note = sum(JSON.stringify({ names: ['A', 'B', 'C', 'D'], roles: ['killer', 'cupid', 'mafia', 'citizen'], winner: 'lovers' }), 1);
    expect(note).toMatchObject({ winner: 'citizens', winner2: 'lovers', role: 'citizen', role2: 'cupid' });
  });

  it('stats per seat: the couple wins with the Lovers (a Mafia lover too); the Serial Killer wins his game; a draw is nobody\'s; he is no townsman', () => {
    const g = (winner: SGame['winner'], roles: any[], lovers?: [number, number]): SGame => ({ id: Math.random() + '', source: 'online', playedAt: 1, winner, days: 1,
      seats: roles.map((role, i) => ({ key: 'p' + i, userId: null, name: 'p' + i, role, alive: true })),
      ev: { first: null, kills: [], outs: [], saves: [], caught: [], ...(lovers ? { lovers } : {}) } });
    const games = [g('lovers', ['mafia', 'citizen', 'cupid', 'mafia'], [0, 1]), g('killer', ['killer', 'citizen', 'mafia', 'citizen']), g('draw', ['killer', 'mafia', 'citizen', 'citizen'])];
    expect(profile(games, 'p0')).toMatchObject({ games: 3, wins: 2 });  // the Mafia lover and the Serial Killer won; the draw is no win
    expect(profile(games, 'p1').wins).toBe(1);
    expect(profile(games, 'p3').wins).toBe(0);
    const p0 = board(games, 1).ranked.find(r => r.key === 'p0')!;
    expect([p0.mg, p0.tg]).toEqual([1, 0]);  // the Serial Killer games count neither as Mafia nor as town
  });
});
