// Online rooms (create / look up), room invites and join requests, the bell, and the history of online games.
import { Hono } from 'hono';
import { Handled, Invite, JoinRequest, MarkGame, MarkRead, type Notification } from '@mafia/protocol';
import { notify } from './hub.ts';
import { dismissWifi, expire, readWifi, wifiNotes } from './wifi.ts';
import { bellNotes, dismissBell, readBell, refreshTitles } from './stats.ts';
import { allow, ApiErr, body, card, HOUR, type AppEnv, type Ctx, type UserRow } from './lib.ts';

export const ROOMS_PER_HOUR = 10, INVITES_PER_HOUR = 30, AGAIN_MS = 5e3, BELL_KEEP_MS = 30 * 24 * HOUR, BELL_MAX = 200;

const friendsWith = async (c: Ctx, other: string) => {
  const [a, b] = c.var.user.id < other ? [c.var.user.id, other] : [other, c.var.user.id];
  return !!(await c.env.DB.prepare("SELECT 1 FROM friendships WHERE a = ? AND b = ? AND status = 'accepted'").bind(a, b).first());
};
/** Invites and join requests share one limit: 30 an hour. */
async function inviteLimit(c: Ctx, now: number) {
  const n = await c.env.DB.prepare("SELECT COUNT(*) AS n FROM notifications WHERE from_id = ? AND kind IN ('invite', 'join_request', 'let_in') AND created_at > ?")
    .bind(c.var.user.id, now - HOUR).first<{ n: number }>();
  if ((n?.n ?? 0) >= INVITES_PER_HOUR) throw new ApiErr(429, 'slow_down');
}

export const rooms = new Hono<AppEnv>();
/** A new online room; the creator is its host. Players then connect to /v1/rooms/:code/ws. */
rooms.post('/', async c => {
  const db = c.env.DB, me = c.var.user, now = c.var.deps.now();
  if (!(await allow(db, 'room:' + me.id, ROOMS_PER_HOUR, HOUR, now))) throw new ApiErr(429, 'slow_down');
  // ponytail: rooms nobody ever joined have no Durable Object to close them; swept here after 2 days
  await db.prepare('UPDATE rooms SET closed_at = ? WHERE closed_at IS NULL AND created_at < ?').bind(now, now - 48 * HOUR).run();
  for (let i = 0; i < 8; i++) {
    const code = String(crypto.getRandomValues(new Uint32Array(1))[0] % 900000 + 100000);
    const r = await db.prepare('INSERT INTO rooms (code, host_id, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING').bind(code, me.id, now).run();
    if (r.meta.changes) return c.json({ code });
  }
  throw new ApiErr(503, 'busy');  // practically unreachable: 8 clashes among 900,000 codes
});
rooms.get('/:code', async c => {
  const r = await c.env.DB.prepare('SELECT r.status, u.display FROM rooms r JOIN users u ON u.id = r.host_id WHERE r.code = ? AND r.closed_at IS NULL')
    .bind(c.req.param('code')).first<{ status: string; display: string }>();
  if (!r) throw new ApiErr(404, 'no_room');
  return c.json({ open: true, status: r.status, host: r.display });
});

export const invites = new Hono<AppEnv>();
/** Invite a friend into my online room. Answering their join request this way tells them "X let you in". */
invites.post('/', async c => {
  const { userId, code } = await body(c, Invite), db = c.env.DB, me = c.var.user, now = c.var.deps.now();
  if (!(await friendsWith(c, userId))) throw new ApiErr(403, 'not_friends');
  if (me.room_code !== code) throw new ApiErr(403, 'not_member');
  const asked = await db.prepare("SELECT id FROM notifications WHERE kind = 'join_request' AND from_id = ? AND user_id = ? AND expires_at > ? AND handled_at IS NULL").bind(userId, me.id, now).first();
  const kind = asked ? 'let_in' : 'invite';
  const old = await db.prepare("SELECT id, created_at FROM notifications WHERE kind IN ('invite', 'let_in') AND from_id = ? AND user_id = ? AND room_code = ?")
    .bind(me.id, userId, code).first<{ id: string; created_at: number }>();
  if (old && !asked && now - old.created_at < AGAIN_MS) return c.json({ ok: true, dup: true });
  await inviteLimit(c, now);
  await db.batch([
    // their request to me is answered (kept in my bell as "Let in"); my older invites to them are replaced
    db.prepare("UPDATE notifications SET handled_at = ?3, result = 'let_in', read_at = COALESCE(read_at, ?3) WHERE kind = 'join_request' AND from_id = ?1 AND user_id = ?2 AND handled_at IS NULL").bind(userId, me.id, now),
    db.prepare("DELETE FROM notifications WHERE kind IN ('invite', 'let_in') AND from_id = ?2 AND user_id = ?1 AND room_code = ?3").bind(userId, me.id, code),
  ]);
  await notify(c.env, c.var.deps, userId, me, kind, code, now);
  // [N5] an invite from the room lets a player kicked from it back in
  await c.env.ROOM.get(c.env.ROOM.idFromName(code)).fetch('https://room/op', { method: 'POST', headers: { 'x-op': 'unkick', 'x-uid': userId } }).catch(() => null);
  return c.json({ ok: true, letIn: !!asked });
});

export const joinRequests = new Hono<AppEnv>();
/** Ask a friend who is in an open online lobby to let me in (they answer with an invite). */
joinRequests.post('/', async c => {
  const { userId } = await body(c, JoinRequest), db = c.env.DB, me = c.var.user, now = c.var.deps.now();
  if (!(await friendsWith(c, userId))) throw new ApiErr(403, 'not_friends');
  const u = await db.prepare('SELECT * FROM users WHERE id = ?').bind(userId).first<UserRow>();
  if (!u || !u.online || !u.show_online || u.room_status !== 'lobby') throw new ApiErr(409, 'not_open');
  const old = await db.prepare("SELECT created_at FROM notifications WHERE kind = 'join_request' AND from_id = ? AND user_id = ? AND handled_at IS NULL").bind(me.id, userId).first<{ created_at: number }>();
  if (old && now - old.created_at < AGAIN_MS) return c.json({ ok: true, dup: true });
  await inviteLimit(c, now);
  await db.prepare("DELETE FROM notifications WHERE kind = 'join_request' AND from_id = ? AND user_id = ?").bind(me.id, userId).run();
  await notify(c.env, c.var.deps, userId, me, 'join_request', null, now);
  return c.json({ ok: true });
});

export const notes = new Hono<AppEnv>();
notes.get('/', async c => {
  const now = c.var.deps.now(), db = c.env.DB, uid = c.var.user.id;
  // [N8] at most 200 per account: beyond that, the oldest answered or lapsed ones go first, then the oldest
  await db.prepare(`DELETE FROM notifications WHERE user_id = ?1 AND (created_at <= ?2 - ?3 OR id IN (
      SELECT id FROM notifications WHERE user_id = ?1 ORDER BY (handled_at IS NULL AND expires_at > ?2) ASC, created_at ASC
      LIMIT MAX(0, (SELECT COUNT(*) FROM notifications WHERE user_id = ?1) - ?4)))`).bind(uid, now, BELL_KEEP_MS, BELL_MAX).run();
  const { results } = await c.env.DB.prepare(
    // [N8] everything from the last 30 days stays (answered ones with their result, lapsed invites as Expired) until Cleared
    `SELECT n.id AS nid, n.kind, n.room_code, n.created_at AS nat, n.expires_at, n.read_at, n.handled_at, n.result, u.* FROM notifications n JOIN users u ON u.id = n.from_id
     WHERE n.user_id = ?1 AND n.created_at > ?2 - ?3
     ORDER BY n.created_at DESC LIMIT ?4`).bind(c.var.user.id, now, BELL_KEEP_MS, BELL_MAX)
    .all<UserRow & { nid: string; kind: Notification['kind']; room_code: string | null; nat: number; expires_at: number; read_at: number | null; handled_at: number | null; result: Notification['result'] }>();
  await expire(c.env, c.var.deps, now);
  const list: Notification[] = [...results.map(r => {
    const lapses = r.kind === 'invite' || r.kind === 'join_request' || r.kind === 'let_in';  // a friend request waits until answered
    const result = r.handled_at != null ? r.result : lapses && r.expires_at <= now ? 'expired' as const : null;
    return { id: r.nid, kind: r.kind, from: card(r, 'none'), code: r.room_code, at: r.nat, expiresAt: r.expires_at, read: r.read_at != null, result };
  }),
    ...await wifiNotes(c.env.DB, c.var.user.id, now), ...await bellNotes(c.env.DB, c.var.user.id, now)].sort((a, b) => b.at - a.at);
  return c.json({ notifications: list, unread: list.filter(n => !n.read).length });
});
notes.post('/read', async c => {
  const { ids } = await body(c, MarkRead), now = c.var.deps.now(), db = c.env.DB;
  if (ids) await db.batch(ids.map(id => db.prepare('UPDATE notifications SET read_at = ? WHERE id = ? AND user_id = ? AND read_at IS NULL').bind(now, id, c.var.user.id)));
  else await db.prepare('UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL').bind(now, c.var.user.id).run();
  await readWifi(db, c.var.user.id, ids);
  await readBell(db, c.var.user.id, ids, now);
  return c.json({ ok: true });
});
/** An item answered from the bell (Join, Let in, Accept, Decline, ✕): kept 24 h with its result. */
notes.post('/:id/handled', async c => {
  const { result } = await body(c, Handled);
  await c.env.DB.prepare('UPDATE notifications SET handled_at = ?, result = ?, read_at = COALESCE(read_at, ?) WHERE id = ? AND user_id = ? AND handled_at IS NULL')
    .bind(c.var.deps.now(), result, c.var.deps.now(), c.req.param('id'), c.var.user.id).run();
  return c.json({ ok: true });
});
/** Clear: everything already handled or expired (anything still waiting for an answer stays). */
notes.delete('/', async c => {
  await c.env.DB.prepare("DELETE FROM notifications WHERE user_id = ? AND (handled_at IS NOT NULL OR kind = 'friend_accept' OR (kind IN ('invite', 'join_request', 'let_in') AND expires_at <= ?))").bind(c.var.user.id, c.var.deps.now()).run();
  await dismissWifi(c.env.DB, c.var.user.id, null);
  await dismissBell(c.env.DB, c.var.user.id, null);
  return c.json({ ok: true });
});
notes.delete('/:id', async c => {
  const id = c.req.param('id');
  if (id.startsWith('w:')) { await dismissWifi(c.env.DB, c.var.user.id, id.slice(2)); return c.json({ ok: true }); }
  if (id.startsWith('b:')) { await dismissBell(c.env.DB, c.var.user.id, id.slice(2)); return c.json({ ok: true }); }
  // ✕ on a live item = Dismissed (kept 24 h); on a handled one it goes for good
  const r = await c.env.DB.prepare("UPDATE notifications SET handled_at = ?, result = 'dismissed', read_at = COALESCE(read_at, ?) WHERE id = ? AND user_id = ? AND handled_at IS NULL")
    .bind(c.var.deps.now(), c.var.deps.now(), id, c.var.user.id).run();
  if (r.meta.changes) return c.json({ ok: true });
  await c.env.DB.prepare('DELETE FROM notifications WHERE id = ? AND user_id = ?').bind(c.req.param('id'), c.var.user.id).run();
  return c.json({ ok: true });
});

export const games = new Hono<AppEnv>();
/** My finished online games, newest first. */
games.get('/', async c => {
  const { results } = await c.env.DB.prepare(
    `SELECT g.id, g.winner, g.days, g.valid, g.played_at, p.seat, p.role, p.alive,
            (SELECT COUNT(*) FROM game_players q WHERE q.game_id = g.id) AS players,
            (SELECT group_concat(q.name, char(31)) FROM game_players q WHERE q.game_id = g.id) AS names
     FROM game_players p JOIN games g ON g.id = p.game_id WHERE p.user_id = ? AND g.source = 'online' ORDER BY g.played_at DESC LIMIT 100`)
    .bind(c.var.user.id).all<{ id: string; winner: string; days: number; valid: number; played_at: number; seat: number; role: string; alive: number; players: number; names: string | null }>();
  // [S15-5] names: the old app's "Search by player name" in the history
  return c.json({ games: results.map(r => ({ id: r.id, winner: r.winner, days: r.days, valid: !!r.valid, playedAt: r.played_at, seat: r.seat, role: r.role, alive: !!r.alive, players: r.players,
    names: (r.names ?? '').split(String.fromCharCode(31)).filter(Boolean) })) });
});
games.get('/:id', async c => {
  const db = c.env.DB, id = c.req.param('id');
  const mine = await db.prepare('SELECT 1 FROM game_players WHERE game_id = ? AND user_id = ?').bind(id, c.var.user.id).first();
  const g = mine && await db.prepare('SELECT * FROM games WHERE id = ?').bind(id).first<{ id: string; host_id: string | null; winner: string; days: number; valid: number; rules: string; log: string; stats: string; played_at: number; record: string | null }>();
  if (!g) throw new ApiErr(404, 'not_found');
  const { results } = await db.prepare('SELECT seat, user_id, name, role, alive FROM game_players WHERE game_id = ? ORDER BY seat').bind(id).all<{ seat: number; user_id: string | null; name: string; role: string; alive: number }>();
  return c.json({
    id: g.id, winner: g.winner, days: g.days, valid: !!g.valid, playedAt: g.played_at, host: g.host_id === c.var.user.id,
    rules: JSON.parse(g.rules), log: JSON.parse(g.log), stats: JSON.parse(g.stats),
    sheikh: (g.record ? JSON.parse(g.record).sheikh : null) ?? null,  // 1.0.0: the Godfather's seat
    players: results.map(p => ({ seat: p.seat, userId: p.user_id, name: p.name, role: p.role, alive: !!p.alive })),
  });
});
/** Only the game's host marks it valid / invalid (counts in stats or not). */
games.patch('/:id', async c => {
  const { valid } = await body(c, MarkGame);
  const r = await c.env.DB.prepare('UPDATE games SET valid = ? WHERE id = ? AND host_id = ?').bind(valid ? 1 : 0, c.req.param('id'), c.var.user.id).run();
  if (!r.meta.changes) throw new ApiErr(404, 'not_found');
  await refreshTitles(c.env, c.var.deps);
  return c.json({ ok: true });
});
