// The old app's history (S8-3). The old app's own Group history uploaded a phone's games to the old relay; here the new
// server reads that group once by its code (server to server; the old app and relay are never changed) and keeps only
// games whose every name is on the real-player list (settings.old_players), so test games stay out.
import { Hono } from 'hono';
import { z } from 'zod';
import { nameKey, type Role } from '@mafia/engine';
import { allow, ApiErr, body, HOUR, sha256, type AppEnv, type Env } from './lib.ts';
import { oldNameOwners } from './stats.ts';

export const OLD_RELAY = 'https://mafia-relay.mafiadealer.workers.dev';
/** Reads an old group: { exists, games }. Tests pass a fake. */
export type OldGroupReader = (env: Env, code: string) => Promise<{ exists: boolean; games: unknown[] }>;
export const relayReader: OldGroupReader = async (_env, code) => {
  const r = await fetch(`${OLD_RELAY}/g/${code}`, { headers: { 'user-agent': 'mafia-dealer-game-import' } });
  if (!r.ok) throw new Error('old relay ' + r.status);
  return await r.json() as { exists: boolean; games: unknown[] };
};

const ROLES = ['mafia', 'doctor', 'detective', 'citizen'] as const;
/** One old LogEntry, checked (the old relay hands back whatever phones uploaded). */
const OldGame = z.object({
  id: z.number().int().positive(),
  names: z.array(z.string().min(1).max(30)).min(4).max(20),
  roles: z.array(z.enum(ROLES)),
  alive: z.array(z.boolean()),
  winner: z.enum(['mafia', 'citizens']),
  days: z.number().int().min(1).max(200),
  valid: z.boolean(),
  hist: z.array(z.string().max(500)).max(400).optional(),
  ev: z.object({
    first: z.number().int().nullable().optional(), saves: z.array(z.number().int()).optional(), caught: z.array(z.string()).optional(),
    kills: z.array(z.number().int()).optional(), outs: z.array(z.number().int()).optional(),
  }).partial().optional(),
}).refine(g => g.roles.length === g.names.length && g.alive.length === g.names.length);
type OldGame = z.infer<typeof OldGame>;

export const IMPORTS_PER_HOUR = 10;
export const legacyRoutes = new Hono<AppEnv>();

/** The real-player list (for "Which one were you?") and my claimed name. */
legacyRoutes.get('/names', async c => {
  const db = c.env.DB, { list } = await oldNameOwners(db);
  const { results } = await db.prepare('SELECT name_key, user_id, name FROM legacy_claims').all<{ name_key: string; user_id: string; name: string }>();
  return c.json({ names: list.map(n => ({ name: n, taken: results.some(r => r.name_key === nameKey(n) && r.user_id !== c.var.user.id) })),
    mine: results.find(r => r.user_id === c.var.user.id)?.name ?? null });
});

/** "Which one were you?": claims an old name (one account per name; changing mine frees the old one). */
legacyRoutes.post('/claim', async c => {
  const { name } = await body(c, z.object({ name: z.string().min(1).max(30) }).strict()), db = c.env.DB;
  const { list } = await oldNameOwners(db), real = list.find(n => nameKey(n) === nameKey(name));
  if (!real) throw new ApiErr(404, 'not_found');
  const taken = await db.prepare('SELECT user_id FROM legacy_claims WHERE name_key = ?').bind(nameKey(real)).first<{ user_id: string }>();
  if (taken && taken.user_id !== c.var.user.id) throw new ApiErr(409, 'handle_taken');
  await db.batch([
    db.prepare('DELETE FROM legacy_claims WHERE user_id = ?').bind(c.var.user.id),
    db.prepare('INSERT INTO legacy_claims (name_key, user_id, name, created_at) VALUES (?, ?, ?, ?)').bind(nameKey(real), c.var.user.id, real, c.var.deps.now()),
  ]);
  return c.json({ ok: true, name: real });
});

/** Imports an old group by its code. Answers { imported, duplicates, skipped }. */
legacyRoutes.post('/import', async c => {
  const { code } = await body(c, z.object({ code: z.string().transform(s => s.toUpperCase().replace(/[^A-Z0-9]/g, '')).pipe(z.string().regex(/^[A-Z2-9]{8}$/)) }).strict());
  const db = c.env.DB, me = c.var.user, now = c.var.deps.now();
  if (!(await allow(db, 'import:' + me.id, IMPORTS_PER_HOUR, HOUR, now))) throw new ApiErr(429, 'slow_down');
  let group: { exists: boolean; games: unknown[] };
  try { group = await c.var.deps.readOldGroup(c.env, code); } catch { throw new ApiErr(502, 'busy'); }
  if (!group?.exists) throw new ApiErr(404, 'not_found');
  const { list } = await oldNameOwners(db), real = new Set(list.map(n => nameKey(n)));
  let imported = 0, duplicates = 0, skipped = 0;
  for (const raw of (Array.isArray(group.games) ? group.games : []).slice(0, 500)) {
    const p = OldGame.safeParse(raw);
    if (!p.success || !p.data.names.every(n => real.has(nameKey(n)))) { skipped++; continue; }  // test games, unknown players, broken entries
    const g: OldGame = p.data;
    const id = (await sha256(JSON.stringify([g.id, g.names, g.roles, g.winner, g.days]))).slice(0, 32);
    const playedAt = g.id > 1_600_000_000_000 && g.id < now + DAY_MS ? g.id : now;  // the old app's id is when the game ended
    const res = await db.batch([
      db.prepare(`INSERT INTO legacy_games (id, importer_id, group_code, raw, format, played_at, valid, winner, days, created_at)
                  VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING`)
        .bind(id, me.id, code, JSON.stringify(raw), playedAt, g.valid ? 1 : 0, g.winner, g.days, now),
      ...g.names.map((n, seat) => db.prepare('INSERT INTO legacy_seats (game_id, seat, name, name_key, role, alive) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING')
        .bind(id, seat, n, nameKey(n), g.roles[seat] as Role, g.alive[seat] ? 1 : 0)),
    ]);
    if (res[0].meta.changes) imported++; else duplicates++;
  }
  return c.json({ imported, duplicates, skipped });
});
const DAY_MS = 24 * HOUR;

/** History → Old app: the old games I imported or played in under my name (valid or not), newest first. */
legacyRoutes.get('/games', async c => {
  const db = c.env.DB, me = c.var.user, { own } = await oldNameOwners(db);
  const myNames = [...own].filter(([, u]) => u === me.id).map(([k]) => k);
  const { results } = await db.prepare(
    `SELECT id, raw, played_at, valid FROM legacy_games WHERE importer_id = ?${myNames.length ? ` OR id IN (SELECT game_id FROM legacy_seats WHERE name_key IN (${myNames.map(() => '?').join(',')}))` : ''}
     ORDER BY played_at DESC LIMIT 300`).bind(me.id, ...myNames).all<{ id: string; raw: string; played_at: number; valid: number }>();
  return c.json({ games: results.map(r => {
    const g = JSON.parse(r.raw) as OldGame, seat = g.names.findIndex(n => own.get(nameKey(n)) === me.id);
    return { id: r.id, playedAt: r.played_at, valid: !!r.valid, winner: g.winner, days: g.days, names: g.names, roles: g.roles, alive: g.alive, hist: g.hist ?? [], seat: seat >= 0 ? seat : null };
  }) });
});
