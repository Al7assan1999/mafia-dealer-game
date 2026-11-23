// Sprint 7: push notifications (S7-1) and Wi-Fi games added to online history by automatic rules (S7-2).
import { describe, expect, it } from 'vitest';
import { createGame, DEFAULT_RULES, nightOptions, startRecord, step, type Action, type GameRecord, type GameState } from '@mafia/engine';
import { setup } from './helpers.ts';
import { DB } from './live.ts';

type T = Awaited<ReturnType<typeof setup>>;
const NAMES = ['Sami', 'Dareer', 'Hokan', 'Fater'];

/** A whole Wi-Fi game played on the engine: the Mafia kills, the day names the Mafia. Actions `gap` ms apart. */
function wifiGame(start: number, gap = 30_000, names = NAMES): GameRecord {
  const c = createGame({ names, counts: { mafia: 1, doctor: 1, detective: 0 }, rules: DEFAULT_RULES }, () => 0.5);
  if (!c.ok) throw new Error(c.error);
  let s: GameState = c.state, now = start;
  const rec = startRecord(s);
  const go = (a: Action) => { const r = step(rec, s, a, { rng: () => 0.5, now: now += gap }); if (!r.ok) throw new Error(a.t + ' ' + r.error); s = r.state; };
  go({ t: 'begin' });
  for (const seat of s.alive.map((_, i) => i)) {
    const o = nightOptions(s, seat);
    go({ t: 'night', seat, choice: o.key === 'none' ? null : o.opts.find(x => !x.disabled)!.seat, day: 1 });
  }
  go({ t: 'startDay' });
  go({ t: 'decide', choice: s.roles.indexOf('mafia') });
  if (s.phase !== 'end') throw new Error('not over');
  return rec;
}

async function hub(t: T, tok: string) {
  const r = await t.app.request('/v1/hub/ws', { headers: { upgrade: 'websocket', 'sec-websocket-protocol': 'mafia.v1, ' + tok } }, t.env);
  const ws = r.webSocket!; ws.accept();
  const msgs: any[] = []; ws.addEventListener('message', e => msgs.push(JSON.parse(e.data as string)));
  return { ws, msgs };
}
const wait = (ms: number) => new Promise(r => setTimeout(r, ms));

/** Four signed-in players, each with a push token; [0] hosts. */
async function table(t: T) {
  const ps = [];
  for (const h of NAMES) {
    const u = await t.user(h);
    await t.call('PUT', '/v1/me/push', { token: u.token, body: { token: 'tok-' + h + '-'.repeat(20), lang: 'en' } });
    ps.push(u);
  }
  return ps;
}
const ask = (t: T, host: { token: string }, ps: { id: string }[], rec: GameRecord, extra: Record<string, unknown> = {}) =>
  t.call('POST', '/v1/wifi-requests', { token: host.token, body: { key: '123456-' + rec.actions.at(-1)!.at, record: rec, seats: ps.map((p, seat) => ({ seat, userId: p.id, name: rec.names[seat] })), app: '0.2.0', ...extra } });

describe('push notifications', () => {
  it('a closed app gets a push in its language, on the right channel, replacing the same sender\'s older one', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Dareer');
    expect((await t.call('PUT', '/v1/me/push', { token: b.token, body: { token: 'x'.repeat(30), lang: 'ar' } })).json).toEqual({ ok: true });
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Dareer' } });
    expect(t.pushes).toHaveLength(1);
    expect(t.pushes[0]).toMatchObject({ token: 'x'.repeat(30), title: 'Mafia Dealer', channel: 'friends', tag: 'friend_request:' + a.id, data: { kind: 'friend_request' } });
    expect(t.pushes[0].body).toBe(String.fromCharCode(0x200f) + 'sami يريد أن يكون صديقك');  // display = the email's name until changed
    await t.call('POST', '/v1/friend-requests', { token: b.token, body: { handle: 'Sami' } });  // accepting: Sami has no token, nothing sent
    expect(t.pushes).toHaveLength(1);
    expect((await t.call('PUT', '/v1/me/push', { token: b.token, body: { token: 'short', lang: 'en' } })).status).toBe(400);
    expect((await t.call('PUT', '/v1/me/push', { token: b.token, body: { token: 'x'.repeat(30), lang: 'fr' } })).status).toBe(400);
  });

  it('an open app gets the live bell and no push', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Dareer');
    await t.call('PUT', '/v1/me/push', { token: b.token, body: { token: 'y'.repeat(30), lang: 'en' } });
    const h = await hub(t, b.token);
    await wait(50);
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Dareer' } });
    await wait(50);
    expect(t.pushes).toHaveLength(0);
    expect(h.msgs.some(m => m.t === 'note' && m.note.kind === 'friend_request')).toBe(true);
    h.ws.close();
  });

  it('tokens go with sign-out, a removed device, account deletion, and when FCM says the app is gone', async () => {
    const t = await setup(), a = await t.user('Sami'), b = await t.user('Dareer');
    const count = async () => (await DB().prepare('SELECT COUNT(*) AS n FROM push_tokens').first<{ n: number }>())!.n;
    await t.call('PUT', '/v1/me/push', { token: b.token, body: { token: 'gone' + 'z'.repeat(30), lang: 'en' } });
    await t.call('POST', '/v1/friend-requests', { token: a.token, body: { handle: 'Dareer' } });
    expect(t.pushes).toHaveLength(1);
    expect(await count()).toBe(0);  // uninstalled: deleted
    await t.call('PUT', '/v1/me/push', { token: b.token, body: { token: 'b'.repeat(30), lang: 'en' } });
    await t.call('PUT', '/v1/me/push', { token: b.token, body: { token: 'c'.repeat(30), lang: 'en' } });  // a new token replaces the device's old one
    expect(await count()).toBe(1);
    await t.call('POST', '/v1/auth/logout', { token: b.token });
    expect(await count()).toBe(0);
    const b2 = await t.signInEmail('dareer@example.com', 'Phone 2'), b3 = await t.signInEmail('dareer@example.com', 'Phone 3');
    await t.call('PUT', '/v1/me/push', { token: b2.token, body: { token: 'd'.repeat(30), lang: 'en' } });
    await t.call('PUT', '/v1/me/push', { token: b3.token, body: { token: 'e'.repeat(30), lang: 'en' } });
    const list = (await t.call('GET', '/v1/sessions', { token: b3.token })).json.sessions as { id: string; current: boolean }[];
    await t.call('DELETE', '/v1/sessions/' + list.find(s => !s.current)!.id, { token: b3.token });
    expect(await count()).toBe(1);
    await t.call('PUT', '/v1/me/push', { token: a.token, body: { token: 'e'.repeat(30), lang: 'en' } });  // the same phone, now Sami's
    expect((await DB().prepare('SELECT user_id FROM push_tokens').all()).results).toEqual([{ user_id: a.id }]);
    await t.call('DELETE', '/v1/me', { token: a.token, body: { confirm: 'delete' } });
    expect(await count()).toBe(0);
  });

  it('every kind has an English and an Arabic text', async () => {
    const { sendPush } = await import('../src/push.ts');
    const t = await setup(), a = await t.user('Sami');
    await t.call('PUT', '/v1/me/push', { token: a.token, body: { token: 'f'.repeat(30), lang: 'ar' } });
    const deps = { push: async (_e: unknown, m: any[]) => { t.pushes.push(...m); return []; } } as any;
    for (const k of ['invite', 'join_request', 'let_in', 'friend_request', 'friend_accept', 'wifi_confirm', 'approved', 'declined', 'expired'] as const)
      await sendPush(t.env, deps, a.id, k, { name: 'Dareer', code: '123456', tag: k, data: {} });
    expect(t.pushes.map(p => p.channel)).toEqual(['invites', 'invites', 'invites', 'friends', 'friends', 'approvals', 'approvals', 'approvals', 'approvals']);
    expect(t.pushes.every(p => /[؀-ۿ]/.test(p.body))).toBe(true);
    expect(t.pushes[0].body).toContain('123456');
  });
});

describe('Wi-Fi games into online history', () => {
  it('asked, confirmed by everyone, approved: in History → Wi-Fi on every player\'s account, not in online history', async () => {
    const t = await setup(), ps = await table(t), rec = wifiGame(t.clock.t - 3600e3);
    const r = await ask(t, ps[0], ps, rec);
    expect(r.json).toMatchObject({ status: 'pending', reason: null });
    // the three others: a push each (their apps are closed) and a bell item with their seat and role
    expect(t.pushes.map(p => [p.token.split('-')[1], p.channel, p.data.kind])).toEqual([['Dareer', 'approvals', 'wifi_confirm'], ['Hokan', 'approvals', 'wifi_confirm'], ['Fater', 'approvals', 'wifi_confirm']]);
    const bell = (await t.call('GET', '/v1/notifications', { token: ps[1].token })).json;
    expect(bell.unread).toBe(1);
    expect(bell.notifications[0]).toMatchObject({ id: 'w:' + r.json.id, kind: 'wifi_confirm', from: { handle: 'Sami' }, read: false,
      wifi: { request: r.json.id, status: 'pending', players: 4, winner: 'citizens', seat: 1, role: rec.roles[1] } });
    // the host sees the progress
    let mine = (await t.call('GET', '/v1/wifi-requests', { token: ps[0].token })).json.games;
    expect(mine).toMatchObject([{ id: r.json.id, key: '123456-' + rec.actions.at(-1)!.at, status: 'pending', host: true, waiting: 3, total: 4, record: null }]);
    for (const p of ps.slice(1, 3)) expect((await t.call('POST', `/v1/wifi-requests/${r.json.id}/answer`, { token: p.token, body: { yes: true } })).json).toEqual({ status: 'pending' });
    expect((await t.call('POST', `/v1/wifi-requests/${r.json.id}/answer`, { token: ps[1].token, body: { yes: false } })).json).toEqual({ status: 'pending' });  // can't change an answer
    expect((await t.call('POST', `/v1/wifi-requests/${r.json.id}/answer`, { token: ps[3].token, body: { yes: true } })).json).toEqual({ status: 'approved' });
    expect(t.pushes.at(-1)).toMatchObject({ token: 'tok-Sami' + '-'.repeat(20), data: { kind: 'approved' }, tag: 'wifi:' + r.json.id });
    mine = (await t.call('GET', '/v1/wifi-requests', { token: ps[2].token })).json.games;
    expect(mine).toMatchObject([{ status: 'approved', host: false, waiting: 0, seat: 2, gameId: 'w-' + r.json.id }]);
    expect(mine[0].record.actions).toHaveLength(rec.actions.length);
    expect((await t.call('GET', '/v1/games', { token: ps[2].token })).json.games).toEqual([]);  // online history stays online games
    expect((await t.call('GET', '/v1/games/w-' + r.json.id, { token: ps[2].token })).json).toMatchObject({ winner: 'citizens', days: 1, players: [{ name: 'Sami', userId: ps[0].id }, {}, {}, {}] });
    const hostBell = (await t.call('GET', '/v1/notifications', { token: ps[0].token })).json;
    expect(hostBell.notifications).toMatchObject([{ kind: 'wifi_result', wifi: { status: 'approved' }, read: false }]);
    await t.call('POST', '/v1/notifications/read', { token: ps[0].token, body: { ids: ['w:' + r.json.id] } });
    expect((await t.call('GET', '/v1/notifications', { token: ps[0].token })).json.unread).toBe(0);
    await t.call('DELETE', '/v1/notifications/w:' + r.json.id, { token: ps[0].token });
    expect((await t.call('GET', '/v1/notifications', { token: ps[0].token })).json.notifications).toEqual([]);
    expect((await t.call('GET', '/v1/notifications', { token: ps[1].token })).json.notifications).toEqual([]);  // answered: gone from the bell
  });

  it('the automatic checks: each failure is kept with its reason', async () => {
    const t = await setup(), ps = await table(t), now = t.clock.t, ok = wifiGame(now - 3600e3);
    const reason = async (rec: GameRecord, extra?: Record<string, unknown>, who = ps[0]) => (await ask(t, who, ps, rec, extra)).json;
    const edited = structuredClone(ok); edited.winner = 'mafia';
    expect(await reason(edited)).toMatchObject({ status: 'rejected', reason: 'replay' });
    const unfinished = structuredClone(ok); unfinished.actions = unfinished.actions.slice(0, -1); unfinished.winner = null; unfinished.log = unfinished.log.slice(0, -2);
    expect((await reason(unfinished)).status).toBe('rejected');
    expect(await reason(ok, { seats: ps.map((p, seat) => ({ seat, userId: p.id, name: seat ? ok.names[seat] : 'Someone' })) })).toMatchObject({ reason: 'seats' });
    expect(await reason(ok, { seats: ps.map((p, seat) => ({ seat, userId: seat === 1 ? ps[2].id : p.id, name: ok.names[seat] })) })).toMatchObject({ reason: 'seats' });
    expect(await reason(ok, { seats: ps.map((p, seat) => ({ seat, userId: seat === 3 ? 'nobody' : p.id, name: ok.names[seat] })) })).toMatchObject({ reason: 'seats' });
    const outsider = await t.user('Halawy');
    expect((await ask(t, outsider, ps, ok)).json).toMatchObject({ reason: 'seats' });  // not one of the players
    expect(await reason(wifiGame(now - 3600e3, 5_000))).toMatchObject({ reason: 'short' });  // 9 actions 5 s apart for one round
    expect(await reason(wifiGame(now - 8 * 86400e3))).toMatchObject({ reason: 'old' });
    expect(await reason(wifiGame(now + 3600e3))).toMatchObject({ reason: 'old' });  // from the future
    expect((await reason(ok)).status).toBe('pending');
    expect(await reason(ok)).toMatchObject({ reason: 'dup' });
    // a guest seat or a malformed request isn't kept at all
    expect((await ask(t, ps[0], ps, ok, { seats: ps.map((p, seat) => ({ seat, name: ok.names[seat] })) })).status).toBe(400);
    expect((await ask(t, ps[0], ps.slice(0, 3), ok)).status).toBe(400);
    expect((await t.call('POST', '/v1/wifi-requests', { body: { key: 'x', record: ok, seats: [] } })).status).toBe(401);
    const kept = (await DB().prepare('SELECT status, reason, rules_version FROM wifi_requests ORDER BY created_at').all()).results;
    expect(kept).toHaveLength(11);
    expect(kept.every((k: any) => k.rules_version === 1)).toBe(true);
  });

  it('the daily limit comes from the settings row, and a changed row is the version later requests record', async () => {
    const t = await setup(), ps = await table(t), now = t.clock.t;
    try {
      await DB().prepare("UPDATE settings SET value = json_set(value, '$.perHostPerDay', 2, '$.version', 2) WHERE key = 'wifi_rules'").run();
      expect((await ask(t, ps[0], ps, wifiGame(now - 3600e3))).json.status).toBe('pending');
      expect((await ask(t, ps[0], ps, wifiGame(now - 7200e3))).json.status).toBe('pending');
      expect((await ask(t, ps[0], ps, wifiGame(now - 9000e3))).status).toBe(429);
      expect((await ask(t, ps[1], ps, wifiGame(now - 9000e3))).json.status).toBe('pending');  // per host
      t.clock.t += 86400e3 + 1;
      expect((await ask(t, ps[0], ps, wifiGame(t.clock.t - 3600e3))).json.status).toBe('pending');
      expect((await DB().prepare('SELECT DISTINCT rules_version AS v FROM wifi_requests').all()).results).toEqual([{ v: 2 }]);
    } finally {
      await DB().prepare("UPDATE settings SET value = json_set(value, '$.perHostPerDay', 10, '$.version', 1) WHERE key = 'wifi_rules'").run();
    }
  });

  it('"Not me" declines it, and the window running out expires it; the host hears either way', async () => {
    const t = await setup(), ps = await table(t), now = t.clock.t;
    const a = (await ask(t, ps[0], ps, wifiGame(now - 3600e3))).json, b = (await ask(t, ps[0], ps, wifiGame(now - 7200e3))).json;
    expect((await t.call('POST', `/v1/wifi-requests/${a.id}/answer`, { token: ps[2].token, body: { yes: false } })).json).toEqual({ status: 'declined' });
    expect((await t.call('POST', `/v1/wifi-requests/${a.id}/answer`, { token: ps[1].token, body: { yes: true } })).json).toEqual({ status: 'declined' });
    expect(t.pushes.at(-1)).toMatchObject({ data: { kind: 'declined' } });
    expect((await t.call('POST', `/v1/wifi-requests/${a.id}/answer`, { token: (await t.user('Halawy')).token, body: { yes: true } })).status).toBe(404);
    t.clock.t += 48 * 3600e3 + 1;
    const bell = (await t.call('GET', '/v1/notifications', { token: ps[0].token })).json.notifications;
    expect(bell.map((n: any) => [n.wifi.request, n.wifi.status, n.wifi.reason])).toEqual([[b.id, 'expired', 'expired'], [a.id, 'declined', 'not_me']]);
    expect(t.pushes.at(-1)).toMatchObject({ data: { kind: 'expired' } });
    expect((await t.call('GET', '/v1/notifications', { token: ps[1].token })).json.notifications).toEqual([]);  // nothing left to confirm
    expect((await t.call('POST', `/v1/wifi-requests/${b.id}/answer`, { token: ps[1].token, body: { yes: true } })).json).toEqual({ status: 'expired' });
    // the cron does the same without anyone opening the app
    const c = (await ask(t, ps[0], ps, wifiGame(t.clock.t - 3600e3))).json;
    const { expire } = await import('../src/wifi.ts');
    await expire(t.env, { push: async () => [] } as any, t.clock.t + 49 * 3600e3);
    expect((await DB().prepare('SELECT status FROM wifi_requests WHERE id = ?').bind(c.id).first())).toEqual({ status: 'expired' });
  });

  it('the last two confirmations at the same moment approve it once, with one game', async () => {
    const t = await setup(), ps = await table(t), r = (await ask(t, ps[0], ps, wifiGame(t.clock.t - 3600e3))).json;
    await t.call('POST', `/v1/wifi-requests/${r.id}/answer`, { token: ps[1].token, body: { yes: true } });
    const both = await Promise.all([2, 3].map(i => t.call('POST', `/v1/wifi-requests/${r.id}/answer`, { token: ps[i].token, body: { yes: true } })));
    expect(both.map(x => x.json.status).sort()).toContain('approved');
    expect((await DB().prepare("SELECT COUNT(*) AS n FROM games WHERE source = 'wifi'").first())).toEqual({ n: 1 });
    expect((await DB().prepare('SELECT COUNT(*) AS n FROM game_players WHERE game_id = ?').bind('w-' + r.id).first())).toEqual({ n: 4 });
    expect(t.pushes.filter(p => p.data.kind === 'approved')).toHaveLength(1);
  });
});
