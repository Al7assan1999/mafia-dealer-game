// Sprint 19 (1.2.0): the suggestions box. A signed-in player sends a suggestion or a problem (one screenshot at most);
// the admin reads, marks done (the player gets a push) and empties it. Limits against spam: 3 a day, 5 waiting per
// player, 300 in the whole box (his numbers, FEEDBACK_LIMITS).
import { Hono } from 'hono';
import { FEEDBACK_LIMITS, FeedbackAction, FeedbackIn, MAX_SHOT_BYTES } from '@mafia/protocol';
import { sendPush } from './push.ts';
import { adminRoutes } from './safety.ts';
import { allow, ApiErr, body, card, DAY, fromB64, type AppEnv, type UserRow } from './lib.ts';

interface Row { id: string; user_id: string; kind: 'idea' | 'problem'; text: string; info: string; game_id: string | null; status: 'new' | 'read' | 'done'; created_at: number; updated_at: number; shot: number }
const COLS = 'f.id, f.user_id, f.kind, f.text, f.info, f.game_id, f.status, f.created_at, f.updated_at, f.image IS NOT NULL AS shot';
const out = (r: Row) => ({ id: r.id, kind: r.kind, text: r.text, info: JSON.parse(r.info), gameId: r.game_id, status: r.status, at: r.created_at, shot: !!r.shot });

/** Can this player send now? null, or why not ('day' | 'waiting' | 'full'), checked before they type (S19-2 AC1). */
async function blocked(db: D1Database, uid: string, now: number): Promise<'day' | 'waiting' | 'full' | null> {
  const [day, mine, all] = await db.batch([
    db.prepare("SELECT count FROM rate_limits WHERE key = ? AND window_start > ?").bind('fb:' + uid, now - DAY),
    db.prepare("SELECT COUNT(*) AS n FROM feedback WHERE user_id = ? AND status = 'new'").bind(uid),
    db.prepare('SELECT COUNT(*) AS n FROM feedback'),
  ]);
  if (((day.results[0] as { count?: number } | undefined)?.count ?? 0) >= FEEDBACK_LIMITS.perDay) return 'day';
  if ((mine.results[0] as { n: number }).n >= FEEDBACK_LIMITS.waiting) return 'waiting';
  if ((all.results[0] as { n: number }).n >= FEEDBACK_LIMITS.box) return 'full';
  return null;
}

export const feedbackRoutes = new Hono<AppEnv>();
/** P3 "My messages": what I sent and how far it got, and whether I can send another now. */
feedbackRoutes.get('/', async c => {
  const db = c.env.DB, me = c.var.user;
  const { results } = await db.prepare(`SELECT ${COLS} FROM feedback f WHERE f.user_id = ? ORDER BY f.created_at DESC`).bind(me.id).all<Row>();
  return c.json({ mine: results.map(out), blocked: await blocked(db, me.id, c.var.deps.now()) });
});
feedbackRoutes.post('/', async c => {
  const f = await body(c, FeedbackIn), db = c.env.DB, me = c.var.user, now = c.var.deps.now();
  const why = await blocked(db, me.id, now);
  if (why) throw new ApiErr(429, why === 'full' ? 'box_full' : 'slow_down');
  let image: Uint8Array | null = null;
  if (f.image) {
    image = fromB64(f.image.slice(f.image.indexOf(',') + 1));
    if (!image) throw new ApiErr(400, 'bad_request');
    if (image.length > MAX_SHOT_BYTES) throw new ApiErr(413, 'too_big');
    // [Quin Q6] a JPEG, whatever the data: URL claims (the phone only makes JPEGs; no PNG decompression bombs for the admin)
    if (image[0] !== 0xff || image[1] !== 0xd8 || image[2] !== 0xff) throw new ApiErr(400, 'bad_request');
  }
  // P2: only a game the sender played in
  if (f.gameId && !(await db.prepare('SELECT 1 FROM game_players WHERE game_id = ? AND user_id = ?').bind(f.gameId, me.id).first())) throw new ApiErr(404, 'not_found');
  if (!(await allow(db, 'fb:' + me.id, FEEDBACK_LIMITS.perDay, DAY, now))) throw new ApiErr(429, 'slow_down');
  const id = crypto.randomUUID();
  await db.prepare('INSERT INTO feedback (id, user_id, kind, text, info, game_id, image, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
    .bind(id, me.id, f.kind, f.text, JSON.stringify(f.info), f.gameId ?? null, image, now, now).run();
  return c.json({ id });
});

// ---------------------------------------------------------------- the box (admin only: safety.ts checks every call)
adminRoutes.get('/feedback', async c => {
  const db = c.env.DB;
  const { results } = await db.prepare(`SELECT ${COLS} FROM feedback f ORDER BY f.created_at DESC LIMIT ${FEEDBACK_LIMITS.box}`).all<Row>();
  const ids = [...new Set(results.map(r => r.user_id))];
  const users = ids.length ? (await db.prepare(`SELECT * FROM users WHERE id IN (${ids.map(() => '?').join(',')})`).bind(...ids).all<UserRow>()).results : [];
  const by = new Map(users.map(u => [u.id, u]));
  return c.json({ items: results.map(r => ({ ...out(r), from: by.has(r.user_id) ? card(by.get(r.user_id)!, 'none') : null })), unread: results.filter(r => r.status === 'new').length });
});
/** One item; opening it marks it read. The screenshot is its own request (raw bytes, no base64 work, Quin Q2). */
adminRoutes.get('/feedback/:id', async c => {
  const db = c.env.DB, id = c.req.param('id'), now = c.var.deps.now();
  const r = await db.prepare(`SELECT ${COLS} FROM feedback f WHERE f.id = ?`).bind(id).first<Row>();
  if (!r) throw new ApiErr(404, 'not_found');
  if (r.status === 'new') await db.prepare("UPDATE feedback SET status = 'read', updated_at = ? WHERE id = ?").bind(now, id).run();
  const u = await db.prepare('SELECT * FROM users WHERE id = ?').bind(r.user_id).first<UserRow>();
  return c.json({ ...out({ ...r, status: r.status === 'new' ? 'read' : r.status }), from: u ? card(u, 'none') : null });
});
adminRoutes.get('/feedback/:id/image', async c => {
  const r = await c.env.DB.prepare('SELECT image FROM feedback WHERE id = ?').bind(c.req.param('id')).first<{ image: ArrayBuffer | null }>();
  if (!r?.image) throw new ApiErr(404, 'not_found');
  return c.body(new Uint8Array(r.image), 200, { 'content-type': 'image/jpeg', 'cache-control': 'private, no-store' });
});
/** Read / Done. P1: Done tells the player (a push; their "My messages" shows it too). */
adminRoutes.post('/feedback/:id', async c => {
  const { status } = await body(c, FeedbackAction), db = c.env.DB, id = c.req.param('id'), now = c.var.deps.now();
  const r = await db.prepare('SELECT user_id, kind, status FROM feedback WHERE id = ?').bind(id).first<{ user_id: string; kind: 'idea' | 'problem'; status: string }>();
  if (!r) throw new ApiErr(404, 'not_found');
  await db.prepare('UPDATE feedback SET status = ?, updated_at = ? WHERE id = ?').bind(status, now, id).run();
  if (status === 'done' && r.status !== 'done') await sendPush(c.env, c.var.deps, r.user_id, 'feedback_done', { code: r.kind, tag: 'feedback:' + id, data: { id } });
  return c.json({ ok: true });
});
/** Delete one, for good (the screenshot too). */
adminRoutes.delete('/feedback/:id', async c => {
  const r = await c.env.DB.prepare('DELETE FROM feedback WHERE id = ?').bind(c.req.param('id')).run();
  if (!r.meta.changes) throw new ApiErr(404, 'not_found');
  return c.json({ ok: true });
});
/** Empty the box, for good: what the admin saw (?upto=<newest at>); anything that came in after stays (Quin Q12). */
adminRoutes.delete('/feedback', async c => {
  const upto = Number(c.req.query('upto') ?? Number.MAX_SAFE_INTEGER);
  if (!Number.isFinite(upto)) throw new ApiErr(400, 'bad_request');
  const r = await c.env.DB.prepare('DELETE FROM feedback WHERE created_at <= ?').bind(upto).run();
  return c.json({ deleted: r.meta.changes });
});
