// Sprint 8: stats (the old app's rules), the Everyone leaderboard, profiles, title notes, and the old history import.
import { describe, expect, it } from 'vitest';
import { board, profile, refreshTitles, type SGame } from '../src/stats.ts';
import { setup } from './helpers.ts';
import { DB } from './live.ts';

type T = Awaited<ReturnType<typeof setup>>;
type Seat = { id?: string; name: string; role: 'mafia' | 'doctor' | 'detective' | 'citizen'; alive?: boolean };
let n = 0;
/** A finished game straight into D1 (online unless said), with engine-style stats. */
async function game(seats: Seat[], winner: 'mafia' | 'citizens', o: { valid?: boolean; source?: 'online' | 'wifi'; at?: number; first?: number | null; saves?: number[]; caught?: [number, number][]; kills?: number[]; outs?: number[] } = {}) {
  const id = 'g' + ++n, db = DB();
  await db.batch([
    db.prepare("INSERT INTO games (id, host_id, winner, days, valid, rules, log, stats, played_at, source) VALUES (?, NULL, ?, 2, ?, '{}', '[]', ?, ?, ?)")
      .bind(id, winner, o.valid === false ? 0 : 1, JSON.stringify({ first: o.first ?? null, kills: o.kills ?? [], outs: o.outs ?? [], saves: o.saves ?? [], caught: o.caught ?? [] }), o.at ?? 1_800_000_000_000 - 3600e3, o.source ?? 'online'),
    ...seats.map((s, i) => db.prepare('INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES (?, ?, ?, ?, ?, ?)').bind(id, i, s.id ?? null, s.name, s.role, s.alive === false ? 0 : 1)),
  ]);
  return id;
}
const sg = (seats: [string, SGame['seats'][0]['role']][], winner: SGame['winner'], ev: Partial<SGame['ev']> = {}): SGame =>
  ({ id: 'x' + ++n, source: 'online', playedAt: n, winner, days: 1, seats: seats.map(([k, role]) => ({ key: k, userId: null, name: k, role, alive: true })),
    ev: { first: null, kills: [], outs: [], saves: [], caught: [], ...ev } });

describe('stats rules (the old app\'s)', () => {
  it('leaderboard: win rate with a minimum, then wins, then games; Mafia / Citizen split; the five titles', () => {
    const g = [
      sg([['A', 'mafia'], ['B', 'doctor'], ['C', 'detective'], ['D', 'citizen']], 'mafia', { first: 3, kills: [3] }),
      sg([['A', 'mafia'], ['B', 'citizen'], ['C', 'detective'], ['D', 'doctor']], 'mafia', { first: 1, kills: [1], saves: [3] }),
      sg([['A', 'citizen'], ['B', 'mafia'], ['C', 'detective'], ['D', 'doctor']], 'citizens', { first: 3, kills: [3], caught: [2], saves: [3] }),
      sg([['A', 'doctor'], ['B', 'mafia'], ['C', 'citizen'], ['D', 'detective']], 'citizens', { caught: [3], saves: [0] }),
      sg([['E', 'mafia'], ['B', 'citizen'], ['C', 'citizen'], ['D', 'doctor']], 'mafia'),
    ];
    const { ranked, titles } = board(g, 3);
    expect(ranked.map(p => [p.key, p.w, p.g, p.q])).toEqual([['A', 4, 4, true], ['C', 2, 5, true], ['D', 2, 5, true], ['B', 0, 5, true], ['E', 1, 1, false]]);
    expect(ranked[0]).toMatchObject({ mg: 2, mw: 2, tg: 2, tw: 2 });
    expect(titles.best?.key).toBe('A');
    expect(titles.mafia?.key).toBe('A');            // 2 of 2 as Mafia
    expect(titles.det?.key).toBe('C');              // the first with the most catches (C 1, D 1: C counted first)
    expect(titles.doc?.key).toBe('D');              // 2 saves
    expect(titles.first?.key).toBe('D');            // killed first twice
    expect(board(g.slice(0, 2), 3).titles.best).toBeNull();  // nobody has 3 games
  });

  it('profile: best role, sides, killed most by, best partner, moments, last 8 games newest first', () => {
    const g = [
      sg([['A', 'mafia'], ['B', 'mafia'], ['C', 'citizen'], ['D', 'citizen'], ['E', 'doctor'], ['F', 'citizen']], 'mafia'),
      sg([['A', 'mafia'], ['B', 'mafia'], ['C', 'citizen'], ['D', 'citizen'], ['E', 'doctor'], ['F', 'citizen']], 'mafia'),
      sg([['A', 'citizen'], ['B', 'mafia'], ['C', 'mafia'], ['D', 'citizen'], ['E', 'doctor'], ['F', 'citizen']], 'mafia', { kills: [0], outs: [] }),
      sg([['A', 'detective'], ['B', 'mafia'], ['C', 'citizen'], ['D', 'mafia'], ['E', 'doctor'], ['F', 'citizen']], 'citizens', { caught: [0], outs: [0] }),
    ];
    const p = profile(g, 'A');
    expect(p).toMatchObject({ games: 4, wins: 3, best: 'mafia', mafia: [2, 2], side: [2, 1], moments: { saves: 0, caught: 1, killed: 1, out: 1 } });
    expect(p.nemesis).toMatchObject({ name: 'B', n: 1 });   // killed by B and C's Mafia; B first
    expect(p.partner).toMatchObject({ name: 'B', n: 2 });
    expect(p.form).toEqual([true, false, true, true]);      // newest first
  });
});

describe('the stats screen\'s data', () => {
  async function four(t: T) { return Promise.all(['Sami', 'Dareer', 'Hokan', 'Fater'].map(h => t.user(h))); }

  it('Mine: my online and approved Wi-Fi games, valid only; others\' games and invalid games never count; source and 30-day filters', async () => {
    const t = await setup(), [a, b, c, d] = await four(t), e = await t.user('Halawy');
    const seats = (x = a) => [{ id: x.id, name: 'Sami', role: 'mafia' as const }, { id: b.id, name: 'Dareer', role: 'doctor' as const }, { id: c.id, name: 'Hokan', role: 'citizen' as const }, { id: d.id, name: 'Fater', role: 'citizen' as const }];
    await game(seats(), 'mafia');
    await game(seats(), 'citizens', { source: 'wifi', at: 1_800_000_000_000 - 40 * 86400e3 });
    await game(seats(), 'mafia', { valid: false });
    await game([{ id: e.id, name: 'Halawy', role: 'mafia' }, { id: b.id, name: 'Dareer', role: 'doctor' }, { id: c.id, name: 'Hokan', role: 'citizen' }, { id: d.id, name: 'Fater', role: 'citizen' }], 'mafia');
    const s = (await t.call('GET', '/v1/stats', { token: a.token })).json;
    expect(s.games).toBe(2);
    expect(s.me).toMatchObject({ g: 2, w: 1, me: true, handle: 'Sami' });
    expect(s.board.map((r: any) => r.handle)).not.toContain('Halawy');
    expect((await t.call('GET', '/v1/stats?source=wifi', { token: a.token })).json.games).toBe(1);
    expect((await t.call('GET', '/v1/stats?days=30', { token: a.token })).json.games).toBe(1);
  });

  it('Everyone: all accounts, 10-game minimum, the switch hides you (and gives the title to the next), banned never show, top 100', async () => {
    const t = await setup(), [a, b, c, d] = await four(t);
    for (let i = 0; i < 10; i++) await game([{ id: a.id, name: 'Sami', role: 'mafia' }, { id: b.id, name: 'Dareer', role: 'doctor' }, { id: c.id, name: 'Hokan', role: 'citizen' }, { id: d.id, name: 'Fater', role: 'citizen' }], i < 7 ? 'mafia' : 'citizens', { caught: [], saves: i < 3 ? [1] : [] });
    let s = (await t.call('GET', '/v1/stats?board=all', { token: d.token })).json;
    expect(s.minGames).toBe(10);
    expect(s.board[0]).toMatchObject({ handle: 'Sami', rank: 1, w: 7, g: 10 });
    expect(s.board.slice(1).map((r: any) => r.rank)).toEqual([2, 2, 2]);  // the three Citizens always shared a side: same record, one rank
    expect(s.titles.best.handle).toBe('Sami');
    expect(s.titles.doc.handle).toBe('Dareer');
    expect(s.me).toMatchObject({ handle: 'Fater', me: true });
    expect((await t.call('PATCH', '/v1/me', { token: a.token, body: { onBoard: false } })).json.user.onBoard).toBe(false);
    s = (await t.call('GET', '/v1/stats?board=all', { token: d.token })).json;
    expect(s.board.map((r: any) => r.handle)).not.toContain('Sami');
    expect(s.titles.best.handle).not.toBe('Sami');
    expect((await t.call('GET', '/v1/stats', { token: a.token })).json.me.g).toBe(10);  // my own stats unchanged
    await DB().prepare('UPDATE users SET banned_at = 1 WHERE id = ?').bind(b.id).run();
    s = (await t.call('GET', '/v1/stats?board=all', { token: d.token })).json;
    expect(s.board.map((r: any) => r.handle)).not.toContain('Dareer');
    expect(s.titles.doc).toBeNull();
  });

  it('a game the host makes invalid leaves everyone\'s stats; a profile from the board', async () => {
    const t = await setup(), [a, b, c, d] = await four(t);
    const id = await game([{ id: a.id, name: 'Sami', role: 'mafia' }, { id: b.id, name: 'Dareer', role: 'doctor' }, { id: c.id, name: 'Hokan', role: 'citizen' }, { id: d.id, name: 'Fater', role: 'citizen' }], 'mafia', { kills: [2] });
    await DB().prepare('UPDATE games SET host_id = ? WHERE id = ?').bind(a.id, id).run();
    const p = (await t.call('GET', `/v1/stats/player?key=u:${c.id}`, { token: b.token })).json;
    expect(p).toMatchObject({ games: 1, wins: 0, nemesis: { name: 'sami', n: 1 }, card: { handle: 'Hokan' } });
    await t.call('PATCH', '/v1/games/' + id, { token: a.token, body: { valid: false } });
    expect((await t.call('GET', '/v1/stats', { token: b.token })).json.games).toBe(0);
    expect((await t.call('GET', `/v1/stats/player?key=u:${c.id}`, { token: b.token })).status).toBe(404);
    expect((await t.call('GET', '/v1/stats/player?key=bogus', { token: b.token })).status).toBe(400);
  });
});

describe('a title taken from you', () => {
  it('the old holder hears it in the bell (or a push when the app is closed); read and dismiss', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Dareer'), c = await t.user('Hokan'), d = await t.user('Fater');
    await t.call('PUT', '/v1/me/push', { token: a.token, body: { token: 'tok-sami-' + 'x'.repeat(20), lang: 'en' } });
    const seats = (m: string, doc: string) => [a, b, c, d].map(u => ({ id: u.id, name: u.id, role: (u.id === m ? 'mafia' : u.id === doc ? 'doctor' : 'citizen') as Seat['role'] }));
    for (let i = 0; i < 10; i++) await game(seats(c.id, a.id), 'citizens', { saves: [[a, b, c, d].findIndex(u => u.id === a.id)] });
    await refreshTitles(t.env, { push: async (_e, m) => { t.pushes.push(...m); return []; }, now: () => t.clock.t });
    expect(t.pushes).toHaveLength(0);  // the first holders: nobody lost anything
    for (let i = 0; i < 12; i++) await game(seats(c.id, b.id), 'citizens', { saves: [[a, b, c, d].findIndex(u => u.id === b.id)] });
    await refreshTitles(t.env, { push: async (_e, m) => { t.pushes.push(...m); return []; }, now: () => t.clock.t });
    expect(t.pushes.map(p => [p.channel, p.body])).toEqual([['titles', 'dareer took Best Doctor from you']]);
    const bell = (await t.call('GET', '/v1/notifications', { token: a.token })).json;
    expect(bell.notifications[0]).toMatchObject({ kind: 'title_lost', title: 'doc', from: { handle: 'Dareer' }, read: false });
    expect(bell.unread).toBe(1);
    await t.call('POST', '/v1/notifications/read', { token: a.token, body: { ids: [bell.notifications[0].id] } });
    expect((await t.call('GET', '/v1/notifications', { token: a.token })).json.unread).toBe(0);
    await t.call('DELETE', '/v1/notifications/' + bell.notifications[0].id, { token: a.token });
    expect((await t.call('GET', '/v1/notifications', { token: a.token })).json.notifications).toEqual([]);
  });
});

describe('importing the old app\'s history', () => {
  const old = (id: number, names: string[], o: Record<string, unknown> = {}) => ({ id, names, roles: ['mafia', 'doctor', 'citizen', 'citizen'].slice(0, names.length), alive: names.map(() => true),
    winner: 'mafia', days: 2, valid: true, hist: ['Night 1: …'], ev: { first: 2, saves: [], caught: [], kills: [2], outs: [] }, acc: null, ...o });
  const real = ['Alhassan', 'Dareer', 'Halawy', 'Sami'];
  const setList = (names: Record<string, string | null>) => DB().prepare("UPDATE settings SET value = ? WHERE key = 'old_players'").bind(JSON.stringify({ version: 1, names })).run();

  it('with no list yet nothing is kept; with the list only real games come in; duplicates and broken entries are counted', async () => {
    const t = await setup(), a = await t.user('Hassan');
    try {
      t.oldGroups.ABCD2345 = { exists: true, games: [old(1_790_000_000_000, real), old(1_790_000_100_000, ['Player 1', 'Player 2', 'Player 3', 'Player 4']),
        old(1_790_000_200_000, ['Alhassan', 'Dareer', 'Halawy', 'Stranger']), { id: 'bad' }, old(1_790_000_300_000, real, { roles: ['mafia'] })] };
      expect((await t.call('POST', '/v1/legacy/import', { token: a.token, body: { code: 'abcd-2345' } })).json).toEqual({ imported: 0, duplicates: 0, skipped: 5 });
      await setList({ Alhassan: null, Dareer: null, Halawy: null, Sami: null });
      expect((await t.call('POST', '/v1/legacy/import', { token: a.token, body: { code: 'ABCD2345' } })).json).toEqual({ imported: 1, duplicates: 0, skipped: 4 });
      expect((await t.call('POST', '/v1/legacy/import', { token: a.token, body: { code: 'ABCD2345' } })).json).toEqual({ imported: 0, duplicates: 1, skipped: 4 });
      const b = await t.user('Dareer');  // the friend imports the same group: nothing twice
      expect((await t.call('POST', '/v1/legacy/import', { token: b.token, body: { code: 'ABCD2345' } })).json.imported).toBe(0);
      const list = (await t.call('GET', '/v1/legacy/games', { token: a.token })).json.games;
      expect(list).toMatchObject([{ names: real, winner: 'mafia', valid: true, hist: ['Night 1: …'], seat: null, playedAt: 1_790_000_000_000 }]);
      expect((await t.call('GET', '/v1/legacy/games', { token: b.token })).json.games).toEqual([]);  // not mine until I claim my name
    } finally { await setList({}); }
  });

  it('"Which one were you?", the settings list linking names to accounts, and the old games in Mine (not in Everyone)', async () => {
    const t = await setup(), a = await t.user('Hassan'), b = await t.user('Dareer');
    try {
      await setList({ Alhassan: null, Dareer: '@Dareer', Halawy: null, Sami: null });
      t.oldGroups.QWER2345 = { exists: true, games: [old(1_790_000_000_000, real), old(1_790_000_500_000, real, { valid: false })] };
      await t.call('POST', '/v1/legacy/import', { token: a.token, body: { code: 'QWER2345' } });
      expect((await t.call('GET', '/v1/legacy/names', { token: a.token })).json).toEqual({ names: real.map(n => ({ name: n, taken: false })), mine: null });
      expect((await t.call('POST', '/v1/legacy/claim', { token: a.token, body: { name: 'alhassan' } })).json).toEqual({ ok: true, name: 'Alhassan' });
      expect((await t.call('POST', '/v1/legacy/claim', { token: b.token, body: { name: 'Alhassan' } })).status).toBe(409);
      expect((await t.call('POST', '/v1/legacy/claim', { token: b.token, body: { name: 'Nobody' } })).status).toBe(404);
      const mine = (await t.call('GET', '/v1/stats', { token: a.token })).json;
      expect(mine.games).toBe(1);  // the invalid one doesn't count
      expect(mine.me).toMatchObject({ g: 1, w: 1, mg: 1 });  // Alhassan was the Mafia, and won
      expect(mine.board.find((r: any) => r.handle === 'Dareer')).toMatchObject({ g: 1, w: 0 });  // linked by the settings list
      const hers = (await t.call('GET', '/v1/stats?source=old', { token: b.token })).json;
      expect(hers.games).toBe(1);  // Dareer's old game counts for her through the list
      expect((await t.call('GET', '/v1/stats?board=all', { token: a.token })).json.games).toBe(0);  // old games never on Everyone
      expect((await t.call('GET', '/v1/legacy/games', { token: b.token })).json.games).toHaveLength(2);
    } finally { await setList({}); }
  });

  it('a wrong code, an unknown group, the old server down, and too many imports', async () => {
    const t = await setup(), a = await t.user('Hassan');
    expect((await t.call('POST', '/v1/legacy/import', { token: a.token, body: { code: 'SHORT' } })).status).toBe(400);
    expect((await t.call('POST', '/v1/legacy/import', { token: a.token, body: { code: 'ZZZZ2345' } })).status).toBe(404);
    t.setOldDown(true);
    expect((await t.call('POST', '/v1/legacy/import', { token: a.token, body: { code: 'ZZZZ2345' } })).status).toBe(502);
    t.setOldDown(false);
    for (let i = 0; i < 8; i++) await t.call('POST', '/v1/legacy/import', { token: a.token, body: { code: 'ZZZZ2345' } });
    expect((await t.call('POST', '/v1/legacy/import', { token: a.token, body: { code: 'ZZZZ2345' } })).status).toBe(429);
  });
});
