// Sign-in (email code, Google), sessions, and the middleware that checks the bearer token.
import { Hono, type MiddlewareHandler } from 'hono';
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';
import { EmailStart, EmailVerify, GoogleAuth, type AuthAnswer, type SessionInfo } from '@mafia/protocol';
import { allow, ApiErr, body, DAY, HOUR, same, sha256, sixDigits, token, userFromToken, type AppEnv, type Ctx, type Env, type UserRow } from './lib.ts';
import { meOf } from './users.ts';

export const CODE_TTL = 10 * 60e3, CODE_TRIES = 5, RESEND_AFTER = 60e3, SESSION_TTL = 180 * DAY;
export const MAIL_PER_HOUR = 5, IP_PER_HOUR = 20;

const codeHash = (email: string, code: string) => sha256(email + ':' + code);

/** Finds the account for a verified sign-in, links a new way of signing in to it, or creates it. */
async function account(c: Ctx, kind: 'email' | 'google', subject: string, email: string, name: string): Promise<UserRow> {
  const db = c.env.DB, now = c.var.deps.now();
  const byId = await db.prepare('SELECT u.* FROM identities i JOIN users u ON u.id = i.user_id WHERE i.kind = ? AND i.subject = ?').bind(kind, subject).first<UserRow>();
  if (byId) return byId;
  // the same verified email signed in another way: same account
  let user = await db.prepare('SELECT u.* FROM identities i JOIN users u ON u.id = i.user_id WHERE i.email = ? LIMIT 1').bind(email).first<UserRow>();
  const steps: D1PreparedStatement[] = [];
  if (!user) {
    const display = (name || email.split('@')[0]).trim().slice(0, 18).trim() || 'Player';
    user = { id: crypto.randomUUID(), handle: null, display, avatar_preset: 0, avatar_ver: 0, fav_role: '', show_online: 1, created_at: now };
    steps.push(db.prepare('INSERT INTO users (id, display, created_at) VALUES (?, ?, ?)').bind(user.id, user.display, now));
  }
  steps.push(db.prepare('INSERT INTO identities (kind, subject, user_id, email, created_at) VALUES (?, ?, ?, ?, ?)').bind(kind, subject, user.id, email, now));
  await db.batch(steps);
  return user;
}

async function signIn(c: Ctx, user: UserRow, device: string): Promise<AuthAnswer> {
  const t = token(), now = c.var.deps.now();
  await c.env.DB.prepare('INSERT INTO sessions (id, token_hash, user_id, device, created_at, last_seen_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .bind(crypto.randomUUID(), await sha256(t), user.id, device, now, now, now + SESSION_TTL).run();
  return { token: t, user: await meOf(c.env.DB, user), needsHandle: !user.handle };
}

/** Bearer token → c.var.user / c.var.sid, or 401. Renews the session at most once a day. */
export const requireUser: MiddlewareHandler<AppEnv> = async (c, next) => {
  const m = /^Bearer (\S+)$/.exec(c.req.header('authorization') || '');
  const s = m && await userFromToken(c.env.DB, m[1], c.var.deps.now());
  if (!s) throw new ApiErr(401, 'auth');
  c.set('user', s.user); c.set('sid', s.sid);
  await next();
};

export const auth = new Hono<AppEnv>();

auth.post('/email/start', async c => {
  const { email } = await body(c, EmailStart), db = c.env.DB, now = c.var.deps.now();
  const ip = c.req.header('cf-connecting-ip') || 'unknown';
  const last = await db.prepare('SELECT sent_at FROM email_codes WHERE email = ?').bind(email).first<{ sent_at: number }>();
  if (last && now - last.sent_at < RESEND_AFTER) throw new ApiErr(429, 'slow_down');
  if (!(await allow(db, 'ip:' + ip, IP_PER_HOUR, HOUR, now)) || !(await allow(db, 'mail:' + email, MAIL_PER_HOUR, HOUR, now))) throw new ApiErr(429, 'slow_down');
  const code = sixDigits();
  await db.batch([
    db.prepare(`INSERT INTO email_codes (email, code_hash, tries, sent_at, expires_at) VALUES (?1, ?2, 0, ?3, ?4)
      ON CONFLICT (email) DO UPDATE SET code_hash = ?2, tries = 0, sent_at = ?3, expires_at = ?4`).bind(email, await codeHash(email, code), now, now + CODE_TTL),
    // ponytail: stale rows are swept here, on each code request; a cron when the table grows
    db.prepare('DELETE FROM rate_limits WHERE window_start < ?').bind(now - DAY),
    db.prepare('DELETE FROM email_codes WHERE expires_at < ?').bind(now - DAY),
  ]);
  await c.var.deps.sendCode(c.env, email, code);
  return c.json({ ok: true });  // the same answer whether or not the email has an account
});

auth.post('/email/verify', async c => {
  const { email, code, device } = await body(c, EmailVerify), db = c.env.DB, now = c.var.deps.now();
  const row = await db.prepare('SELECT code_hash, tries, expires_at FROM email_codes WHERE email = ?').bind(email).first<{ code_hash: string; tries: number; expires_at: number }>();
  if (!row || row.expires_at < now || row.tries >= CODE_TRIES) throw new ApiErr(400, 'code');
  if (!same(row.code_hash, await codeHash(email, code))) {
    await db.prepare('UPDATE email_codes SET tries = tries + 1 WHERE email = ?').bind(email).run();
    throw new ApiErr(400, 'code');
  }
  await db.prepare('DELETE FROM email_codes WHERE email = ?').bind(email).run();
  return c.json(await signIn(c, await account(c, 'email', email, email, ''), device));
});

auth.post('/google', async c => {
  const { idToken, device } = await body(c, GoogleAuth);
  const g = await c.var.deps.verifyGoogle(c.env, idToken);
  if (!g) throw new ApiErr(401, 'google');
  return c.json(await signIn(c, await account(c, 'google', g.sub, g.email, g.name), device));
});

auth.post('/logout', requireUser, async c => {
  await c.env.DB.prepare('DELETE FROM sessions WHERE id = ?').bind(c.var.sid).run();
  return c.json({ ok: true });
});

export const sessions = new Hono<AppEnv>();
sessions.use(requireUser);
sessions.get('/', async c => {
  const { results } = await c.env.DB.prepare('SELECT id, device, created_at, last_seen_at FROM sessions WHERE user_id = ? AND expires_at > ? ORDER BY last_seen_at DESC')
    .bind(c.var.user.id, c.var.deps.now()).all<{ id: string; device: string; created_at: number; last_seen_at: number }>();
  return c.json({ sessions: results.map((s): SessionInfo => ({ id: s.id, device: s.device, createdAt: s.created_at, lastSeenAt: s.last_seen_at, current: s.id === c.var.sid })) });
});
sessions.delete('/:id', async c => {
  await c.env.DB.prepare('DELETE FROM sessions WHERE id = ? AND user_id = ?').bind(c.req.param('id'), c.var.user.id).run();
  return c.json({ ok: true });
});

// ---- real outside services

const GOOGLE_ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];
/** Checks a Google sign-in token: signature (Google's published keys), issuer, audience, expiry, verified email. */
export function googleVerifier(keys: JWTVerifyGetKey) {
  return async (env: Env, idToken: string) => {
    const audience = env.GOOGLE_CLIENT_IDS.split(',').map(s => s.trim()).filter(Boolean);
    if (!audience.length) return null;
    try {
      const { payload: p } = await jwtVerify(idToken, keys, { issuer: GOOGLE_ISSUERS, audience });
      if (p.email_verified !== true || typeof p.email !== 'string' || typeof p.sub !== 'string') return null;
      return { sub: p.sub, email: p.email.toLowerCase(), name: typeof p.name === 'string' ? p.name : '' };
    } catch { return null; }
  };
}
export const googleKeys = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));

/** Local test mode only (MAIL_LOG=1): the last code per email, for the emulator test to read. */
export const lastCodes = new Map<string, string>();

/** Sends the sign-in code through Resend. */
export async function resendCode(env: Env, to: string, code: string) {
  // the CI emulator test runs a local Worker: it reads the code from this log line (never set in wrangler.jsonc)
  if (env.MAIL_LOG === '1') { lastCodes.set(to, code); console.log(`MAIL_LOG code ${to} ${code}`); return; }
  if (!env.RESEND_API_KEY) throw new ApiErr(503, 'mail');
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      from: env.MAIL_FROM, to: [to], subject: `${code} is your Mafia Dealer code`,
      text: `Your Mafia Dealer sign-in code: ${code}\nIt expires in 10 minutes. If you didn't ask for it, ignore this email.\n\n` +
        `رمز الدخول إلى Mafia Dealer: ${code}\nينتهي خلال 10 دقائق. إن لم تطلبه فتجاهل هذه الرسالة.`,
    }),
  });
  if (!r.ok) throw new ApiErr(502, 'mail');
}
