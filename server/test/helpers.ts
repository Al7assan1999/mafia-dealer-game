import { env } from 'cloudflare:test';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import { googleVerifier } from '../src/auth.ts';
import { createApp } from '../src/index.ts';
import type { Env } from '../src/lib.ts';

export const AUD = 'test-client.apps.googleusercontent.com';

/** A test app: a clock you can move, a mailbox, and a fake Google that signs with a local key. */
export async function setup() {
  // a clean database for every test (the plugin keeps D1 between tests of a file)
  const db = (env as unknown as Env).DB;
  await db.batch(['games', 'rooms', 'users', 'email_codes', 'rate_limits'].map(t => db.prepare(`DELETE FROM ${t}`)));
  const clock = { t: 1_800_000_000_000 };
  const mail: { to: string; code: string }[] = [];
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const jwk = { ...(await exportJWK(publicKey)), kid: 'k1', alg: 'RS256' };
  const app = createApp({
    now: () => clock.t,
    sendCode: async (_e, to, code) => { mail.push({ to, code }); },
    verifyGoogle: googleVerifier(createLocalJWKSet({ keys: [jwk] })),
  });
  const testEnv: Env = { ...(env as unknown as Env), GOOGLE_CLIENT_IDS: AUD };
  const call = async (method: string, path: string, opts: { body?: unknown; token?: string; ip?: string } = {}) => {
    const headers: Record<string, string> = { 'cf-connecting-ip': opts.ip ?? '1.2.3.4' };
    if (opts.body !== undefined) headers['content-type'] = 'application/json';
    if (opts.token) headers.authorization = 'Bearer ' + opts.token;
    const r = await app.request(path, { method, headers, body: opts.body === undefined ? undefined : JSON.stringify(opts.body) }, testEnv);
    const type = r.headers.get('content-type') || '';
    return { status: r.status, json: type.includes('json') ? await r.json() as any : null, res: r };
  };
  /** A Google sign-in token, signed by the fake Google. */
  const googleToken = (claims: Record<string, unknown>, o: { aud?: string; iss?: string; exp?: number } = {}) =>
    new SignJWT({ email_verified: true, ...claims }).setProtectedHeader({ alg: 'RS256', kid: 'k1' })
      .setIssuer(o.iss ?? 'https://accounts.google.com').setAudience(o.aud ?? AUD)
      .setIssuedAt().setExpirationTime(o.exp ?? Math.floor(Date.now() / 1000) + 600).sign(privateKey);
  /** Signs in by email code; returns the auth answer. */
  const signInEmail = async (email: string, device = 'Pixel 8') => {
    const s = await call('POST', '/v1/auth/email/start', { body: { email } });
    if (s.status !== 200) throw new Error('start ' + s.status + ' ' + JSON.stringify(s.json));
    const code = mail.filter(m => m.to === email.toLowerCase()).at(-1)!.code;
    const v = await call('POST', '/v1/auth/email/verify', { body: { email, code, device } });
    if (v.status !== 200) throw new Error('verify ' + v.status);
    clock.t += 61_000;  // past the resend wait for the next sign-in
    return v.json;
  };
  /** A signed-in user with a handle. */
  const user = async (handle: string) => {
    const a = await signInEmail(handle.toLowerCase() + '@example.com');
    const p = await call('PATCH', '/v1/me', { token: a.token, body: { handle } });
    if (p.status !== 200) throw new Error('handle ' + p.status);
    return { token: a.token as string, id: a.user.id as string };
  };
  return { app, clock, mail, call, googleToken, signInEmail, user, env: testEnv };
}
