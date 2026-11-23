// One Durable Object per account ("hub"): the open app keeps a socket to it. It marks the account online, and
// everything live for that person (friends' presence, invites, join requests, friend notes) is pushed through it.
import { DurableObject } from 'cloudflare:workers';
import type { HubOut, Notification } from '@mafia/protocol';
import { card, presenceOf, type Deps, type Env, type UserRow } from './lib.ts';
import { sendPush } from './push.ts';
import { BELL_KEEP_MS } from './social.ts';
import { wifiNotes } from './wifi.ts';

export const INVITE_TTL = 30 * 60e3, NOTE_TTL = 7 * 24 * 3600e3, HUB_STALE_MS = 30e3;

export class Hub extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // keep-alives are answered by Cloudflare without waking the hub (they'd count against the daily request limit)
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  async fetch(req: Request) {
    const uid = req.headers.get('x-uid')!;
    if (req.headers.get('upgrade') === 'websocket') {
      const [client, server] = Object.values(new WebSocketPair());
      const first = this.ctx.getWebSockets().length === 0;
      await this.ctx.storage.put('uid', uid);
      this.ctx.acceptWebSocket(server);
      server.serializeAttachment({ at: Date.now() });
      if (first) await setOnline(this.env, uid, true);
      server.send(JSON.stringify({ t: 'unread', n: await unread(this.env.DB, uid, Date.now()) } satisfies HubOut));
      return new Response(null, { status: 101, webSocket: client, headers: { 'Sec-WebSocket-Protocol': 'mafia.v1' } });
    }
    // internal: send a message to this person's open app(s); answers how many got it (0 = the app is closed)
    const msg = await req.text();
    // [N4] a phone swiped away or out of signal leaves its socket "open" for a while: only one heard from in the last 30 s
    // (the app pings every 10 s, answered by Cloudflare) counts as an open app; a silent one is closed and the push goes out
    let open = 0;
    const now = Date.now();
    for (const ws of this.ctx.getWebSockets()) try {
      if (ws.readyState !== WebSocket.OPEN) continue;
      if (now - this.seen(ws) > HUB_STALE_MS) { try { ws.close(4001, 'stale'); } catch { /* gone */ } continue; }
      ws.send(msg); open++;
    } catch { /* closing */ }
    return Response.json({ open });
  }
  async webSocketMessage(ws: WebSocket, msg: string | ArrayBuffer) {
    if (msg === 'ping') { ws.send('pong'); ws.serializeAttachment({ at: Date.now() }); }  // normally answered by Cloudflare before it gets here
  }
  async webSocketClose(ws: WebSocket, code: number) {
    try { ws.close(code === 1005 ? 1000 : code, 'bye'); } catch { /* already closed */ }
    if (!this.ctx.getWebSockets().some(w => w !== ws && w.readyState === WebSocket.OPEN)) {
      const uid = await this.uid(); if (uid) await setOnline(this.env, uid, false);
    }
  }
  async webSocketError(ws: WebSocket) { await this.webSocketClose(ws, 1011); }
  /** When this socket last showed life: connected, or answered a ping (Cloudflare's auto-response keeps the time). */
  private seen(ws: WebSocket) {
    const a = ws.deserializeAttachment() as { at?: number } | null;
    return Math.max(a?.at ?? 0, this.ctx.getWebSocketAutoResponseTimestamp(ws)?.getTime() ?? 0);
  }
  /** The hub's account id (its name). Kept in storage so it survives hibernation. */
  private async uid() { return this.ctx.storage.get<string>('uid'); }
}

/** Sends a message to someone's open app. Returns false when the app is closed (nobody got it). */
export async function pushTo(env: Env, uid: string, msg: HubOut) {
  const r = await env.HUB.get(env.HUB.idFromName(uid)).fetch('https://hub/push', { method: 'POST', body: JSON.stringify(msg) });
  return ((await r.json()) as { open: number }).open > 0;
}

/** Unread bell items: notes plus the Wi-Fi confirmations and results. */
export async function unread(db: D1Database, uid: string, now: number) {
  const n = await db.prepare('SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND read_at IS NULL AND created_at > ?').bind(uid, now - BELL_KEEP_MS).first<{ n: number }>();
  const b = await db.prepare('SELECT COUNT(*) AS n FROM bell_notes WHERE user_id = ? AND read_at IS NULL AND expires_at > ?').bind(uid, now).first<{ n: number }>();
  return (n?.n ?? 0) + (b?.n ?? 0) + (await wifiNotes(db, uid, now)).filter(x => !x.read).length;
}

/** Tells this person's online friends how they look now (online, in a lobby / game). */
export async function pushPresence(env: Env, uid: string) {
  const u = await env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(uid).first<UserRow>();
  if (!u) return;
  const p = presenceOf(u);
  const { results } = await env.DB.prepare(
    `SELECT u.id FROM friendships f JOIN users u ON u.id = CASE WHEN f.a = ?1 THEN f.b ELSE f.a END
     WHERE (f.a = ?1 OR f.b = ?1) AND f.status = 'accepted' AND u.online = 1`).bind(uid).all<{ id: string }>();
  await Promise.all(results.map(r => pushTo(env, r.id, { t: 'presence', uid, ...p })));
}

export async function setOnline(env: Env, uid: string, on: boolean) {
  await env.DB.prepare('UPDATE users SET online = ? WHERE id = ?').bind(on ? 1 : 0, uid).run();
  await pushPresence(env, uid);
}
/** In an online room (lobby or game), or out of it (code null). */
export async function setRoom(env: Env, uid: string, code: string | null, status: '' | 'lobby' | 'game') {
  const r = await env.DB.prepare('UPDATE users SET room_code = ?, room_status = ? WHERE id = ? AND (room_code IS NOT ? OR room_status <> ?)')
    .bind(code, code ? status : '', uid, code, code ? status : '').run();
  if (r.meta.changes) await pushPresence(env, uid);
}

/** Puts a note in someone's bell and shows it live if their app is open, else sends a push. */
export async function notify(env: Env, deps: Deps, to: string, from: UserRow, kind: Exclude<Notification['kind'], 'wifi_confirm' | 'wifi_result'>, code: string | null, now: number) {
  const id = crypto.randomUUID(), room = kind === 'invite' || kind === 'let_in';
  const expiresAt = now + (room || kind === 'join_request' ? INVITE_TTL : NOTE_TTL);
  await env.DB.prepare('INSERT INTO notifications (id, user_id, from_id, kind, room_code, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .bind(id, to, from.id, kind, room ? code : null, now, expiresAt).run();
  const note: Notification = { id, kind, from: card(from, 'none'), code: room ? code : null, at: now, expiresAt, read: false };
  if (!(await pushTo(env, to, { t: 'note', note })))
    await sendPush(env, deps, to, kind, { name: from.display, code, tag: kind + ':' + from.id, data: { id, ...(note.code ? { code: note.code } : {}) } });
  return id;
}
