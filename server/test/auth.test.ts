import { describe, expect, it } from 'vitest';
import { setup } from './helpers.ts';

describe('email code sign-in', () => {
  it('signs up, then signs in again into the same account; the code works once', async () => {
    const t = await setup();
    expect((await t.call('POST', '/v1/auth/email/start', { body: { email: ' Sami@Example.com ' } })).json).toEqual({ ok: true });
    expect(t.mail).toEqual([{ to: 'sami@example.com', code: expect.stringMatching(/^\d{6}$/) }]);
    const code = t.mail[0].code;
    const v = await t.call('POST', '/v1/auth/email/verify', { body: { email: 'sami@example.com', code, device: 'Pixel 8' } });
    expect(v.status).toBe(200);
    expect(v.json).toMatchObject({ needsHandle: true, user: { handle: null, display: 'sami', emails: ['sami@example.com'], google: false } });
    expect(v.json.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect((await t.call('POST', '/v1/auth/email/verify', { body: { email: 'sami@example.com', code, device: 'x' } })).status).toBe(400);
    t.clock.t += 61_000;
    const again = await t.signInEmail('sami@example.com');
    expect(again.user.id).toBe(v.json.user.id);
  });

  it('a wrong code counts; after 5 tries even the right one is refused', async () => {
    const t = await setup();
    await t.call('POST', '/v1/auth/email/start', { body: { email: 'a@example.com' } });
    const code = t.mail[0].code, wrong = code === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) expect((await t.call('POST', '/v1/auth/email/verify', { body: { email: 'a@example.com', code: wrong, device: 'x' } })).json).toEqual({ error: 'code' });
    expect((await t.call('POST', '/v1/auth/email/verify', { body: { email: 'a@example.com', code, device: 'x' } })).status).toBe(400);
  });

  it('codes expire after 10 minutes', async () => {
    const t = await setup();
    await t.call('POST', '/v1/auth/email/start', { body: { email: 'a@example.com' } });
    t.clock.t += 10 * 60e3 + 1;
    expect((await t.call('POST', '/v1/auth/email/verify', { body: { email: 'a@example.com', code: t.mail[0].code, device: 'x' } })).status).toBe(400);
  });

  it('limits: one code a minute, 5 an hour per email, 20 an hour per address', async () => {
    const t = await setup(), start = (email: string, ip = '1.2.3.4') => t.call('POST', '/v1/auth/email/start', { body: { email }, ip });
    expect((await start('a@example.com')).status).toBe(200);
    expect((await start('a@example.com')).json).toEqual({ error: 'slow_down' });
    for (let i = 0; i < 4; i++) { t.clock.t += 61_000; expect((await start('a@example.com')).status).toBe(200); }
    t.clock.t += 61_000;
    expect((await start('a@example.com')).status).toBe(429);   // 6th in the hour
    t.clock.t += 3600e3;
    expect((await start('a@example.com')).status).toBe(200);   // a new hour
    const u = await setup();
    for (let i = 0; i < 20; i++) expect((await u.call('POST', '/v1/auth/email/start', { body: { email: `p${i}@example.com` }, ip: '9.9.9.9' })).status).toBe(200);
    expect((await u.call('POST', '/v1/auth/email/start', { body: { email: 'p99@example.com' }, ip: '9.9.9.9' })).status).toBe(429);
    expect((await u.call('POST', '/v1/auth/email/start', { body: { email: 'p99@example.com' }, ip: '8.8.8.8' })).status).toBe(200);
  });

  it('refuses bad input', async () => {
    const t = await setup();
    expect((await t.call('POST', '/v1/auth/email/start', { body: { email: 'not-an-email' } })).json).toEqual({ error: 'bad_request' });
    expect((await t.call('POST', '/v1/auth/email/verify', { body: { email: 'a@example.com', code: '12345', device: 'x' } })).status).toBe(400);
    expect((await t.call('POST', '/v1/auth/email/start', { body: undefined })).status).toBe(400);
  });
});

describe('Google sign-in', () => {
  it('signs in; the same verified email by code reaches the same account', async () => {
    const t = await setup();
    const g = await t.call('POST', '/v1/auth/google', { body: { idToken: await t.googleToken({ sub: 'g-1', email: 'Dareer@Gmail.com', name: 'Dareer K' }), device: 'Galaxy' } });
    expect(g.status).toBe(200);
    expect(g.json.user).toMatchObject({ display: 'Dareer K', emails: ['dareer@gmail.com'], google: true });
    const e = await t.signInEmail('dareer@gmail.com');
    expect(e.user.id).toBe(g.json.user.id);
    expect(e.user.google).toBe(true);
    const g2 = await t.call('POST', '/v1/auth/google', { body: { idToken: await t.googleToken({ sub: 'g-1', email: 'dareer@gmail.com' }), device: 'Galaxy' } });
    expect(g2.json.user.id).toBe(g.json.user.id);
  });

  it('refuses a wrong audience, issuer, an expired token, an unverified email, or a bad signature', async () => {
    const t = await setup(), go = async (tok: string) => (await t.call('POST', '/v1/auth/google', { body: { idToken: tok, device: 'x' } })).json;
    expect(await go(await t.googleToken({ sub: 's', email: 'a@x.com' }, { aud: 'other' }))).toEqual({ error: 'google' });
    expect(await go(await t.googleToken({ sub: 's', email: 'a@x.com' }, { iss: 'https://evil.example' }))).toEqual({ error: 'google' });
    expect(await go(await t.googleToken({ sub: 's', email: 'a@x.com' }, { exp: Math.floor(Date.now() / 1000) - 10 }))).toEqual({ error: 'google' });
    expect(await go(await t.googleToken({ sub: 's', email: 'a@x.com', email_verified: false }))).toEqual({ error: 'google' });
    const other = await setup();
    expect(await go(await other.googleToken({ sub: 's', email: 'a@x.com' }))).toEqual({ error: 'google' });
  });
});

describe('sessions', () => {
  it('needs a valid bearer token; logout ends it', async () => {
    const t = await setup(), a = await t.signInEmail('a@example.com');
    expect((await t.call('GET', '/v1/me')).status).toBe(401);
    expect((await t.call('GET', '/v1/me', { token: 'x'.repeat(43) })).status).toBe(401);
    expect((await t.call('GET', '/v1/me', { token: a.token })).json.user.id).toBe(a.user.id);
    expect((await t.call('POST', '/v1/auth/logout', { token: a.token })).status).toBe(200);
    expect((await t.call('GET', '/v1/me', { token: a.token })).status).toBe(401);
  });

  it('lists devices and signs out another one', async () => {
    const t = await setup(), a = await t.signInEmail('a@example.com', 'Pixel'), b = await t.signInEmail('a@example.com', 'Tablet');
    const list = (await t.call('GET', '/v1/sessions', { token: a.token })).json.sessions;
    expect(list.map((s: any) => [s.device, s.current]).sort()).toEqual([['Pixel', true], ['Tablet', false]]);
    const tablet = list.find((s: any) => s.device === 'Tablet');
    await t.call('DELETE', '/v1/sessions/' + tablet.id, { token: a.token });
    expect((await t.call('GET', '/v1/me', { token: b.token })).status).toBe(401);
    expect((await t.call('GET', '/v1/me', { token: a.token })).status).toBe(200);
  });

  it('expires after 180 days unused, and renews with use', async () => {
    const t = await setup(), a = await t.signInEmail('a@example.com');
    t.clock.t += 170 * 86400e3;
    expect((await t.call('GET', '/v1/me', { token: a.token })).status).toBe(200);  // renewed here
    t.clock.t += 170 * 86400e3;
    expect((await t.call('GET', '/v1/me', { token: a.token })).status).toBe(200);
    t.clock.t += 181 * 86400e3;
    expect((await t.call('GET', '/v1/me', { token: a.token })).status).toBe(401);
  });
});
