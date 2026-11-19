import { describe, expect, it } from 'vitest';
import { setup } from './helpers.ts';

const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

describe('profile', () => {
  it('handle: chosen once signed in, unique ignoring case, with an optional @', async () => {
    const t = await setup(), a = await t.signInEmail('a@example.com'), b = await t.signInEmail('b@example.com');
    const p = await t.call('PATCH', '/v1/me', { token: a.token, body: { handle: '@Dareer', display: 'Dareer', fav: 'detective' } });
    expect(p.json).toMatchObject({ needsHandle: false, user: { handle: 'Dareer', display: 'Dareer', fav: 'detective' } });
    expect((await t.call('PATCH', '/v1/me', { token: b.token, body: { handle: 'dareer' } })).json).toEqual({ error: 'handle_taken' });
    for (const handle of ['ab', 'with space', 'x'.repeat(21), 'نجم']) expect((await t.call('PATCH', '/v1/me', { token: b.token, body: { handle } })).status).toBe(400);
    expect((await t.call('PATCH', '/v1/me', { token: b.token, body: { display: 'x'.repeat(19) } })).status).toBe(400);
    expect((await t.call('PATCH', '/v1/me', { token: b.token, body: { display: 'حلاوي', showOnline: false } })).json.user).toMatchObject({ display: 'حلاوي', showOnline: false });
    expect((await t.call('PATCH', '/v1/me', { token: b.token, body: { admin: true } })).status).toBe(400);
  });

  it('avatar: a preset or a photo; the photo is public, with a new version per upload', async () => {
    const t = await setup(), a = await t.user('Sami');
    expect((await t.call('PUT', '/v1/me/avatar', { token: a.token, body: { preset: 3 } })).json.user.avatar).toEqual({ preset: 3 });
    const up = await t.call('PUT', '/v1/me/avatar', { token: a.token, body: { image: PNG } });
    expect(up.json.user.avatar).toEqual({ photo: t.clock.t });
    const img = await t.call('GET', '/v1/avatars/' + a.id);
    expect(img.status).toBe(200);
    expect(img.res.headers.get('content-type')).toBe('image/png');
    expect(new Uint8Array(await img.res.arrayBuffer()).slice(1, 4)).toEqual(new TextEncoder().encode('PNG'));
    expect((await t.call('PUT', '/v1/me/avatar', { token: a.token, body: { preset: 12 } })).status).toBe(400);
    expect((await t.call('PUT', '/v1/me/avatar', { token: a.token, body: { image: 'data:image/gif;base64,R0lG' } })).status).toBe(400);
    await t.call('PUT', '/v1/me/avatar', { token: a.token, body: { preset: 1 } });
    expect((await t.call('GET', '/v1/avatars/' + a.id)).status).toBe(404);
  });

  it('deleting the account removes everything; the email can sign up again as new', async () => {
    const t = await setup(), a = await t.user('Hokan'), b = await t.user('Fater');
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Fater' } });
    await t.call('PUT', '/v1/me/avatar', { token: a.token, body: { image: PNG } });
    expect((await t.call('DELETE', '/v1/me', { token: a.token, body: {} })).status).toBe(400);
    expect((await t.call('DELETE', '/v1/me', { token: a.token, body: { confirm: 'delete' } })).json).toEqual({ ok: true });
    expect((await t.call('GET', '/v1/me', { token: a.token })).status).toBe(401);
    expect((await t.call('GET', '/v1/friends', { token: b.token })).json).toEqual({ friends: [], incoming: [], outgoing: [] });
    expect((await t.call('GET', '/v1/avatars/' + a.id)).status).toBe(404);
    for (const table of ['users', 'identities', 'sessions', 'avatars', 'friendships']) {
      const r = await t.env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE ${table === 'users' ? 'id' : table === 'friendships' ? 'a = ?1 OR b' : 'user_id'} = ?1`).bind(a.id).first<{ n: number }>();
      expect([table, r!.n]).toEqual([table, 0]);
    }
    const again = await t.signInEmail('hokan@example.com');
    expect(again.user.id).not.toBe(a.id);
    expect(again.needsHandle).toBe(true);
  });
});

describe('friends', () => {
  it('request → accept → friends; never shows emails', async () => {
    const t = await setup(), a = await t.user('Dareer'), b = await t.user('Halawy');
    const r = await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: '@halawy' } });
    expect(r.json).toMatchObject({ rel: 'requested', user: { id: b.id, handle: 'Halawy' } });
    expect(JSON.stringify(r.json)).not.toContain('@example.com');
    expect((await t.call('GET', '/v1/friends', { token: b.token })).json.incoming.map((u: any) => u.id)).toEqual([a.id]);
    expect((await t.call('GET', '/v1/users/Dareer', { token: b.token })).json.user.rel).toBe('incoming');
    expect((await t.call('POST', `/v1/friend-requests/${a.id}/accept`, { token: a.token })).json).toEqual({ error: 'no_request' });  // can't accept my own
    expect((await t.call('POST', `/v1/friend-requests/${a.id}/accept`, { token: b.token })).json).toEqual({ rel: 'friends' });
    const fa = (await t.call('GET', '/v1/friends', { token: a.token })).json;
    expect(fa.friends.map((u: any) => [u.handle, u.rel])).toEqual([['Halawy', 'friends']]);
    expect((await t.call('DELETE', '/v1/friends/' + b.id, { token: a.token })).json).toEqual({ rel: 'none' });
    expect((await t.call('GET', '/v1/friends', { token: b.token })).json.friends).toEqual([]);
  });

  it('asking someone who already asked me is a yes; asking at the same moment too', async () => {
    const t = await setup(), a = await t.user('Farouq'), b = await t.user('Sami');
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Sami' } });
    expect((await t.call('POST', '/v1/friend-requests', { token: b.token, body: { handle: 'Farouq' } })).json.rel).toBe('friends');
    const c = await t.user('Hokan'), d = await t.user('Fater');
    const [x, y] = await Promise.all([
      t.call('POST', '/v1/friend-requests', { token: c.token, body: { handle: 'Fater' } }),
      t.call('POST', '/v1/friend-requests', { token: d.token, body: { handle: 'Hokan' } }),
    ]);
    expect([x.status, y.status]).toEqual([200, 200]);
    expect((await t.call('GET', '/v1/users/Fater', { token: c.token })).json.user.rel).toBe('friends');
    expect((await t.env.DB.prepare('SELECT COUNT(*) AS n FROM friendships').first<{ n: number }>())!.n).toBe(2);
  });

  it('decline, take back, no self, unknown handle, a handle needed first', async () => {
    const t = await setup(), a = await t.user('Khaddour'), b = await t.user('Dareer');
    expect((await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'khaddour' } })).json).toEqual({ error: 'self' });
    expect((await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'nobody_here' } })).json).toEqual({ error: 'not_found' });
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Dareer' } });
    await t.call('DELETE', '/v1/friend-requests/' + a.id, { token: b.token });  // declined
    expect((await t.call('GET', '/v1/friends', { token: a.token })).json.outgoing).toEqual([]);
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Dareer' } });
    await t.call('DELETE', '/v1/friend-requests/' + b.id, { token: a.token });  // taken back
    expect((await t.call('GET', '/v1/friends', { token: b.token })).json.incoming).toEqual([]);
    const n = await t.signInEmail('new@example.com');
    expect((await t.call('POST', '/v1/friend-requests', { token: n.token, body: { handle: 'Dareer' } })).json).toEqual({ error: 'needs_handle' });
    expect((await t.call('GET', '/v1/users/nobody_here', { token: a.token })).status).toBe(404);
  });
});

it('unknown paths and the health check', async () => {
  const t = await setup();
  expect((await t.call('GET', '/v1/health')).json).toEqual({ ok: true });
  expect((await t.call('GET', '/v1/nope')).json).toEqual({ error: 'not_found' });
});
