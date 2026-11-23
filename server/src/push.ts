// Push notifications (Firebase Cloud Messaging, HTTP v1). A push goes out only when the person's app is closed (no hub
// socket); an open app gets the live bell instead. Each device registers its token with its session, so sign-out,
// removing the device or deleting the account drops it (ON DELETE CASCADE).
import { Hono } from 'hono';
import { importPKCS8, SignJWT } from 'jose';
import { PushTokenIn } from '@mafia/protocol';
import { body, type AppEnv, type Deps, type Env } from './lib.ts';

/** One notification for one device. channel = the Android channel (the app creates them); tag replaces an older one. */
export interface PushMsg { token: string; title: string; body: string; channel: 'invites' | 'friends' | 'approvals' | 'titles'; tag: string; data: Record<string, string> }
/** Sends pushes; returns the tokens FCM says are gone (the app was uninstalled), which are then deleted. */
export type PushSender = (env: Env, msgs: PushMsg[]) => Promise<string[]>;

export type PushKind = 'invite' | 'join_request' | 'let_in' | 'friend_request' | 'friend_accept' | 'wifi_confirm' | 'approved' | 'declined' | 'expired' | 'title_lost' | 'test';
const RLM = String.fromCharCode(0x200f);  // keeps an Arabic line right-to-left when it starts with a Latin name
const TEXT: Record<'en' | 'ar', Record<PushKind, (n: string, code: string) => string>> = {
  en: {
    invite: (n, c) => `${n} invited you to room ${c}`,
    join_request: n => `${n} wants to join your room`,
    let_in: n => `${n} let you in. Tap to join.`,
    friend_request: n => `${n} wants to be your friend`,
    friend_accept: n => `${n} accepted your friend request`,
    wifi_confirm: n => `${n} asks to add a Wi-Fi game to online history. Confirm it?`,
    approved: () => 'Your Wi-Fi game was added to online history',
    declined: () => 'Your Wi-Fi game was not added: a player said Not me',
    expired: () => 'Your Wi-Fi game was not added: not everyone confirmed in time',
    title_lost: (n, t) => `${n} took ${t} from you`,
    test: () => 'Notifications work on this phone ✓',
  },
  ar: {
    invite: (n, c) => `${RLM}${n} دعاك إلى الغرفة ${c}`,
    join_request: n => `${RLM}${n} يريد الانضمام إلى غرفتك`,
    let_in: n => `${RLM}${n} سمح لك بالدخول. اضغط للانضمام.`,
    friend_request: n => `${RLM}${n} يريد أن يكون صديقك`,
    friend_accept: n => `${RLM}${n} قبل طلب صداقتك`,
    wifi_confirm: n => `${RLM}${n} يطلب إضافة لعبة واي فاي إلى السجل عبر الإنترنت. هل تؤكد؟`,
    approved: () => 'أُضيفت لعبة الواي فاي إلى السجل عبر الإنترنت',
    declined: () => 'لم تُضف لعبة الواي فاي: أحد اللاعبين قال «لست أنا»',
    expired: () => 'لم تُضف لعبة الواي فاي: لم يؤكد الجميع في الوقت المحدد',
    title_lost: (n, t) => `${RLM}${n} أخذ منك لقب ${TITLE_AR[t] ?? t}`,
    test: () => 'الإشعارات تعمل على هذا الهاتف ✓',
  },
};
const TITLE_AR: Record<string, string> = { 'Best player': 'أفضل لاعب', 'Best Mafia': 'أفضل مافيا', 'Best Detective': 'أفضل محقق', 'Best Doctor': 'أفضل طبيب', 'Most killed first': 'الأكثر قتلًا أولًا' };
const CHANNEL: Record<PushKind, PushMsg['channel']> = {
  invite: 'invites', join_request: 'invites', let_in: 'invites', friend_request: 'friends', friend_accept: 'friends',
  wifi_confirm: 'approvals', approved: 'approvals', declined: 'approvals', expired: 'approvals', title_lost: 'titles', test: 'friends',
};

/** Pushes to every device of `uid`. `tag` makes a newer push replace an older one (one per sender and kind). */
export async function sendPush(env: Env, deps: Deps, uid: string, kind: PushKind, o: { name?: string; code?: string | null; tag: string; data: Record<string, string> }) {
  const { results } = await env.DB.prepare('SELECT token, lang FROM push_tokens WHERE user_id = ?').bind(uid).all<{ token: string; lang: 'en' | 'ar' }>();
  if (!results.length) return;
  const msgs = results.map(r => ({ token: r.token, title: 'Mafia Dealer', body: TEXT[r.lang][kind](o.name ?? '', o.code ?? ''), channel: CHANNEL[kind], tag: o.tag, data: { kind, ...o.data } }));
  try {
    const gone = await deps.push(env, msgs);
    if (gone.length) await env.DB.batch(gone.map(t => env.DB.prepare('DELETE FROM push_tokens WHERE token = ?').bind(t)));
  } catch (e) { console.error('push', e); }  // a push failing never fails the request that caused it
}

let cached: { token: string; until: number } | null = null;
/** The real sender. Without the FCM_SERVICE_ACCOUNT secret it sends nothing (everything else works as before). */
export const fcmSender: PushSender = async (env, msgs) => {
  if (!env.FCM_SERVICE_ACCOUNT) return [];
  const sa = JSON.parse(env.FCM_SERVICE_ACCOUNT) as { project_id: string; client_email: string; private_key: string };
  if (!cached || cached.until < Date.now() + 60e3) {
    const jwt = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' }).setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuer(sa.client_email).setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h')
      .sign(await importPKCS8(sa.private_key, 'RS256'));
    const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }) });
    if (!r.ok) throw new Error('fcm auth ' + r.status);
    const j = await r.json() as { access_token: string; expires_in: number };
    cached = { token: j.access_token, until: Date.now() + j.expires_in * 1000 };
  }
  const gone: string[] = [];
  await Promise.all(msgs.map(async m => {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: 'POST', headers: { authorization: 'Bearer ' + cached!.token, 'content-type': 'application/json' },
      body: JSON.stringify({ message: { token: m.token, data: m.data,
        android: { priority: 'high', notification: { title: m.title, body: m.body, channel_id: m.channel, tag: m.tag } } } }),
    });
    if (r.status === 404 || r.status === 410) gone.push(m.token);  // UNREGISTERED
    else if (!r.ok) console.error('fcm send', r.status, await r.text());
  }));
  return gone;
};

/** PUT /v1/me/push: this device's token (and language); DELETE: stop pushes to this device. */
export const pushRoutes = new Hono<AppEnv>();
pushRoutes.put('/', async c => {
  const { token, lang } = await body(c, PushTokenIn), db = c.env.DB, now = c.var.deps.now();
  // a token belongs to one device: if it moved to another account on this phone, the old row goes
  await db.batch([
    db.prepare('DELETE FROM push_tokens WHERE token = ? AND session_id <> ?').bind(token, c.var.sid),
    db.prepare(`INSERT INTO push_tokens (session_id, user_id, token, lang, updated_at) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (session_id) DO UPDATE SET token = excluded.token, lang = excluded.lang, updated_at = excluded.updated_at`)
      .bind(c.var.sid, c.var.user.id, token, lang, now),
  ]);
  return c.json({ ok: true });
});
/** P5: "Send me a test notification": a push to every device of mine, whether the app is open or not. */
pushRoutes.post('/test', async c => {
  const n = await c.env.DB.prepare('SELECT COUNT(*) AS n FROM push_tokens WHERE user_id = ?').bind(c.var.user.id).first<{ n: number }>();
  const mine = await c.env.DB.prepare('SELECT 1 FROM push_tokens WHERE session_id = ?').bind(c.var.sid).first();
  await sendPush(c.env, c.var.deps, c.var.user.id, 'test', { tag: 'test', data: {} });
  return c.json({ devices: n?.n ?? 0, thisPhone: !!mine, canSend: !!c.env.FCM_SERVICE_ACCOUNT });  // [R6] no key: nothing goes out
});
pushRoutes.delete('/', async c => {
  await c.env.DB.prepare('DELETE FROM push_tokens WHERE session_id = ?').bind(c.var.sid).run();
  return c.json({ ok: true });
});
