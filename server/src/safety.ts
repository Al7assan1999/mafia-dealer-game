// Google Play's user-generated-content rule: block, report, and the admin's moderation (dismiss or ban).
import { Hono } from 'hono';
import { BlockIn, ReportIn, ReportAction } from '@mafia/protocol';
import { ApiErr, body, card, type AppEnv, type Env, type UserRow } from './lib.ts';

/** Does either of them block the other? */
export async function blockedEither(db: D1Database, a: string, b: string) {
  return !!(await db.prepare('SELECT 1 FROM blocks WHERE (blocker_id = ?1 AND blocked_id = ?2) OR (blocker_id = ?2 AND blocked_id = ?1)').bind(a, b).first());
}
/** Does `blocker` block `blocked`? */
export async function blocks(db: D1Database, blocker: string, blocked: string) {
  return !!(await db.prepare('SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ?').bind(blocker, blocked).first());
}
export const isAdmin = (env: { ADMIN_IDS?: string }, id: string) => (env.ADMIN_IDS ?? '').split(',').map(s => s.trim()).filter(Boolean).includes(id);

/** Tells the room someone is in to reload who blocks whom (so its chat follows the change at once). */
async function refreshRoom(env: Env, code: string | null | undefined) {
  if (!code) return;
  await env.ROOM.get(env.ROOM.idFromName(code)).fetch('https://room/op', { method: 'POST', headers: { 'x-op': 'blocks' } });
}

export const blockRoutes = new Hono<AppEnv>();
blockRoutes.get('/', async c => {
  const { results } = await c.env.DB.prepare('SELECT u.* FROM blocks b JOIN users u ON u.id = b.blocked_id WHERE b.blocker_id = ? ORDER BY b.created_at DESC')
    .bind(c.var.user.id).all<UserRow>();
  return c.json({ blocked: results.map(u => card(u, 'none')) });
});
/** Block: their messages and DMs stop reaching me, no requests / invites from them, our friendship ends. They aren't told. */
blockRoutes.post('/', async c => {
  const { userId } = await body(c, BlockIn), db = c.env.DB, me = c.var.user;
  if (userId === me.id) throw new ApiErr(400, 'self');
  const u = await db.prepare('SELECT id FROM users WHERE id = ?').bind(userId).first();
  if (!u) throw new ApiErr(404, 'not_found');
  const [a, b] = me.id < userId ? [me.id, userId] : [userId, me.id];
  await db.batch([
    db.prepare('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING').bind(me.id, userId, c.var.deps.now()),
    db.prepare('DELETE FROM friendships WHERE a = ? AND b = ?').bind(a, b),
    db.prepare("DELETE FROM notifications WHERE user_id = ? AND from_id = ?").bind(me.id, userId),
  ]);
  await refreshRoom(c.env, me.room_code);
  return c.json({ ok: true });
});
blockRoutes.delete('/:userId', async c => {
  await c.env.DB.prepare('DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?').bind(c.var.user.id, c.req.param('userId')).run();
  await refreshRoom(c.env, c.var.user.room_code);
  return c.json({ ok: true });
});

export const reportRoutes = new Hono<AppEnv>();
/** Report a player, or one of their room messages (the room supplies the message, so it can't be made up). */
reportRoutes.post('/', async c => {
  const r = await body(c, ReportIn), db = c.env.DB, me = c.var.user, now = c.var.deps.now();
  if (r.userId === me.id) throw new ApiErr(400, 'self');
  const u = await db.prepare('SELECT * FROM users WHERE id = ?').bind(r.userId).first<UserRow>();
  if (!u) throw new ApiErr(404, 'not_found');
  let message: { text: string; at: number } | null = null;
  if (r.room && r.msgId != null) {
    const res = await c.env.ROOM.get(c.env.ROOM.idFromName(r.room)).fetch('https://room/op', { method: 'POST', headers: { 'x-op': 'msg', 'x-id': String(r.msgId), 'x-uid': me.id } });
    const m = res.ok ? await res.json<{ text: string; at: number; fromUid: string } | null>() : null;
    if (!m || m.fromUid !== u.id) throw new ApiErr(404, 'not_found');
    message = { text: m.text, at: m.at };
  }
  const snapshot = { display: u.display, handle: u.handle, room: r.room ?? null, message };
  await db.prepare('INSERT INTO reports (id, reporter_id, reported_id, reason, note, snapshot, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .bind(crypto.randomUUID(), me.id, u.id, r.reason, r.note ?? '', JSON.stringify(snapshot), now).run();
  return c.json({ ok: true });
});

export const adminRoutes = new Hono<AppEnv>();
adminRoutes.use('*', async (c, next) => { if (!isAdmin(c.env, c.var.user.id)) throw new ApiErr(403, 'forbidden'); await next(); });
/** The open reports, oldest first. */
adminRoutes.get('/reports', async c => {
  const { results } = await c.env.DB.prepare(
    `SELECT r.id, r.reason, r.note, r.snapshot, r.created_at, r.reported_id, rp.display AS reporter
     FROM reports r LEFT JOIN users rp ON rp.id = r.reporter_id WHERE r.status = 'open' ORDER BY r.created_at LIMIT 200`)
    .all<{ id: string; reason: string; note: string; snapshot: string; created_at: number; reported_id: string | null; reporter: string | null }>();
  return c.json({ reports: results.map(x => ({ id: x.id, reason: x.reason, note: x.note, at: x.created_at, reportedId: x.reported_id, reporter: x.reporter, ...JSON.parse(x.snapshot) })) });
});
/** Dismiss a report, or ban the reported account (signed out everywhere, no new sign-ins). */
adminRoutes.post('/reports/:id', async c => {
  const { action } = await body(c, ReportAction), db = c.env.DB, now = c.var.deps.now();
  const r = await db.prepare("SELECT reported_id FROM reports WHERE id = ? AND status = 'open'").bind(c.req.param('id')).first<{ reported_id: string | null }>();
  if (!r) throw new ApiErr(404, 'not_found');
  const steps = [db.prepare('UPDATE reports SET status = ?, handled_at = ? WHERE id = ?').bind(action === 'ban' ? 'banned' : 'dismissed', now, c.req.param('id'))];
  if (action === 'ban' && r.reported_id) {
    steps.push(db.prepare('UPDATE users SET banned_at = ? WHERE id = ?').bind(now, r.reported_id), db.prepare('DELETE FROM sessions WHERE user_id = ?').bind(r.reported_id));
  }
  await db.batch(steps);
  return c.json({ ok: true });
});
