// Sprint 9: the bell keeps answered items 24 h with their result (S9-5 AC2). The kick rule is in rooms.test.ts.
import { describe, expect, it } from 'vitest';
import { setup } from './helpers.ts';

describe('bell history (Sprint 10 N8: 30 days, at most 200, read state of its own)', () => {
  it('answered items stay with their result and count as read; a friend request never "expires"; 30 days later they are gone', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Dareer'), c = await t.user('Hokan');
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Dareer' } });
    await t.call('POST', '/v1/friend-requests', { token: c.token, body: { handle: 'Dareer' } });
    let bell = (await t.call('GET', '/v1/notifications', { token: b.token })).json;
    expect(bell.unread).toBe(2);
    await t.call('DELETE', '/v1/friend-requests/' + a.id, { token: b.token });   // declined from Friends: answered in the bell too
    t.clock.t += 8 * 24 * 3600e3;                                                   // past the old 7-day note life
    bell = (await t.call('GET', '/v1/notifications', { token: b.token })).json;
    expect(bell.notifications.map((n: any) => [n.from.handle, n.result, n.read]).sort()).toEqual([['Hokan', null, false], ['Sami', 'declined', true]]);
    expect(bell.unread).toBe(1);                                                    // Hokan's request still waits
    t.clock.t += 23 * 24 * 3600e3;
    expect((await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications).toEqual([]);
  });

  it('✕ = Dismissed (kept); ✕ again removes it; Join is recorded; read is separate from answered; Clear spares what still waits', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Dareer'), c = await t.user('Hokan');
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Dareer' } });
    await t.call('POST', '/v1/friend-requests', { token: c.token, body: { handle: 'Dareer' } });
    const [x, y] = (await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications;
    await t.call('POST', '/v1/notifications/read', { token: b.token, body: { ids: [y.id] } });
    let bell = (await t.call('GET', '/v1/notifications', { token: b.token })).json;
    expect(bell.notifications.find((n: any) => n.id === y.id)).toMatchObject({ read: true, result: null });  // read, still waiting
    await t.call('DELETE', '/v1/notifications/' + x.id, { token: b.token });
    bell = (await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications;
    expect(bell.find((n: any) => n.id === x.id)).toMatchObject({ result: 'dismissed', read: true });
    await t.call('DELETE', '/v1/notifications/' + x.id, { token: b.token });
    expect((await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications.map((n: any) => n.id)).toEqual([y.id]);
    expect((await t.call('POST', `/v1/notifications/${y.id}/handled`, { token: b.token, body: { result: 'nonsense' } })).status).toBe(400);
    await t.call('DELETE', '/v1/notifications', { token: b.token });  // Clear: y still waits for an answer, so it stays
    expect((await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications.map((n: any) => n.id)).toEqual([y.id]);
    await t.call('POST', `/v1/notifications/${y.id}/handled`, { token: b.token, body: { result: 'joined' } });
    expect((await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications[0]).toMatchObject({ result: 'joined' });
    await t.call('DELETE', '/v1/notifications', { token: b.token });
    expect((await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications).toEqual([]);
  });

  it('at most 200 per account: the oldest answered ones go first', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Dareer');
    const { DB } = await import('./live.ts');
    const now = t.clock.t;
    // 150 answered + 60 waiting = 210 items
    const rows = [...Array(210).keys()].map(i => DB().prepare("INSERT INTO notifications (id, user_id, from_id, kind, created_at, expires_at, handled_at, result) VALUES (?, ?, ?, 'friend_request', ?, ?, ?, ?)")
      .bind('n' + i, b.id, a.id, now - (210 - i) * 1000, now + 86400e3, i < 150 ? now - 500 : null, i < 150 ? 'accepted' : null));
    await DB().batch(rows);
    const bell = (await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications;
    expect(bell).toHaveLength(200);
    const left = (await DB().prepare('SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND handled_at IS NULL').bind(b.id).first<{ n: number }>())!.n;
    expect(left).toBe(60);  // every waiting item kept; the 10 oldest answered went
  });

  it('a lapsed invite reads Expired; the push test reaches my devices', async () => {
    const t = await setup(), a = await t.user('Sami');
    const { DB } = await import('./live.ts');
    await DB().prepare("INSERT INTO notifications (id, user_id, from_id, kind, room_code, created_at, expires_at) VALUES ('i1', ?, ?, 'invite', '123456', ?, ?)")
      .bind(a.id, a.id, t.clock.t - 3600e3, t.clock.t - 1800e3).run();
    expect((await t.call('GET', '/v1/notifications', { token: a.token })).json.notifications[0]).toMatchObject({ kind: 'invite', result: 'expired' });
    expect((await t.call('POST', '/v1/me/push/test', { token: a.token })).json).toEqual({ devices: 0, thisPhone: false, canSend: false });
    await t.call('PUT', '/v1/me/push', { token: a.token, body: { token: 'x'.repeat(30), lang: 'en' } });
    expect((await t.call('POST', '/v1/me/push/test', { token: a.token })).json).toEqual({ devices: 1, thisPhone: true, canSend: false });
    expect(t.pushes.at(-1)).toMatchObject({ body: 'Notifications work on this phone ✓', channel: 'friends' });
  });
});
