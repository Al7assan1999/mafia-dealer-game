// Small shared pieces: the app's types, errors, hashing, ids, rate limits.
import type { Context } from 'hono';
import type { ApiError, Avatar, Rel, UserCard } from '@mafia/protocol';
import type { z } from 'zod';

export interface Env {
  DB: D1Database;
  ROOM: DurableObjectNamespace;   // one per online room code
  HUB: DurableObjectNamespace;    // one per account: presence + live notifications
  GOOGLE_CLIENT_IDS: string;   // comma-separated Google OAuth client ids (the sign-in token's audience)
  MAIL_FROM: string;
  RESEND_API_KEY?: string;     // secret
  ADMIN_IDS?: string;          // secret: comma-separated account ids that moderate reports
  FCM_SERVICE_ACCOUNT?: string; // secret: the Google service account JSON that sends pushes (none: no pushes)
  OLD_RELAY?: Fetcher;         // service binding to the old app's relay (read only: its Group history, S8-3 / R4)
  MAIL_LOG?: string;           // local tests only (`wrangler dev --var MAIL_LOG:1`): print codes instead of sending
}
export interface GoogleId { sub: string; email: string; name: string }
/** What the outside world gives the app; tests pass fakes. */
export interface Deps {
  now(): number;
  sendCode(env: Env, to: string, code: string): Promise<void>;
  verifyGoogle(env: Env, idToken: string): Promise<GoogleId | null>;
  push: import('./push.ts').PushSender;
  readOldGroup: import('./legacy.ts').OldGroupReader;
}
export interface UserRow {
  id: string; handle: string | null; display: string; avatar_preset: number; avatar_ver: number;
  fav_role: string; show_online: number; created_at: number;
  online?: number; room_code?: string | null; room_status?: '' | 'lobby' | 'game'; room_size?: number; banned_at?: number | null; on_board?: number;
}

export const avatarOf = (u: UserRow): Avatar => (u.avatar_ver > 0 ? { photo: u.avatar_ver } : { preset: u.avatar_preset });
/** Another account as others see it: never the email. Friends also see presence (unless hidden). */
export function card(u: UserRow, rel: Rel): UserCard {
  const c: UserCard = { id: u.id, handle: u.handle, display: u.display, avatar: avatarOf(u), fav: u.fav_role, rel };
  if (rel === 'friends') Object.assign(c, presenceOf(u));
  return c;
}
export function presenceOf(u: UserRow) {
  const on = !!u.online && !!u.show_online, st: '' | 'lobby' | 'game' = on ? u.room_status || '' : '';
  return { on, st, op: st === 'lobby', n: st ? u.room_size ?? 0 : 0 };  // n: players in that room (P3)
}

/** The account behind a session token, or null (expired or unknown). Renews the session at most once a day. */
export async function userFromToken(db: D1Database, tok: string, now: number): Promise<{ user: UserRow; sid: string } | null> {
  if (!/^[A-Za-z0-9_-]{43}$/.test(tok)) return null;
  const s = await db.prepare('SELECT id, user_id, last_seen_at FROM sessions WHERE token_hash = ? AND expires_at > ?').bind(await sha256(tok), now)
    .first<{ id: string; user_id: string; last_seen_at: number }>();
  const user = s && await db.prepare('SELECT * FROM users WHERE id = ?').bind(s.user_id).first<UserRow>();
  if (!s || !user || user.banned_at) return null;  // a banned account is signed out everywhere
  if (now - s.last_seen_at > DAY) await db.prepare('UPDATE sessions SET last_seen_at = ?, expires_at = ? WHERE id = ?').bind(now, now + 180 * DAY, s.id).run();
  return { user, sid: s.id };
}
export type AppEnv = { Bindings: Env; Variables: { deps: Deps; user: UserRow; sid: string } };
export type Ctx = Context<AppEnv>;

export const HOUR = 3600e3, DAY = 24 * HOUR;

/** An answer with an error code: { error } and an HTTP status. */
export class ApiErr extends Error {
  readonly status: 400 | 401 | 403 | 404 | 409 | 413 | 429 | 502 | 503;
  readonly code: ApiError | 'mail';
  constructor(status: ApiErr['status'], code: ApiErr['code']) { super(code); this.status = status; this.code = code; }
}

/** The request's JSON body, checked against a schema (400 bad_request otherwise). */
export async function body<S extends z.ZodType>(c: Ctx, schema: S): Promise<z.output<S>> {
  let raw: unknown;
  try { raw = await c.req.json(); } catch { throw new ApiErr(400, 'bad_request'); }
  const r = schema.safeParse(raw);
  if (!r.success) throw new ApiErr(400, 'bad_request');
  return r.data;
}

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('');
export const sha256 = async (s: string) => hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));
/** Random URL-safe token (32 bytes). */
export function token() {
  const b = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
/** Random 6-digit code. */
export const sixDigits = () => String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, '0');
/** Constant-time string compare (equal length hex hashes). */
export function same(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

/** Fixed-window counter: true while `key` has been hit at most `limit` times in the current window. */
export async function allow(db: D1Database, key: string, limit: number, windowMs: number, now: number) {
  const r = await db.prepare(
    `INSERT INTO rate_limits (key, window_start, count) VALUES (?1, ?2, 1)
     ON CONFLICT (key) DO UPDATE SET
       count = CASE WHEN window_start <= ?2 - ?3 THEN 1 ELSE count + 1 END,
       window_start = CASE WHEN window_start <= ?2 - ?3 THEN ?2 ELSE window_start END
     RETURNING count`).bind(key, now, windowMs).first<{ count: number }>();
  return (r?.count ?? 1) <= limit;
}

/** base64 → bytes with a plain loop (Uint8Array.from(atob(..), fn) costs ~35 ms of CPU for 300 KB; this ~1 ms). null if not base64. */
export function fromB64(b64: string): Uint8Array | null {
  let s: string;
  try { s = atob(b64); } catch { return null; }
  const u = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) u[i] = s.charCodeAt(i);
  return u;
}

/** 1.3.0: the roles a 1.2 app knows. History, game pages and Wi-Fi notes send it this role (the Hunter, the Mayor and
 *  the Watcher are townsfolk: Citizen) and the real one in `role2`, which 1.3.0 reads; a 1.2 phone would break on a
 *  role name it doesn't know. */
const OLD_ROLES = ['mafia', 'doctor', 'detective', 'citizen', 'sniper', 'jester', 'bodyguard'];
export const roleFor12 = (r: string) => (OLD_ROLES.includes(r) ? r : 'citizen');
/** 1.4.0: the result a phone before 1.4.0 knows (a 1.2 app breaks on another); the real one goes in `winner2`. */
export const winnerFor13 = (w: string | null) => (w == null || w === 'mafia' || w === 'citizens' || w === 'jester' ? w : 'citizens') as 'mafia' | 'citizens' | 'jester' | null;
