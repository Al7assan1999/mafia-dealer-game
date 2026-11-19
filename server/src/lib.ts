// Small shared pieces: the app's types, errors, hashing, ids, rate limits.
import type { Context } from 'hono';
import type { ApiError } from '@mafia/protocol';
import type { z } from 'zod';

export interface Env {
  DB: D1Database;
  GOOGLE_CLIENT_IDS: string;   // comma-separated Google OAuth client ids (the sign-in token's audience)
  MAIL_FROM: string;
  RESEND_API_KEY?: string;     // secret
}
export interface GoogleId { sub: string; email: string; name: string }
/** What the outside world gives the app; tests pass fakes. */
export interface Deps {
  now(): number;
  sendCode(env: Env, to: string, code: string): Promise<void>;
  verifyGoogle(env: Env, idToken: string): Promise<GoogleId | null>;
}
export interface UserRow {
  id: string; handle: string | null; display: string; avatar_preset: number; avatar_ver: number;
  fav_role: string; show_online: number; created_at: number;
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
