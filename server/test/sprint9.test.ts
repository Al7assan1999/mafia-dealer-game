// Sprint 9: the bell keeps answered items 24 h with their result (S9-5 AC2). The kick rule is in rooms.test.ts.
import { describe, expect, it } from 'vitest';
import { setup } from './helpers.ts';

describe('bell history', () => {
  it('answered items stay 24 h, read-only, with their result; only what waits counts as unread; Clear keeps what still waits', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Dareer'), c = await t.user('Hokan');
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Dareer' } });
    await t.call('POST', '/v1/friend-requests', { token: c.token, body: { handle: 'Dareer' } });
    let bell = (await t.call('GET', '/v1/notifications', { token: b.token })).json;
    expect(bell.unread).toBe(2);
    expect(bell.notifications.every((n: any) => n.result === null)).toBe(true);
    // declined from the Friends screen: the bell item is answered too
    await t.call('DELETE', '/v1/friend-requests/' + a.id, { token: b.token });
    // accepted
    await t.call('POST', `/v1/friend-requests/${c.id}/accept`, { token: b.token });
    bell = (await t.call('GET', '/v1/notifications', { token: b.token })).json;
    expect(bell.unread).toBe(0);
    expect(bell.notifications.map((n: any) => [n.from.handle, n.result, n.read]).sort()).toEqual([['Hokan', 'accepted', true], ['Sami', 'declined', true]]);
    // a day later they're gone on their own
    t.clock.t += 24 * 3600e3 + 1;
    expect((await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications).toEqual([]);
  });

  it('✕ on a waiting item = Dismissed (kept); ✕ again removes it; Join is recorded; Clear spares what still waits', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Dareer'), c = await t.user('Hokan');
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Dareer' } });
    await t.call('POST', '/v1/friend-requests', { token: c.token, body: { handle: 'Dareer' } });
    const [x, y] = (await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications;
    await t.call('DELETE', '/v1/notifications/' + x.id, { token: b.token });
    let bell = (await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications;
    expect(bell.find((n: any) => n.id === x.id)).toMatchObject({ result: 'dismissed', read: true });
    await t.call('DELETE', '/v1/notifications/' + x.id, { token: b.token });
    bell = (await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications;
    expect(bell.map((n: any) => n.id)).toEqual([y.id]);
    expect((await t.call('POST', `/v1/notifications/${y.id}/handled`, { token: b.token, body: { result: 'nonsense' } })).status).toBe(400);
    await t.call('DELETE', '/v1/notifications', { token: b.token });  // Clear: y still waits for an answer, so it stays
    expect((await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications.map((n: any) => n.id)).toEqual([y.id]);
    await t.call('POST', `/v1/notifications/${y.id}/handled`, { token: b.token, body: { result: 'joined' } });
    expect((await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications[0]).toMatchObject({ result: 'joined' });
    await t.call('DELETE', '/v1/notifications', { token: b.token });
    expect((await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications).toEqual([]);
  });

  it('an item nobody answered shows as Expired for a day after it lapses', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Dareer');
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Dareer' } });
    t.clock.t += 7 * 24 * 3600e3 + 1;  // friend notes last 7 days
    const bell = (await t.call('GET', '/v1/notifications', { token: b.token })).json;
    expect(bell).toMatchObject({ unread: 0, notifications: [{ kind: 'friend_request', result: 'expired', read: true }] });
    t.clock.t += 24 * 3600e3;
    expect((await t.call('GET', '/v1/notifications', { token: b.token })).json.notifications).toEqual([]);
  });
});
