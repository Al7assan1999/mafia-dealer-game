// Helpers for the live tests: accounts made straight in D1, REST calls and real sockets through the Worker.
import { env, SELF } from 'cloudflare:test';
import { sha256, token, type Env } from '../src/lib.ts';

export const DB = () => (env as unknown as Env).DB;

/** An account with a handle and a session, made directly in the database. */
export async function account(handle: string) {
  const id = crypto.randomUUID(), tok = token(), now = Date.now();
  await DB().batch([
    DB().prepare('INSERT INTO users (id, handle, display, created_at) VALUES (?, ?, ?, ?)').bind(id, handle, handle, now),
    DB().prepare('INSERT INTO sessions (id, token_hash, user_id, device, created_at, last_seen_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .bind(crypto.randomUUID(), await sha256(tok), id, 'test', now, now, now + 86400e3),
  ]);
  return { id, token: tok, handle };
}
export async function befriend(a: { id: string }, b: { id: string }) {
  const [x, y] = a.id < b.id ? [a.id, b.id] : [b.id, a.id];
  await DB().prepare("INSERT INTO friendships (a, b, requested_by, status, created_at, accepted_at) VALUES (?, ?, ?, 'accepted', 0, 0)").bind(x, y, x).run();
}

export async function api(method: string, path: string, tok?: string, body?: unknown) {
  const headers: Record<string, string> = {};
  if (tok) headers.authorization = 'Bearer ' + tok;
  if (body !== undefined) headers['content-type'] = 'application/json';
  const r = await SELF.fetch('https://x' + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: r.status, json: await r.json() as any };
}

export const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

/** A connected socket that remembers every message and the latest room / view. */
export async function connect(path: string, tok: string) {
  const r = await SELF.fetch('https://x' + path, { headers: { upgrade: 'websocket', 'sec-websocket-protocol': 'mafia.v1, ' + tok } });
  const ws = r.webSocket;
  if (!ws) throw new Error('no socket: ' + r.status + ' ' + await r.text());
  ws.accept();
  const s = { ws, msgs: [] as any[], room: null as any, view: null as any, me: null as any, closed: false, pongs: 0,
    send: (o: unknown) => ws.send(JSON.stringify(o)),
    /** Waits until `ok()` holds (polling), or fails after 3 s with what it last saw. */
    async until(ok: () => unknown, what = 'condition') {
      for (let i = 0; i < 300; i++) { if (ok()) return; await sleep(10); }
      throw new Error(`timed out waiting for ${what}; last: ${JSON.stringify(s.msgs.slice(-3))}`);
    },
    got: (pred: (m: any) => boolean) => s.msgs.find(pred),
  };
  ws.addEventListener('message', e => {
    if (e.data === 'pong') { s.pongs++; return; }
    const m = JSON.parse(String(e.data)); s.msgs.push(m);
    if (m.t === 'room') { s.room = m.room; s.me = m.me; }
    if (m.t === 'view') s.view = m.view;
  });
  ws.addEventListener('close', () => { s.closed = true; });
  return s;
}
export type Sock = Awaited<ReturnType<typeof connect>>;

/** The Durable Object of a room code. */
export const roomStub = (code: string) => { const ns = (env as unknown as Env).ROOM; return ns.get(ns.idFromName(code)); };
