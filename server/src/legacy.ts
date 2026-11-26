// The old app's history (S8-3). The old app's own Group history uploaded a phone's games to the old relay; here the new
// server reads that group by its code (server to server; the old app and relay are never changed). [S12-1] Every valid
// game is kept; it counts in stats once every name in it is marked a real player (the admin's Old players screen, or
// settings.old_players), and never if a name is marked a test name. Nothing waits on a list sent by chat.
import { Hono } from 'hono';
import { z } from 'zod';
import { nameKey, type Role } from '@mafia/engine';
import { allow, ApiErr, body, HOUR, sha256, type AppEnv, type Env } from './lib.ts';
import { isAdmin } from './safety.ts';
import { oldNameOwners, oldPlayers, oldStatus, refreshTitles } from './stats.ts';

export const OLD_RELAY = 'https://mafia-relay.mafiadealer.workers.dev';
/** Reads an old group: { exists, games }. Tests pass a fake. */
export type OldGroupReader = (env: Env, code: string) => Promise<{ exists: boolean; games: unknown[] }>;
// [R4] Cloudflare refuses a fetch from one Worker to another on the same account's workers.dev (error 1042), so in
// production the old relay is reached through the service binding OLD_RELAY; local dev (no binding) uses the URL.
export const relayReader: OldGroupReader = async (env, code) => {
  const req = new Request(`${OLD_RELAY}/g/${code}`, { headers: { 'user-agent': 'mafia-dealer-game-import' } });
  const r = await (env.OLD_RELAY ? env.OLD_RELAY.fetch(req) : fetch(req));
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

/** Imports an old group by its code. Answers { found, imported, duplicates, broken, waiting } (waiting: games with a name
 *  not marked yet, kept but not counted). */
legacyRoutes.post('/import', async c => {
  const { code } = await body(c, z.object({ code: z.string().transform(s => s.toUpperCase().replace(/[^A-Z0-9]/g, '')).pipe(z.string().regex(/^[A-Z2-9]{8}$/)) }).strict());
  const db = c.env.DB, me = c.var.user, now = c.var.deps.now();
  if (!isAdmin(c.env, me.id)) throw new ApiErr(403, 'forbidden');  // S13-1: only the admin imports (one truth for everyone)
  if (!(await allow(db, 'import:' + me.id, IMPORTS_PER_HOUR, HOUR, now))) throw new ApiErr(429, 'slow_down');
  let group: { exists: boolean; games: unknown[] };
  try { group = await c.var.deps.readOldGroup(c.env, code); } catch { throw new ApiErr(502, 'busy'); }
  if (!group?.exists) throw new ApiErr(404, 'not_found');
  const { real, tests } = await oldNameOwners(db);
  let found = 0, imported = 0, duplicates = 0, broken = 0, waiting = 0;
  for (const raw of (Array.isArray(group.games) ? group.games : []).slice(0, 500)) {
    const p = OldGame.safeParse(raw);
    if (!p.success) { broken++; continue; }  // what the old relay holds but isn't a game
    const g: OldGame = p.data;
    found++;
    if (oldStatus(g.names, real, tests) === 'waiting') waiting++;
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
  // skipped: what the 0.4.0 app reads (its import line fails without it): the entries that couldn't be read
  return c.json({ found, imported, duplicates, broken, waiting, skipped: broken });
});
const DAY_MS = 24 * HOUR;

/** History → Old app: the admin sees every imported game; a player, the old games under their linked name. Newest first. */
legacyRoutes.get('/games', async c => {
  const db = c.env.DB, me = c.var.user, { own, real, tests } = await oldNameOwners(db);
  const myNames = [...own].filter(([, u]) => u === me.id).map(([k]) => k), admin = isAdmin(c.env, me.id);
  const { results } = await db.prepare(
    `SELECT id, raw, played_at, valid FROM legacy_games WHERE ${admin ? '1 = 1 OR ' : ''}importer_id = ?${myNames.length ? ` OR id IN (SELECT game_id FROM legacy_seats WHERE name_key IN (${myNames.map(() => '?').join(',')}))` : ''}
     ORDER BY played_at DESC LIMIT 300`).bind(me.id, ...myNames).all<{ id: string; raw: string; played_at: number; valid: number }>();
  return c.json({ games: results.map(r => {
    const g = JSON.parse(r.raw) as OldGame, seat = g.names.findIndex(n => own.get(nameKey(n)) === me.id);
    return { id: r.id, playedAt: r.played_at, valid: !!r.valid, status: oldStatus(g.names, real, tests), winner: g.winner, days: g.days, names: g.names, roles: g.roles, alive: g.alive, hist: g.hist ?? [], seat: seat >= 0 ? seat : null };
  }) });
});

// ------------------------------------------------------------------ [S12-1] Old players (the admin marks every name found)
const PlayerMark = z.object({ name: z.string().min(1).max(30), mark: z.enum(['real', 'test', 'unknown']), link: z.string().max(40).nullable().optional() }).strict();

/** Every name found in imported games, how many games it is in, and how it is marked. Admin only. */
legacyRoutes.get('/players', async c => {
  if (!isAdmin(c.env, c.var.user.id)) throw new ApiErr(403, 'forbidden');
  const db = c.env.DB, { names, tests } = await oldPlayers(db);
  const { results } = await db.prepare('SELECT name_key, MIN(name) AS name, COUNT(DISTINCT game_id) AS games FROM legacy_seats GROUP BY name_key ORDER BY games DESC, name')
    .all<{ name_key: string; name: string; games: number }>();
  const realBy = new Map(Object.entries(names).map(([n, v]) => [nameKey(n), v])), testKeys = new Set(tests.map(nameKey));
  return c.json({ players: results.map(r => ({ name: r.name, games: r.games,
    mark: realBy.has(r.name_key) ? 'real' : testKeys.has(r.name_key) ? 'test' : 'unknown', link: realBy.get(r.name_key) ?? null })) });
});

/** Marks one name: a real player (optionally linked to an @handle), a test name, or back to unknown. Admin only. */
legacyRoutes.put('/players', async c => {
  if (!isAdmin(c.env, c.var.user.id)) throw new ApiErr(403, 'forbidden');
  const { name, mark, link } = await body(c, PlayerMark), db = c.env.DB, key = nameKey(name);
  let to: string | null = null;
  if (mark === 'real' && link) {
    const u = await db.prepare('SELECT id, handle FROM users WHERE handle = ? COLLATE NOCASE').bind(link.replace(/^@/, '')).first<{ id: string; handle: string }>();
    if (!u) throw new ApiErr(404, 'not_found');
    to = '@' + u.handle;
  }
  const { names, tests } = await oldPlayers(db);
  const next = { version: 2, names: Object.fromEntries(Object.entries(names).filter(([n]) => nameKey(n) !== key)), tests: tests.filter(n => nameKey(n) !== key) };
  if (mark === 'real') next.names[name] = to;
  if (mark === 'test') next.tests.push(name);
  await db.prepare("UPDATE settings SET value = ?, updated_at = ? WHERE key = 'old_players'").bind(JSON.stringify(next), c.var.deps.now()).run();
  await refreshTitles(c.env, c.var.deps, true);  // [1.2.1 hotfix] the titles change now, not at the next game; no notes (Q3)
  return c.json({ ok: true, name, mark, link: to });
});
