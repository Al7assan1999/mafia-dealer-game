// [Quin Q4] migration 0015 and its rollback on a database that already has games: every 1.3.x row survives the
// migration (players and the approved Wi-Fi link too), and the rollback removes only the games 1.3.x can't hold.
import { describe, expect, it } from 'vitest';
import up from '../migrations/0015_wave2.sql?raw';
import down from '../rollbacks/0015_wave2.sql?raw';
import { account, DB } from './live.ts';

// one statement per `;` at a line end, comments dropped; one batch = one transaction (defer_foreign_keys holds)
const run = (sql: string) => DB().batch(sql.replace(/--.*$/gm, '').split(/;\s*$/m).map(q => q.trim()).filter(Boolean).map(q => DB().prepare(q)));
const game = (id: string, host: string, winner: string) => DB().prepare(
  `INSERT INTO games (id, host_id, winner, days, rules, log, stats, played_at, record, source) VALUES (?, ?, ?, 2, '{}', '[]', '{}', 1, '{}', 'wifi')`).bind(id, host, winner).run();
const seat = (id: string, n: number, user: string | null, role: string) => DB().prepare(
  `INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES (?, ?, ?, 'P', ?, 1)`).bind(id, n, user, role).run();
const wifi = (id: string, gameId: string, host: string) => DB().prepare(
  `INSERT INTO wifi_requests (id, host_id, record, record_hash, played_at, rules_version, status, created_at, expires_at, game_id)
   VALUES (?, ?, '{}', ?, 1, 1, 'approved', 1, 2, ?)`).bind(id, host, id, gameId).run();
const rows = async (q: string) => (await DB().prepare(q).all()).results;

describe('migration 0015 with games already saved', () => {
  it('keeps every 1.3.x game, its players and its Wi-Fi link; the rollback removes only the new results', async () => {
    const a = await account('mig15' + Math.random().toString(36).slice(2, 6));
    await run(down);                                                  // the 1.3.x schema
    await game('old', a.id, 'mafia'); await seat('old', 0, a.id, 'hunter'); await seat('old', 1, null, 'mafia');
    await wifi('w-old', 'old', a.id);
    await expect(game('bad', a.id, 'killer')).rejects.toThrow();     // 1.3.x can't hold a Serial Killer win
    await run(up);
    expect(await rows(`SELECT id, winner FROM games`)).toEqual([{ id: 'old', winner: 'mafia' }]);
    expect(await rows(`SELECT seat, user_id, role FROM game_players ORDER BY seat`)).toEqual([{ seat: 0, user_id: a.id, role: 'hunter' }, { seat: 1, user_id: null, role: 'mafia' }]);
    expect(await rows(`SELECT game_id FROM wifi_requests WHERE id = 'w-old'`)).toEqual([{ game_id: 'old' }]);
    await game('sk', a.id, 'killer'); await seat('sk', 0, a.id, 'killer');
    await game('cu', a.id, 'citizens'); await seat('cu', 0, a.id, 'cupid');
    await wifi('w-sk', 'sk', a.id);
    await run(down);
    expect(await rows(`SELECT id FROM games ORDER BY id`)).toEqual([{ id: 'old' }]);
    expect(await rows(`SELECT game_id, seat FROM game_players ORDER BY seat`)).toEqual([{ game_id: 'old', seat: 0 }, { game_id: 'old', seat: 1 }]);
    expect(await rows(`SELECT id, game_id FROM wifi_requests ORDER BY id`)).toEqual([{ id: 'w-old', game_id: 'old' }, { id: 'w-sk', game_id: null }]);  // Q5: an orphaned approval
    await run(up);                                                    // and forward again
    expect(await rows(`SELECT count(*) AS n FROM game_players`)).toEqual([{ n: 2 }]);
  });
});
