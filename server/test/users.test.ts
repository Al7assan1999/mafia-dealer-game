import { describe, expect, it } from 'vitest';
import { setup } from './helpers.ts';
import { DB } from './live.ts';

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

describe('saved names and setup (Sprint 3)', () => {
  const rules = { skip: true, norep: false, saverev: false, decoy: true, self: true, rep: false, reveal: true, timer: 180, nightT: 0, ghost: false, skipVote: true };

  it('names: newest first, at most 30, 1-18 characters, no two the same; each account sees only its own', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Hokan');
    expect((await t.call('GET', '/v1/me/roster', { token: a.token })).json).toEqual({ names: [] });
    expect((await t.call('PUT', '/v1/me/roster', { token: a.token, body: { names: [' Dareer ', 'حلاوي'] } })).json).toEqual({ names: ['Dareer', 'حلاوي'] });
    expect((await t.call('GET', '/v1/me/roster', { token: a.token })).json).toEqual({ names: ['Dareer', 'حلاوي'] });
    expect((await t.call('GET', '/v1/me/roster', { token: b.token })).json).toEqual({ names: [] });
    expect((await t.call('PUT', '/v1/me/roster', { token: a.token, body: { names: ['Sami', 'sami '] } })).json).toEqual({ error: 'dup_names' });
    for (const names of [Array.from({ length: 31 }, (_, i) => 'P' + i), ['x'.repeat(19)], ['  ']]) {
      expect((await t.call('PUT', '/v1/me/roster', { token: a.token, body: { names } })).status).toBe(400);
    }
    expect((await t.call('GET', '/v1/me/roster')).status).toBe(401);
  });

  it('setup: checked with the engine limits; kept with the names; deleted with the account', async () => {
    const t = await setup(), a = await t.user('Sami');
    expect((await t.call('GET', '/v1/me/setup', { token: a.token })).json).toEqual({ setup: null });
    const s = { counts: { mafia: 2, detective: 1 }, rules: { ...rules, nightT: 60 } };
    expect((await t.call('PUT', '/v1/me/setup', { token: a.token, body: s })).json).toEqual({ setup: s });
    await t.call('PUT', '/v1/me/roster', { token: a.token, body: { names: ['Dareer'] } });
    expect((await t.call('GET', '/v1/me/setup', { token: a.token })).json).toEqual({ setup: s });
    expect((await t.call('GET', '/v1/me/roster', { token: a.token })).json).toEqual({ names: ['Dareer'] });
    for (const bad of [{ counts: { mafia: 1, detective: 1 }, rules }, { counts: { mafia: 10, detective: 0 }, rules },
      { counts: { mafia: 1, detective: 0 }, rules: { ...rules, nightT: 50 } }, { counts: { mafia: 1, detective: 0 }, rules: { ...rules, extra: 1 } }]) {
      expect((await t.call('PUT', '/v1/me/setup', { token: a.token, body: bad })).status).toBe(400);
    }
    expect((await t.call('DELETE', '/v1/me', { token: a.token, body: { confirm: 'delete' } })).status).toBe(200);
    expect(await t.env.DB.prepare('SELECT COUNT(*) AS n FROM saved').first('n')).toBe(0);
  });
});

describe('safety: block, report, ban (Sprint 5)', () => {
  it('block: ends the friendship, hides requests both ways (they are not told), listed and undone', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Hokan');
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Hokan' } });
    await t.call('POST', '/v1/friend-requests', { token: b.token, body: { handle: 'Sami' } });
    expect((await t.call('GET', '/v1/friends', { token: a.token })).json.friends).toHaveLength(1);
    expect((await t.call('POST', '/v1/blocks', { token: a.token, body: { userId: b.id } })).json).toEqual({ ok: true });
    expect((await t.call('GET', '/v1/friends', { token: a.token })).json.friends).toHaveLength(0);
    // Hokan asks again: he sees "requested", but Sami is never asked
    expect((await t.call('POST', '/v1/friend-requests', { token: b.token, body: { handle: 'Sami' } })).json.rel).toBe('requested');
    expect((await t.call('GET', '/v1/friends', { token: a.token })).json.incoming).toHaveLength(0);
    expect((await t.call('GET', '/v1/notifications', { token: a.token })).json.notifications.filter((n: any) => n.from.id === b.id)).toHaveLength(0);
    // Sami must unblock before asking Hokan
    expect((await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Hokan' } })).json).toEqual({ error: 'blocked' });
    expect((await t.call('GET', '/v1/blocks', { token: a.token })).json.blocked.map((x: any) => x.handle)).toEqual(['Hokan']);
    expect((await t.call('POST', '/v1/blocks', { token: a.token, body: { userId: a.id } })).status).toBe(400);
    await t.call('DELETE', '/v1/blocks/' + b.id, { token: a.token });
    expect((await t.call('GET', '/v1/blocks', { token: a.token })).json.blocked).toEqual([]);
  });

  it('report a player; only the admin sees reports; a ban signs them out and refuses new sign-ins; reports outlive the account', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Hokan'), admin = await t.user('Boss');
    expect((await t.call('POST', '/v1/reports', { token: a.token, body: { userId: b.id, reason: 'spam', note: 'ads in chat' } })).json).toEqual({ ok: true });
    expect((await t.call('POST', '/v1/reports', { token: a.token, body: { userId: b.id, reason: 'rude' } })).status).toBe(400);
    expect((await t.call('GET', '/v1/admin/reports', { token: admin.token })).status).toBe(403);
    t.env.ADMIN_IDS = admin.id;
    expect((await t.call('GET', '/v1/me', { token: admin.token })).json.user.admin).toBe(true);
    expect((await t.call('GET', '/v1/me', { token: a.token })).json.user.admin).toBe(false);
    const list = (await t.call('GET', '/v1/admin/reports', { token: admin.token })).json.reports;
    expect(list).toHaveLength(1);
    expect(list[0]).toMatchObject({ reason: 'spam', note: 'ads in chat', display: 'hokan', handle: 'Hokan', reporter: 'sami', message: null });
    expect((await t.call('POST', '/v1/admin/reports/' + list[0].id, { token: admin.token, body: { action: 'ban' } })).json).toEqual({ ok: true });
    expect((await t.call('GET', '/v1/me', { token: b.token })).status).toBe(401);
    await t.call('POST', '/v1/auth/email/start', { body: { email: 'hokan@example.com' } });
    const code = t.mail.filter(m => m.to === 'hokan@example.com').at(-1)!.code;
    expect((await t.call('POST', '/v1/auth/email/verify', { body: { email: 'hokan@example.com', code, device: 'x' } })).json).toEqual({ error: 'banned' });
    expect((await t.call('GET', '/v1/admin/reports', { token: admin.token })).json.reports).toHaveLength(0);
    // the reporter deletes their account: the report stays (for moderation), without them
    await t.call('POST', '/v1/reports', { token: a.token, body: { userId: admin.id, reason: 'other' } });
    await t.call('DELETE', '/v1/me', { token: a.token, body: { confirm: 'delete' } });
    expect((await t.call('GET', '/v1/admin/reports', { token: admin.token })).json.reports[0]).toMatchObject({ reason: 'other', reporter: null });
  });
});

// [S13-4 / his note 12] finding people without their exact @username. [QA] tried: one letter, wrong case, an Arabic name,
// a "%" (a SQL wildcard that must stay a letter), myself, a blocked and a banned account.
describe('friend search (Sprint 13)', () => {
  it('2+ letters: the start of an @handle or any part of a name, any case; never me, blocked or banned', async () => {
    const t = await setup(), me = await t.user('Sami'), d = await t.user('Dareer'), h = await t.user('Halawy'), x = await t.user('Xavier'), b = await t.user('Badguy');
    await t.call('PATCH', '/v1/me', { token: h.token, body: { display: 'Mohammed Halawy' } });
    await t.call('PATCH', '/v1/me', { token: x.token, body: { display: 'خالد' } });
    const find = async (q: string, tok = me.token) => (await t.call('GET', '/v1/users?q=' + encodeURIComponent(q), { token: tok }));
    expect((await find('d')).status).toBe(400);
    expect((await find('DAR')).json.users.map((u: any) => u.handle)).toEqual(['Dareer']);
    expect((await find('@dar')).json.users.map((u: any) => u.handle)).toEqual(['Dareer']);
    expect((await find('hammed')).json.users.map((u: any) => u.handle)).toEqual(['Halawy']);  // inside a display name
    expect((await find('خال')).json.users.map((u: any) => u.handle)).toEqual(['Xavier']);
    expect((await find('%a')).json.users).toEqual([]);  // "%" is a letter here, not "anything"
    expect((await find('sam')).json.users).toEqual([]);  // never myself
    await t.call('POST', '/v1/friend-requests', { token: me.token, body: { handle: 'Dareer' } });
    expect((await find('dareer')).json.users[0]).toMatchObject({ handle: 'Dareer', rel: 'requested' });
    await t.call('POST', '/v1/blocks', { token: b.token, body: { userId: me.id } });
    expect((await find('badg')).json.users).toEqual([]);  // blocked me: I can't find them
    expect((await find('sami', b.token)).json.users).toEqual([]);  // nor they me
    await DB().prepare('UPDATE users SET banned_at = 1 WHERE id = ?').bind(d.id).run();
    expect((await find('dareer')).json.users).toEqual([]);
  });
});
