// Sprint 17 (1.0.0): modes in an online room, old apps kept out of the new roles, new-role games saved and counted.
import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_RULES } from '@mafia/engine';
import { MODES_BUILD } from '@mafia/protocol';
import { board, profile, type SGame } from '../src/stats.ts';
import { setup } from './helpers.ts';
import { account, api, connect, DB, type Sock } from './live.ts';

beforeEach(async () => { await setup(); });

/** n players in a new room; builds[i] is the app build player i connects with (undefined: none sent). */
async function table(n: number, builds: (number | undefined)[] = []) {
  const accts = await Promise.all(Array.from({ length: n }, (_, i) => account('M' + (i + 1) + 'x' + Math.random().toString(36).slice(2, 6))));
  const { json } = await api('POST', '/v1/rooms', accts[0].token);
  const players: Sock[] = [];
  for (const [i, a] of accts.entries()) {
    const q = builds[i] === -1 ? '?none=1' : builds[i] ? '?v=' + builds[i] : '';  // -1: a phone that sends no build
    players.push(await connect(`/v1/rooms/${json.code}/ws${q}`, a.token));
    await players.at(-1)!.until(() => players.at(-1)!.room, 'room');
  }
  await players[0].until(() => players[0].room?.members.length === n, n + ' members');
  return { code: json.code as string, players };
}
const setupMsg = (mode?: string) => ({ t: 'setup', buzzMax: 3, rules: DEFAULT_RULES, counts: { mafia: 1, detective: 0 }, ...(mode ? { mode } : {}) });

describe('modes online (S17-1, S17-4)', () => {
  it('the host picks a mode; the room shows it; a phone below 1.0.0 (or one that sends no build) keeps any deal from happening, Classic too', async () => {
    const t = await table(6, [MODES_BUILD, MODES_BUILD, MODES_BUILD, MODES_BUILD, MODES_BUILD - 1, -1]);
    const [host] = t.players;
    expect(host.room.mode).toBe('classic');
    host.send(setupMsg('sniper'));
    await host.until(() => host.room.mode === 'sniper', 'mode');
    host.send({ t: 'deal' });
    await host.until(() => host.got(m => m.t === 'err' && m.error === 'old_app'), 'old_app');
    expect(host.view).toBeNull();
    // his ruling (Q4): Classic waits for them too
    host.send(setupMsg());
    await host.until(() => host.room.mode === 'classic', 'classic');
    host.msgs.length = 0;
    host.send({ t: 'deal' });
    await host.until(() => host.got(m => m.t === 'err' && m.error === 'old_app'), 'old_app in Classic');
    expect(host.view).toBeNull();
  });

  it('with every phone on 1.0.0 the mode deals its fixed deck; too few players for the mode is refused', async () => {
    const t = await table(6, Array(6).fill(MODES_BUILD));
    const [host] = t.players;
    host.send(setupMsg('all'));
    await host.until(() => host.room.mode === 'all', 'mode');
    host.send({ t: 'deal' });
    await host.until(() => host.got(m => m.t === 'err' && m.error === 'modeFew'), 'modeFew');
    host.send(setupMsg('sniper'));
    await host.until(() => host.room.mode === 'sniper', 'mode');
    host.send({ t: 'deal' });
    await Promise.all(t.players.map(p => p.until(() => p.view?.phase === 'deal', 'deal')));
    const roles = t.players.map(p => p.view.role).sort();
    expect(roles).toEqual(['citizen', 'detective', 'doctor', 'mafia', 'mafia', 'sniper']);
    const mafia = t.players.filter(p => p.view.role === 'mafia');
    expect(mafia.every(p => p.view.sheikh === mafia[0].view.sheikh && p.view.sheikh != null)).toBe(true);
    expect(t.players.filter(p => p.view.role !== 'mafia').every(p => p.view.sheikh === null)).toBe(true);
  });
});

describe('new-role games are saved and counted (migration 0010, S17-5)', () => {
  it('history takes a Jester win and Sniper / Jester seats', async () => {
    const a = await account('Jx' + Math.random().toString(36).slice(2, 6));
    await DB().batch([
      DB().prepare("INSERT INTO games (id, host_id, winner, days, rules, log, stats, played_at) VALUES ('j1', ?, 'jester', 1, '{}', '[]', '{}', 1)").bind(a.id),
      DB().prepare("INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES ('j1', 0, ?, 'A', 'jester', 0), ('j1', 1, NULL, 'B', 'sniper', 1)").bind(a.id),
    ]);
    expect((await DB().prepare("SELECT count(*) n FROM game_players WHERE game_id = 'j1'").first<{ n: number }>())!.n).toBe(2);
  });

  it('stats: the Jester wins alone; the Sheikh counts as Mafia; the Sniper is on the Citizens\' side', () => {
    const seat = (key: string, role: any) => ({ key, userId: null, name: key, role, alive: true });
    const g = (winner: SGame['winner'], roles: string[]): SGame => ({ id: Math.random() + '', source: 'online', playedAt: 1, winner, days: 1,
      seats: roles.map((r, i) => seat('p' + i, r)), ev: { first: null, kills: [], outs: [], saves: [], caught: [] } });
    const games = [g('jester', ['mafia', 'sniper', 'jester', 'citizen']), g('citizens', ['mafia', 'sniper', 'jester', 'citizen'])];
    const { ranked } = board(games, 1);
    const by = Object.fromEntries(ranked.map(p => [p.key, p]));
    expect([by.p0.w, by.p1.w, by.p2.w, by.p3.w]).toEqual([0, 1, 1, 1]);
    expect([by.p1.tg, by.p2.tg]).toEqual([2, 0]);  // the Jester is on nobody's side
    const me = profile(games, 'p2');
    expect(me.roles.jester).toEqual([2, 1]);
    expect(profile(games, 'p1').side).toEqual([2, 1]);
    // [Quin Q1] a 0.4 app reads `best` as one of its four roles: a Jester-only player still gets one; 1.0.0 reads best1
    expect(['mafia', 'doctor', 'detective', 'citizen']).toContain(me.best);
    expect(me.best1).toBe('jester');
  });
});
