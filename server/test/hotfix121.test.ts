// 1.2.1 hotfix: a tie leaves a title with its holder; linking an old name recounts the titles at once; Online includes
// the old app's games; migration 0013 gives Best Doctor back after the tie.
import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { board, refreshTitles, type SGame } from '../src/stats.ts';
import { setup } from './helpers.ts';
import { DB } from './live.ts';

let n = 0;
const sg = (seats: [string, SGame['seats'][0]['role']][], winner: SGame['winner'], ev: Partial<SGame['ev']> = {}): SGame =>
  ({ id: 'h' + ++n, source: 'online', playedAt: n, winner, days: 1, seats: seats.map(([k, role]) => ({ key: k, userId: k, name: k, role, alive: true })),
    ev: { first: null, kills: [], outs: [], saves: [], caught: [], ...ev } });
const titlesRow = async () => JSON.parse((await DB().prepare("SELECT value FROM settings WHERE key = 'titles'").first<{ value: string }>())?.value ?? '{}');

describe('a tie keeps the title with its holder', () => {
  // A and B: one save each, one first-kill each, the same record
  const g = [
    sg([['A', 'doctor'], ['B', 'citizen'], ['M', 'mafia'], ['C', 'citizen']], 'citizens', { saves: [0], first: 0 }),
    sg([['A', 'citizen'], ['B', 'doctor'], ['M', 'mafia'], ['C', 'citizen']], 'citizens', { saves: [1], first: 1 }),
    sg([['A', 'citizen'], ['B', 'citizen'], ['M', 'mafia'], ['C', 'citizen']], 'citizens'),
  ];
  it('the holder keeps it on a tie, whoever comes first in the games', () => {
    expect(board(g, 3).titles.doc?.key).toBe('A');                        // no holder: the first in the list
    expect(board(g, 3, undefined, { doc: 'B', first: 'B', best: 'B' }).titles).toMatchObject({ doc: { key: 'B' }, first: { key: 'B' }, best: { key: 'B' } });
  });
  it('passing the holder takes it; a holder who is off the board (or not in the running) does not keep it', () => {
    const more = [...g, sg([['A', 'doctor'], ['B', 'citizen'], ['M', 'mafia'], ['C', 'citizen']], 'citizens', { saves: [0] })];
    expect(board(more, 3, undefined, { doc: 'B' }).titles.doc?.key).toBe('A');
    expect(board(g, 3, p => p.key !== 'B', { doc: 'B' }).titles.doc?.key).toBe('A');
    expect(board(g, 3, undefined, { doc: 'M' }).titles.doc?.key).toBe('A'); // M saved nobody
  });
  it('[Quin Q11] Best Mafia and Best Detective ties too; a Best player holder under the minimum does not keep it', () => {
    const m = [
      sg([['A', 'mafia'], ['B', 'citizen'], ['C', 'detective'], ['D', 'citizen']], 'mafia', { caught: [2] }),
      sg([['A', 'mafia'], ['B', 'citizen'], ['C', 'citizen'], ['D', 'detective']], 'citizens', { caught: [3] }),
      sg([['A', 'citizen'], ['B', 'mafia'], ['C', 'citizen'], ['D', 'citizen']], 'mafia'),
      sg([['A', 'citizen'], ['B', 'mafia'], ['C', 'citizen'], ['D', 'citizen']], 'citizens'),
    ];  // A and B: 1 of 2 as Mafia; C and D: one catch each
    expect(board(m, 3).titles).toMatchObject({ mafia: { key: 'A' }, det: { key: 'C' } });
    expect(board(m, 3, undefined, { mafia: 'B', det: 'D' }).titles).toMatchObject({ mafia: { key: 'B' }, det: { key: 'D' } });
    expect(board(m, 5, undefined, { best: 'B' }).titles.best).toBeNull();  // nobody has 5 games
  });
});

describe('the server keeps the holder', () => {
  it('a tie in the games sends no note, and the board shows the holder', async () => {
    const t = await setup(), [a, b, c, d] = [await t.user('Sami'), await t.user('Hassan'), await t.user('Hokan'), await t.user('Fater')], db = DB();
    const game = async (doc: number) => {
      const id = 'tg' + ++n;
      await db.batch([
        db.prepare("INSERT INTO games (id, host_id, winner, days, valid, rules, log, stats, played_at, source) VALUES (?, NULL, 'citizens', 2, 1, '{}', '[]', ?, ?, 'online')")
          .bind(id, JSON.stringify({ first: null, kills: [], outs: [], saves: [doc], caught: [] }), 1_800_000_000_000),
        ...[a, b, c, d].map((u, i) => db.prepare('INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES (?, ?, ?, ?, ?, 1)')
          .bind(id, i, u.id, u.id, i === doc ? 'doctor' : i === 2 ? 'mafia' : 'citizen')),
      ]);
    };
    const deps = { push: async (_e: unknown, m: any[]) => { t.pushes.push(...m); return []; }, now: () => t.clock.t };
    await game(1); await game(1); await game(1);
    await refreshTitles(t.env, deps);
    expect((await titlesRow()).doc).toBe(b.id);
    await game(0); await game(0); await game(0);  // Sami ties Hassan: 3 and 3
    await refreshTitles(t.env, deps);
    expect((await titlesRow()).doc).toBe(b.id);
    expect(t.pushes).toHaveLength(0);
    expect((await db.prepare("SELECT COUNT(*) AS n FROM bell_notes WHERE kind = 'title_lost'").first<{ n: number }>())!.n).toBe(0);
    expect((await t.call('GET', '/v1/stats', { token: a.token })).json.titles.doc).toMatchObject({ handle: 'Hassan' });
    await game(0);  // Sami passes him
    await refreshTitles(t.env, deps);
    expect((await titlesRow()).doc).toBe(a.id);
    expect((await db.prepare("SELECT user_id FROM bell_notes WHERE kind = 'title_lost'").all()).results).toEqual([{ user_id: b.id }]);
  });
});

describe('Old players and the titles; Online with the old games', () => {
  const real = ['Alhassan', 'Dareer', 'Halawy', 'Sami'];
  const old = (id: number, saves: number[]) => ({ id, names: real, roles: ['mafia', 'doctor', 'citizen', 'citizen'], alive: [true, true, true, true],
    winner: 'citizens', days: 2, valid: true, hist: [], ev: { first: 2, saves, caught: [], kills: [], outs: [] }, acc: null });
  const setList = (names: Record<string, string | null>) => DB().prepare("UPDATE settings SET value = ? WHERE key = 'old_players'").bind(JSON.stringify({ version: 2, names, tests: [] })).run();

  it('linking a name recounts the titles at once; the old games count under Online, not under Wi-Fi', async () => {
    const t = await setup(), boss = await t.user('Boss'), d = await t.user('Dareer');
    try {
      t.env.ADMIN_IDS = boss.id;
      t.oldGroups.TIES2345 = { exists: true, games: [old(1_790_000_000_000, [1]), old(1_790_000_100_000, [1])] };
      await t.call('POST', '/v1/legacy/import', { token: boss.token, body: { code: 'TIES2345' } });
      const put = (name: string, link?: string) => t.call('PUT', '/v1/legacy/players', { token: boss.token, body: { name, mark: 'real', ...(link ? { link } : {}) } });
      for (const x of ['Alhassan', 'Halawy', 'Sami']) await put(x);
      await put('Dareer', '@dareer');
      expect((await titlesRow()).doc).toBe(d.id);  // no game played since: the link itself recounted
      expect(t.pushes).toHaveLength(0);              // [Quin Q3] the admin's bookkeeping pushes nobody
      await t.call('PUT', '/v1/legacy/players', { token: boss.token, body: { name: 'Dareer', mark: 'test' } });
      expect((await titlesRow()).doc).toBeNull();    // a test name: its games stop counting, at once
      expect((await DB().prepare("SELECT COUNT(*) AS n FROM bell_notes WHERE kind = 'title_lost'").first<{ n: number }>())!.n).toBe(0);
      await put('Dareer', '@dareer');
      const online = (await t.call('GET', '/v1/stats?source=online', { token: d.token })).json;
      expect(online.games).toBe(2);
      expect(online.me).toMatchObject({ handle: 'Dareer', g: 2, sv: 2 });
      expect((await t.call('GET', '/v1/stats?source=wifi', { token: d.token })).json.games).toBe(0);
      expect((await t.call('GET', '/v1/stats?source=old', { token: d.token })).json.games).toBe(2);  // 1.2.0 phones still ask for it
      expect((await t.call('GET', `/v1/stats/player?key=u:${d.id}&source=online`, { token: d.token })).json.games).toBe(2);
    } finally { await setList({}); t.env.ADMIN_IDS = undefined; }
  });
});

describe('migration 0013', () => {
  it('puts Best Doctor back with Alhassan and removes the note, only if the tie left it with Sami', async () => {
    const al = 'a1edc5b5-8f62-44b8-85ec-ee03bb376a43', sami = 'f2250a3e-fe90-4606-a3af-206700603e23', db = DB();
    // the file's own statements, as CI applies them
    const sql: string[] = (env as any).TEST_MIGRATIONS.find((m: { name: string }) => m.name === '0013_title_tie.sql').queries;
    const set = (v: object) => db.prepare("INSERT INTO settings (key, value, updated_at) VALUES ('titles', ?, 0) ON CONFLICT (key) DO UPDATE SET value = excluded.value").bind(JSON.stringify(v)).run();
    const before = await titlesRow();
    try {
      await set({ doc: sami, first: sami });
      await db.prepare("INSERT INTO users (id, display, created_at) VALUES (?, 'Al', 0), (?, 'Sami', 0) ON CONFLICT DO NOTHING").bind(al, sami).run();
      await db.prepare("INSERT INTO bell_notes (id, user_id, kind, data, created_at, expires_at) VALUES ('n1', ?, 'title_lost', ?, 0, 1), ('n2', ?, 'title_lost', ?, 0, 1)")
        .bind(al, JSON.stringify({ title: 'doc', by: sami }), al, JSON.stringify({ title: 'best', by: sami })).run();
      for (const s of sql) await db.prepare(s).run();
      expect(await titlesRow()).toEqual({ doc: al, first: sami });
      expect((await db.prepare('SELECT id FROM bell_notes WHERE user_id = ?').bind(al).all()).results).toEqual([{ id: 'n2' }]);
      await set({ doc: 'someone-else' });
      for (const s of sql) await db.prepare(s).run();
      expect((await titlesRow()).doc).toBe('someone-else');  // already moved on: left alone
    } finally { await set(before); await db.prepare('DELETE FROM bell_notes WHERE user_id = ?').bind(al).run(); }
  });
});
