// The signed-in user's own account, other accounts' public cards, avatars and friends.
import { Hono } from 'hono';
import { FriendRequest, Handle, MAX_AVATAR_BYTES, PatchMe, PutAvatar, SavedNames, SavedSetup, type FriendsAnswer, type Me, type Rel } from '@mafia/protocol';
import { deckOk, nameKey } from '@mafia/engine';
import { notify, pushPresence } from './hub.ts';
import { ApiErr, avatarOf, body, card, type AppEnv, type Ctx, type UserRow } from './lib.ts';

export const MAX_FRIENDS = 300;

export async function meOf(db: D1Database, u: UserRow): Promise<Me> {
  const { results } = await db.prepare('SELECT kind, email FROM identities WHERE user_id = ?').bind(u.id).all<{ kind: string; email: string }>();
  return {
    id: u.id, handle: u.handle, display: u.display, avatar: avatarOf(u), fav: u.fav_role, showOnline: !!u.show_online,
    emails: [...new Set(results.map(r => r.email))].sort(), google: results.some(r => r.kind === 'google'),
    room: u.room_code && u.room_status ? { code: u.room_code, status: u.room_status } : null,
  };
}

/** The friendship row for two users (stored once, a < b). */
const pair = (x: string, y: string) => (x < y ? [x, y] : [y, x]) as [string, string];
interface FriendRow { a: string; b: string; requested_by: string; status: 'pending' | 'accepted' }
const relOf = (me: string, f: FriendRow | null): Rel => !f ? 'none' : f.status === 'accepted' ? 'friends' : f.requested_by === me ? 'requested' : 'incoming';
const friendRow = (c: Ctx, other: string) => c.env.DB.prepare('SELECT a, b, requested_by, status FROM friendships WHERE a = ? AND b = ?').bind(...pair(c.var.user.id, other)).first<FriendRow>();
const needHandle = (c: Ctx) => { if (!c.var.user.handle) throw new ApiErr(403, 'needs_handle'); };

export const me = new Hono<AppEnv>();

me.get('/', async c => c.json({ user: await meOf(c.env.DB, c.var.user), needsHandle: !c.var.user.handle }));

me.patch('/', async c => {
  const p = await body(c, PatchMe), u = c.var.user;
  try {
    await c.env.DB.prepare('UPDATE users SET handle = ?, display = ?, fav_role = ?, show_online = ? WHERE id = ?')
      .bind(p.handle ?? u.handle, p.display ?? u.display, p.fav ?? u.fav_role, p.showOnline == null ? u.show_online : +p.showOnline, u.id).run();
  } catch (e) {
    if (/UNIQUE/i.test(String(e))) throw new ApiErr(409, 'handle_taken');
    throw e;
  }
  const fresh = (await c.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(u.id).first<UserRow>())!;
  if (fresh.show_online !== u.show_online) await pushPresence(c.env, u.id);  // "show me as online" switched
  return c.json({ user: await meOf(c.env.DB, fresh), needsHandle: !fresh.handle });
});

me.put('/avatar', async c => {
  const a = await body(c, PutAvatar), db = c.env.DB, id = c.var.user.id;
  if ('preset' in a) {
    await db.batch([db.prepare('UPDATE users SET avatar_preset = ?, avatar_ver = 0 WHERE id = ?').bind(a.preset, id), db.prepare('DELETE FROM avatars WHERE user_id = ?').bind(id)]);
  } else {
    const [, mime, b64] = /^data:(image\/\w+);base64,(.+)$/.exec(a.image)!;
    const bytes = Uint8Array.from(atob(b64), ch => ch.charCodeAt(0));
    if (bytes.length > MAX_AVATAR_BYTES) throw new ApiErr(413, 'too_big');
    const ver = c.var.deps.now();  // a new version per upload, so cached old photos never show
    await db.batch([
      db.prepare('INSERT INTO avatars (user_id, mime, data, ver) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (user_id) DO UPDATE SET mime = ?2, data = ?3, ver = ?4').bind(id, mime, bytes, ver),
      db.prepare('UPDATE users SET avatar_ver = ? WHERE id = ?').bind(ver, id),
    ]);
  }
  const fresh = (await db.prepare('SELECT * FROM users WHERE id = ?').bind(id).first<UserRow>())!;
  return c.json({ user: await meOf(db, fresh) });
});

/** The saved player names (the setup's chips), newest first. */
me.get('/roster', async c => {
  const r = await c.env.DB.prepare('SELECT names FROM saved WHERE user_id = ?').bind(c.var.user.id).first<{ names: string }>();
  return c.json({ names: r ? JSON.parse(r.names) : [] });
});
me.put('/roster', async c => {
  const { names } = await body(c, SavedNames);
  if (new Set(names.map(nameKey)).size < names.length) throw new ApiErr(400, 'dup_names');
  await c.env.DB.prepare(`INSERT INTO saved (user_id, names, updated_at) VALUES (?1, ?2, ?3)
    ON CONFLICT (user_id) DO UPDATE SET names = ?2, updated_at = ?3`).bind(c.var.user.id, JSON.stringify(names), c.var.deps.now()).run();
  return c.json({ names });
});

/** The last setup (role counts and rules), or null. */
me.get('/setup', async c => {
  const r = await c.env.DB.prepare('SELECT setup FROM saved WHERE user_id = ?').bind(c.var.user.id).first<{ setup: string | null }>();
  return c.json({ setup: r?.setup ? JSON.parse(r.setup) : null });
});
me.put('/setup', async c => {
  const setup = await body(c, SavedSetup);
  // the engine's limits: Detective only with 2+ Mafia, and a deck at least 4 players could deal
  if (setup.counts.detective && setup.counts.mafia < 2) throw new ApiErr(400, 'bad_request');
  if (!deckOk(20, setup.counts.mafia, setup.counts.detective)) throw new ApiErr(400, 'bad_request');  // dealable with the most players
  await c.env.DB.prepare(`INSERT INTO saved (user_id, setup, updated_at) VALUES (?1, ?2, ?3)
    ON CONFLICT (user_id) DO UPDATE SET setup = ?2, updated_at = ?3`).bind(c.var.user.id, JSON.stringify(setup), c.var.deps.now()).run();
  return c.json({ setup });
});

/** Deletes the account and everything that belongs to it (sessions, sign-ins, avatar, friendships). */
me.delete('/', async c => {
  const b = await c.req.json().catch(() => null) as { confirm?: unknown } | null;
  if (b?.confirm !== 'delete') throw new ApiErr(400, 'bad_request');
  const db = c.env.DB, id = c.var.user.id;
  await db.batch([
    db.prepare('DELETE FROM email_codes WHERE email IN (SELECT email FROM identities WHERE user_id = ?)').bind(id),
    db.prepare('DELETE FROM users WHERE id = ?').bind(id),
  ]);
  return c.json({ ok: true });
});

export const users = new Hono<AppEnv>();
users.get('/:handle', async c => {
  const h = Handle.safeParse(c.req.param('handle'));
  if (!h.success) throw new ApiErr(404, 'not_found');
  const u = await c.env.DB.prepare('SELECT * FROM users WHERE handle = ?').bind(h.data).first<UserRow>();
  if (!u) throw new ApiErr(404, 'not_found');
  return c.json({ user: card(u, u.id === c.var.user.id ? 'me' : relOf(c.var.user.id, await friendRow(c, u.id))) });
});

/** Public avatar photo (no sign-in: shown in rooms and friend lists). */
export const avatars = new Hono<AppEnv>();
avatars.get('/:id', async c => {
  const r = await c.env.DB.prepare('SELECT mime, data FROM avatars WHERE user_id = ?').bind(c.req.param('id')).first<{ mime: string; data: ArrayBuffer | number[] }>();
  if (!r) throw new ApiErr(404, 'not_found');
  return c.body(new Uint8Array(r.data as ArrayBuffer), 200, { 'content-type': r.mime, 'cache-control': 'public, max-age=86400' });
});

export const friends = new Hono<AppEnv>();
friends.get('/', async c => {
  const id = c.var.user.id;
  const { results } = await c.env.DB.prepare(
    `SELECT f.requested_by, f.status, u.* FROM friendships f JOIN users u ON u.id = CASE WHEN f.a = ?1 THEN f.b ELSE f.a END
     WHERE f.a = ?1 OR f.b = ?1 ORDER BY u.display COLLATE NOCASE`).bind(id).all<UserRow & { requested_by: string; status: 'pending' | 'accepted' }>();
  const out: FriendsAnswer = { friends: [], incoming: [], outgoing: [] };
  for (const r of results) {
    const rel = relOf(id, { a: '', b: '', requested_by: r.requested_by, status: r.status });
    (rel === 'friends' ? out.friends : rel === 'incoming' ? out.incoming : out.outgoing).push(card(r, rel));
  }
  return c.json(out);
});
friends.delete('/:userId', async c => {
  await c.env.DB.prepare("DELETE FROM friendships WHERE a = ? AND b = ? AND status = 'accepted'").bind(...pair(c.var.user.id, c.req.param('userId'))).run();
  return c.json({ rel: 'none' });
});

export const requests = new Hono<AppEnv>();
/** Ask someone (by @handle). If they already asked me, that's a yes. */
requests.post('/', async c => {
  needHandle(c);
  const { handle } = await body(c, FriendRequest), db = c.env.DB, me = c.var.user, now = c.var.deps.now();
  const u = await db.prepare('SELECT * FROM users WHERE handle = ?').bind(handle).first<UserRow>();
  if (!u) throw new ApiErr(404, 'not_found');
  if (u.id === me.id) throw new ApiErr(400, 'self');
  let f = await friendRow(c, u.id);
  if (!f) {
    const n = await db.prepare('SELECT COUNT(*) AS n FROM friendships WHERE a = ?1 OR b = ?1').bind(me.id).first<{ n: number }>();
    if ((n?.n ?? 0) >= MAX_FRIENDS) throw new ApiErr(409, 'full');
    const [a, b] = pair(me.id, u.id);
    // both asking at the same moment: one insert wins, the other one turns into an accept below
    const ins = await db.prepare("INSERT INTO friendships (a, b, requested_by, status, created_at) VALUES (?, ?, ?, 'pending', ?) ON CONFLICT DO NOTHING").bind(a, b, me.id, now).run();
    if (ins.meta.changes) await notify(c.env, u.id, me, 'friend_request', null, now);
    f = await friendRow(c, u.id);
  }
  if (f && f.status === 'pending' && f.requested_by !== me.id) {
    const up = await db.prepare("UPDATE friendships SET status = 'accepted', accepted_at = ? WHERE a = ? AND b = ? AND status = 'pending'").bind(now, f.a, f.b).run();
    if (up.meta.changes) await notify(c.env, u.id, me, 'friend_accept', null, now);
    f = { ...f, status: 'accepted' };
  }
  const rel = relOf(me.id, f);
  return c.json({ rel, user: card(u, rel) });
});
requests.post('/:userId/accept', async c => {
  const [a, b] = pair(c.var.user.id, c.req.param('userId'));
  const r = await c.env.DB.prepare("UPDATE friendships SET status = 'accepted', accepted_at = ? WHERE a = ? AND b = ? AND status = 'pending' AND requested_by = ?")
    .bind(c.var.deps.now(), a, b, c.req.param('userId')).run();
  if (!r.meta.changes) throw new ApiErr(404, 'no_request');
  await notify(c.env, c.req.param('userId'), c.var.user, 'friend_accept', null, c.var.deps.now());
  return c.json({ rel: 'friends' });
});
/** Decline their request, or take mine back. */
requests.delete('/:userId', async c => {
  await c.env.DB.prepare("DELETE FROM friendships WHERE a = ? AND b = ? AND status = 'pending'").bind(...pair(c.var.user.id, c.req.param('userId'))).run();
  return c.json({ rel: 'none' });
});
