// Sprint 18 (1.1.0): the Bodyguard online, the 1.1.0 gate, Bodyguard games saved and counted (migration 0011).
import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_RULES } from '@mafia/engine';
import { MODES_BUILD } from '@mafia/protocol';
import { profile, type SGame } from '../src/stats.ts';
import { setup } from './helpers.ts';
import { account, api, connect, DB, type Sock } from './live.ts';

beforeEach(async () => { await setup(); });

async function table(n: number, builds: number[]) {
  const accts = await Promise.all(Array.from({ length: n }, (_, i) => account('B' + (i + 1) + 'x' + Math.random().toString(36).slice(2, 6))));
  const { json } = await api('POST', '/v1/rooms', accts[0].token);
  const players: Sock[] = [];
  for (const [i, a] of accts.entries()) {
    players.push(await connect(`/v1/rooms/${json.code}/ws?v=${builds[i] ?? MODES_BUILD}`, a.token));
    await players.at(-1)!.until(() => players.at(-1)!.room, 'room');
  }
  await players[0].until(() => players[0].room?.members.length === n, n + ' members');
  return players;
}
const setupMsg = (mode: string, bodyguard?: boolean) =>
  ({ t: 'setup', buzzMax: 3, rules: DEFAULT_RULES, counts: { mafia: 1, detective: 0 }, mode, ...(bodyguard != null ? { bodyguard } : {}) });

describe('the Bodyguard online (S18-4, S18-7)', () => {
  it('every table needs 1.1.0: a 1.0.0 or 1.0.1 phone keeps the deal from happening', async () => {
    expect(MODES_BUILD).toBe(100019);
    const players = await table(6, [MODES_BUILD, MODES_BUILD, MODES_BUILD, MODES_BUILD, 100017, 100018]);
    const [host] = players;
    host.send({ t: 'deal' });
    await host.until(() => host.got(m => m.t === 'err' && m.error === 'old_app'), 'old_app');
    expect(host.view).toBeNull();
  });

  it('the Bodyguard mode deals him; the Sniper mode adds him only with the switch on', async () => {
    const players = await table(6, []);
    const [host] = players;
    host.send(setupMsg('bodyguard'));
    await host.until(() => host.room.mode === 'bodyguard', 'mode');
    host.send({ t: 'deal' });
    await Promise.all(players.map(p => p.until(() => p.view?.phase === 'deal' && p.view.deal === 1, 'deal')));
    expect(players.map(p => p.view.role).sort()).toEqual(['bodyguard', 'citizen', 'detective', 'doctor', 'mafia', 'mafia']);
    host.send({ t: 'start' });
    await host.until(() => host.view?.phase === 'night', 'night');
    const bg = players.find(p => p.view.role === 'bodyguard')!;
    await bg.until(() => bg.view?.night?.key === 'bodyguard', 'his turn');
    expect(bg.view.night.opts.find((o: any) => o.seat === bg.view.seat).disabled).toBe(true);
  });

  it('the Sniper mode with the Bodyguard switch', async () => {
    const players = await table(6, []);
    const [host] = players;
    host.send(setupMsg('sniper', true));
    await host.until(() => host.room.mode === 'sniper' && host.room.bodyguard === true, 'switch');
    host.send({ t: 'deal' });
    await Promise.all(players.map(p => p.until(() => p.view?.phase === 'deal', 'deal')));
    expect(players.map(p => p.view.role).sort()).toEqual(['bodyguard', 'detective', 'doctor', 'mafia', 'mafia', 'sniper']);
  });
});

describe('Bodyguard games are saved and counted (migration 0011, S18-5)', () => {
  it('history takes a Bodyguard seat; games are untouched', async () => {
    const a = await account('Gx' + Math.random().toString(36).slice(2, 6));
    await DB().batch([
      DB().prepare("INSERT INTO games (id, host_id, winner, days, rules, log, stats, played_at) VALUES ('b1', ?, 'citizens', 1, '{}', '[]', '{}', 1)").bind(a.id),
      DB().prepare("INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES ('b1', 0, ?, 'A', 'bodyguard', 0), ('b1', 1, NULL, 'B', 'mafia', 0)").bind(a.id),
    ]);
    expect((await DB().prepare("SELECT role FROM game_players WHERE game_id = 'b1' AND seat = 0").first<{ role: string }>())!.role).toBe('bodyguard');
    await expect(DB().prepare("INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES ('b1', 2, NULL, 'C', 'nope', 1)").run()).rejects.toThrow();
  });

  it('stats: the Bodyguard is on the town\'s side; a 1.0.0 app still gets one of the roles it knows', () => {
    const g = (winner: SGame['winner']): SGame => ({ id: Math.random() + '', source: 'online', playedAt: 1, winner, days: 1,
      seats: ['mafia', 'bodyguard', 'citizen', 'citizen'].map((role: any, i) => ({ key: 'p' + i, userId: null, name: 'p' + i, role, alive: true })),
      ev: { first: null, kills: [], outs: [], saves: [], caught: [], guards: [1] } });
    const me = profile([g('citizens'), g('citizens'), g('mafia')], 'p1');
    expect(me.moments.guards).toBe(3);  // [Quin Q5] "Took the hit" on the profile
    expect(me.roles.bodyguard).toEqual([3, 2]);
    expect(me.side).toEqual([3, 2]);
    expect(me.best1).toBe('bodyguard');
    expect(['mafia', 'doctor', 'detective', 'citizen']).toContain(me.best);
  });
});
