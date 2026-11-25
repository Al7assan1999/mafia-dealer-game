// One Durable Object per online room code. It runs the lobby and the game with the shared engine (the server is the
// judge), sends each phone only its own view, keeps the room chat, and deletes everything when the room ends.
import { DurableObject } from 'cloudflare:workers';
import { createGame, DEFAULT_RULES, nameKey, startRecord, step, viewFor, type Action, type Counts, type GameEvent, type GameRecord, type GameState, type Mode, type Rules } from '@mafia/engine';
import { MODES_BUILD, RoomIn, SUBPROTOCOL, type Avatar, type ChatMsg, type RoomInfo, type RoomOut } from '@mafia/protocol';
import { canSee, edit, newChat, react, send, type ChatResult, type ChatState, type Who } from './chat.ts';
import { setRoom } from './hub.ts';
import { fcmSender } from './push.ts';
import { refreshTitles } from './stats.ts';
import { avatarOf, type Env, type UserRow } from './lib.ts';

interface Member { uid: string; cn: number; display: string; handle: string | null; avatar: Avatar; buzz: number; left?: true; v?: number }  // v: the app's build
interface RoomState {
  code: string; hostUid: string; members: Member[]; kicked: string[]; nextCn: number; sizeSent?: number;
  rules: Rules; counts: Counts; buzzMax: number; kick?: 'lobby' | 'any';  // kick: S9-4 (missing in older rooms = lobby only)
  mode?: Mode;  // 1.0.0 (missing in older rooms = Classic)
  bodyguard?: boolean;  // 1.1.0: the Sniper and Jester modes' optional Bodyguard
  deal: number; game: GameState | null; seats: string[]; ready: string[]; gameId: string | null; valid: boolean | null;
  lastActive: number;
  rev: number;                                  // grows with every change: phones reconnect with the last one they saw
  past: { rev: number; events: GameEvent[] }[]; // the last KEEP_EVENTS events, for phones that reconnect
  cut: number;                                  // the newest rev dropped from `past` (a phone behind it missed events)
  lastIn: Record<string, string>;               // each player's last applied night / vote / ready, so a retry is ignored
  rec: GameRecord | null;                       // the running game's record (saved with the game)
  blocks: Record<string, string[]>;             // who blocks whom among the members (chat isn't delivered across a block)
}

export const IDLE_MS = 12 * 3600e3, MAX_MEMBERS = 20, KEEP_EVENTS = 200;
/** A socket that sent nothing (not even its 10 s "ping") for this long is closed: the phone lost its signal. */
export const STALE_MS = 30e3;
const PROTO = { 'Sec-WebSocket-Protocol': SUBPROTOCOL };
const rng = () => crypto.getRandomValues(new Uint32Array(1))[0] / 4294967296;
const running = (st: RoomState) => !!st.game && st.game.phase !== 'end';
const statusOf = (st: RoomState): 'lobby' | 'game' => (running(st) ? 'game' : 'lobby');

/** Seat names: display names, with handles (then numbers) where two would be the same. */
function seatNames(ms: Member[]) {
  const n = (k: string) => ms.filter(m => nameKey(m.display) === k).length;
  const names = ms.map(m => (n(nameKey(m.display)) > 1 ? (m.handle || m.display) : m.display).slice(0, 18));
  return names.map((x, i) => (names.filter(y => nameKey(y) === nameKey(x)).length > 1 ? `${x.slice(0, 15)} ${i + 1}` : x));
}

export class Room extends DurableObject<Env> {
  private events: GameEvent[] = [];
  private queue: Promise<unknown> = Promise.resolve();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // keep-alives are answered by Cloudflare without waking the room (they'd count against the daily request limit)
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  /** One change at a time: awaiting D1 or another object lets the next message in, and it would start from the old
   *  state (two joins at once, one lost). Every entry point goes through here. */
  private serial<T>(fn: () => Promise<T>): Promise<T> {
    const p = this.queue.then(fn);
    this.queue = p.catch(() => {});
    return p;
  }

  private async load() {
    const st = await this.ctx.storage.get<RoomState>('room');
    if (st) { st.rev ??= 0; st.past ??= []; st.cut ??= 0; st.lastIn ??= {}; st.rec ??= null; st.blocks ??= {}; }  // rooms saved before these fields
    return st;
  }
  private save(st: RoomState) { return this.ctx.storage.put('room', st); }
  private sockets(uid?: string, except?: WebSocket) {
    return this.ctx.getWebSockets(uid).filter(w => w !== except && w.readyState === WebSocket.OPEN);
  }
  private online(uid: string, except?: WebSocket) { return this.sockets(uid, except).length > 0; }
  private out(ws: WebSocket, msg: RoomOut) { try { ws.send(JSON.stringify(msg)); } catch { /* closing */ } }
  private toUid(uid: string, msg: RoomOut) { for (const w of this.sockets(uid)) this.out(w, msg); }
  private uidOf(ws: WebSocket) { return this.ctx.getTags(ws)[0]; }
  /** When this socket last showed life: a message, or a "ping" Cloudflare answered for us. */
  private seen(ws: WebSocket) {
    const a = ws.deserializeAttachment() as { at: number } | null;
    return Math.max(a?.at ?? 0, this.ctx.getWebSocketAutoResponseTimestamp(ws)?.getTime() ?? 0);
  }

  /** The host's controls: the host while connected, otherwise the first connected player in join order. */
  private hostOf(st: RoomState, except?: WebSocket) {
    const here = st.members.filter(m => !m.left);
    if (here.some(m => m.uid === st.hostUid) && this.online(st.hostUid, except)) return st.hostUid;
    return here.find(m => this.online(m.uid, except))?.uid ?? st.hostUid;
  }

  private info(st: RoomState, except?: WebSocket): RoomInfo {
    const host = this.hostOf(st, except);
    return {
      code: st.code, rules: st.rules, counts: st.counts, mode: st.mode ?? 'classic', bodyguard: !!st.bodyguard, buzzMax: st.buzzMax, kick: st.kick ?? 'lobby', status: statusOf(st), deal: st.deal,
      gameId: st.gameId, valid: st.valid,
      members: st.members.filter(m => !m.left).map(m => ({
        uid: m.uid, cn: m.cn, display: m.display, handle: m.handle, avatar: m.avatar, online: this.online(m.uid, except), v: m.v ?? null,
        host: m.uid === host, ready: st.ready.includes(m.uid), muted: st.buzzMax > 0 && m.buzz >= st.buzzMax,
        seat: st.game && st.seats.includes(m.uid) ? st.seats.indexOf(m.uid) : null,
      })),
    };
  }

  /** Everyone gets the room and their own view; game events (minus the private night details) go to all. */
  private broadcast(st: RoomState, events: GameEvent[], except?: WebSocket) {
    const room = this.info(st, except), now = Date.now(), rev = st.rev;
    for (const ws of this.sockets(undefined, except)) {
      const uid = this.uidOf(ws), m = st.members.find(x => x.uid === uid);
      if (!m) continue;
      if (events.length) this.out(ws, { t: 'events', rev, events });
      this.out(ws, { t: 'room', rev, now, room, me: { uid, cn: m.cn, host: room.members.find(x => x.uid === uid)?.host ?? false } });
      const seat = st.seats.indexOf(uid);
      this.out(ws, { t: 'view', rev, view: st.game ? viewFor(st.game, seat >= 0 ? seat : 'table', now) : null });
    }
  }

  private who(st: RoomState): Who {
    const outs = new Set<number>();
    if (running(st)) st.members.forEach(m => { const s = st.seats.indexOf(m.uid); if (s >= 0 && !st.game!.alive[s]) outs.add(m.cn); });
    return { members: new Set(st.members.filter(m => !m.left).map(m => m.cn)), outs };
  }

  private async schedule(st: RoomState) {
    const at: number[] = [];
    if (st.game?.phase === 'night' && st.game.night.endsAt) at.push(st.game.night.endsAt);
    const open = this.sockets();
    if (!open.length) at.push(st.lastActive + IDLE_MS);
    else at.push(Math.min(...open.map(w => this.seen(w))) + STALE_MS);  // the next socket that could go stale
    if (at.length) await this.ctx.storage.setAlarm(Math.min(...at)); else await this.ctx.storage.deleteAlarm();
  }

  /** Runs an engine action; returns an error code or null. */
  private play(st: RoomState, a: Action) {
    st.rec ??= startRecord(st.game!);
    const r = step(st.rec, st.game!, a, { rng, now: Date.now() });
    if (!r.ok) return r.error;
    st.game = r.state; this.events.push(...r.events);
    return null;
  }

  /** After every change: save, record a finished game, update presence, the alarm, and tell everyone. */
  private async commit(st: RoomState, before: 'lobby' | 'game', except?: WebSocket) {
    if (st.game?.phase === 'end' && !st.gameId) await this.saveGame(st);
    // the night summary names who the Doctor protected and the Detective checked: only in the history at the end
    const events = this.events.filter(e => e.t !== 'night'); this.events = [];
    st.rev++;
    if (events.length) {
      st.past.push({ rev: st.rev, events });
      while (st.past.reduce((n, p) => n + p.events.length, 0) > KEEP_EVENTS) st.cut = st.past.shift()!.rev;
    }
    await this.save(st);
    const now = statusOf(st), size = st.members.filter(m => !m.left).length;
    if (now !== before) await this.env.DB.prepare('UPDATE rooms SET status = ? WHERE code = ? AND closed_at IS NULL').bind(now, st.code).run();
    if (now !== before || st.sizeSent !== size) {  // P3: friends see how many are in the room
      st.sizeSent = size;
      await this.save(st);
      await Promise.all(st.members.filter(m => !m.left).map(m => setRoom(this.env, m.uid, st.code, now, size)));
    }
    await this.schedule(st);
    this.broadcast(st, events, except);
  }

  private async saveGame(st: RoomState) {
    const g = st.game!, id = crypto.randomUUID(), db = this.env.DB;
    await db.batch([
      db.prepare('INSERT INTO games (id, host_id, winner, days, valid, rules, log, stats, played_at, record) VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?)')
        .bind(id, st.hostUid, g.winner, g.day, JSON.stringify(g.rules), JSON.stringify(g.log), JSON.stringify(g.stats), Date.now(),
          st.rec ? JSON.stringify(st.rec) : null),
      ...g.names.map((name, seat) => db.prepare('INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES (?, ?, (SELECT id FROM users WHERE id = ?), ?, ?, ?)')
        .bind(id, seat, st.seats[seat], name, g.roles[seat], g.alive[seat] ? 1 : 0)),
    ]);
    st.gameId = id; st.valid = true;
    await refreshTitles(this.env, { push: fcmSender, now: () => Date.now() });
  }

  private async close(st: RoomState, why: 'closed') {
    for (const ws of this.sockets()) { this.out(ws, { t: 'bye', why }); try { ws.close(4000, why); } catch { /* gone */ } }
    await this.env.DB.prepare('UPDATE rooms SET closed_at = ? WHERE code = ? AND closed_at IS NULL').bind(Date.now(), st.code).run();
    await Promise.all(st.members.map(m => setRoom(this.env, m.uid, null, '')));
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }

  /** Someone leaves for good (left, kicked). A leaver stays as `left` (their seat in a game, and their number: back in
   *  the room they get the same one, so their earlier chat is still theirs: [QA] S13 emulator); a kicked one is gone. */
  private async drop(st: RoomState, uid: string, why: 'left' | 'kicked') {
    const m = st.members.find(x => x.uid === uid); if (!m) return;
    if (why === 'left') m.left = true;
    else st.members = st.members.filter(x => x.uid !== uid);
    st.ready = st.ready.filter(x => x !== uid);
    for (const w of this.sockets(uid)) { this.out(w, { t: 'bye', why }); try { w.close(4000, why); } catch { /* gone */ } }
    await setRoom(this.env, uid, null, '');
    if (uid === st.hostUid) st.hostUid = st.members.find(x => !x.left)?.uid ?? st.hostUid;
  }

  // ---------------------------------------------------------------- connect

  fetch(req: Request) { return this.serial(() => (req.headers.get('x-op') ? this.op(req) : this.join(req))); }

  /** Internal calls from the Worker: reload the blocks (someone blocked or unblocked), or fetch a message for a report. */
  private async op(req: Request) {
    const st = await this.load();
    if (!st) return Response.json(null, { status: 404 });
    if (req.headers.get('x-op') === 'blocks') { await this.loadBlocks(st); await this.save(st); return new Response(null, { status: 204 }); }
    if (req.headers.get('x-op') === 'unkick') { // [N5] the host invited a kicked player back in
      st.kicked = st.kicked.filter(u => u !== req.headers.get('x-uid')); await this.save(st); return new Response(null, { status: 204 });
    }
    const id = Number(req.headers.get('x-id')), reporter = st.members.find(m => m.uid === req.headers.get('x-uid'));
    const chat = (await this.ctx.storage.get<ChatState>('chat')) ?? newChat(), msg = chat.msgs.find(m => m.id === id);
    if (!msg || !reporter || !canSee(msg, reporter.cn, this.who(st))) return Response.json(null, { status: 404 });
    return Response.json({ text: msg.text, at: msg.at, fromUid: st.members.find(m => m.cn === msg.from)?.uid ?? null });
  }

  /** Who blocks whom among the members (from D1; refreshed on every join and when someone blocks). */
  private async loadBlocks(st: RoomState) {
    const ids = st.members.map(m => m.uid);
    st.blocks = {};
    if (ids.length < 2) return;
    const q = ids.map(() => '?').join(',');
    const { results } = await this.env.DB.prepare(`SELECT blocker_id, blocked_id FROM blocks WHERE blocker_id IN (${q}) AND blocked_id IN (${q})`)
      .bind(...ids, ...ids).all<{ blocker_id: string; blocked_id: string }>();
    for (const r of results) (st.blocks[r.blocker_id] ??= []).push(r.blocked_id);
  }
  /** Does the member `viewer` block the sender (by chat number)? Then that message isn't delivered to them. */
  private hides(st: RoomState, viewer: string, fromCn: number) {
    const from = st.members.find(m => m.cn === fromCn)?.uid;
    return !!from && !!st.blocks[viewer]?.includes(from);
  }
  private async join(req: Request) {
    const user = JSON.parse(req.headers.get('x-user')!) as UserRow, code = req.headers.get('x-code')!;
    const [client, server] = Object.values(new WebSocketPair());
    const refuse = (error: string) => {
      server.accept(); server.send(JSON.stringify({ t: 'err', error } satisfies RoomOut)); server.close(4004, error);
      return new Response(null, { status: 101, webSocket: client, headers: PROTO });
    };
    let st = await this.load();
    if (!st) {
      const row = await this.env.DB.prepare('SELECT host_id FROM rooms WHERE code = ? AND closed_at IS NULL').bind(code).first<{ host_id: string }>();
      if (!row) return refuse('no_room');
      st = { code, hostUid: row.host_id, members: [], kicked: [], nextCn: 1, rules: { ...DEFAULT_RULES }, counts: { mafia: 1, doctor: 1, detective: 0 },
        buzzMax: 3, deal: 0, game: null, seats: [], ready: [], gameId: null, valid: null, lastActive: Date.now(),
        rev: 0, past: [], cut: 0, lastIn: {}, rec: null, blocks: {} };
    }
    if (st.kicked.includes(user.id)) return refuse('kicked');
    const before = statusOf(st), me = { display: user.display, handle: user.handle, avatar: avatarOf(user) };
    let m = st.members.find(x => x.uid === user.id);
    const v = Number(new URL(req.url).searchParams.get('v'));  // the phone's app build, for "old version" in the lobby
    if (m) { delete m.left; Object.assign(m, me); }
    else {
      if (running(st)) return refuse('started');  // late joiners wait for the next deal; seat holders rejoin above
      if (st.members.filter(x => !x.left).length >= MAX_MEMBERS) return refuse('room_full');
      m = { uid: user.id, cn: st.nextCn++, ...me, buzz: 0 };
      st.members.push(m);
    }
    if (Number.isInteger(v) && v > 0) m.v = v;
    st.lastActive = Date.now();
    this.ctx.acceptWebSocket(server, [user.id]);
    server.serializeAttachment({ at: Date.now() });
    // a phone coming back: the events it missed since the last rev it saw (or "missed" if they're gone)
    const since = Number(new URL(req.url).searchParams.get('rev'));
    if (Number.isInteger(since) && since > 0 && since <= st.rev) {
      if (since < st.cut) this.out(server, { t: 'missed' });
      else for (const p of st.past) if (p.rev > since) this.out(server, { t: 'events', rev: p.rev, events: p.events });
    }
    await this.loadBlocks(st);
    await setRoom(this.env, user.id, st.code, statusOf(st), st.members.filter(x => !x.left).length);
    await this.commit(st, before);
    const chat = (await this.ctx.storage.get<ChatState>('chat')) ?? newChat(), w = this.who(st);
    this.out(server, { t: 'chatAll', msgs: chat.msgs.filter(x => canSee(x, m!.cn, w) && !this.hides(st, user.id, x.from)) });
    return new Response(null, { status: 101, webSocket: client, headers: PROTO });
  }

  webSocketClose(ws: WebSocket, code: number) {
    return this.serial(async () => {
      try { ws.close(code === 1005 ? 1000 : code, 'bye'); } catch { /* already closed */ }
      const st = await this.load(); if (!st) return;
      st.lastActive = Date.now();
      await this.commit(st, statusOf(st), ws);  // online dots and the host's controls may move
    });
  }
  async webSocketError(ws: WebSocket) { await this.webSocketClose(ws, 1011); }

  /** The night timer ran out (unfinished turns are skipped), a phone went silent, or the room sat empty for 12 hours. */
  alarm() { return this.serial(() => this.tick()); }
  private async tick() {
    const st = await this.load(); if (!st) return;
    const before = statusOf(st), now = Date.now();
    let changed = false;
    if (st.game?.phase === 'night' && st.game.night.endsAt && now >= st.game.night.endsAt) changed = !this.play(st, { t: 'skipPending' });
    for (const w of this.sockets()) {
      if (now - this.seen(w) < STALE_MS) continue;
      try { w.close(4001, 'stale'); } catch { /* gone */ }  // if the phone is still there, it reconnects
      changed = true;
    }
    if (!this.sockets().length && now >= st.lastActive + IDLE_MS) return this.close(st, 'closed');
    if (changed) await this.commit(st, before); else await this.schedule(st);
  }

  // ---------------------------------------------------------------- messages

  webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer) {
    if (raw === 'ping') { ws.send('pong'); return; }  // normally answered by Cloudflare before it gets here
    ws.serializeAttachment({ at: Date.now() });
    return this.serial(() => this.onMessage(ws, raw));
  }
  private async onMessage(ws: WebSocket, raw: string | ArrayBuffer) {
    const uid = this.uidOf(ws);
    let parsed; try { parsed = RoomIn.safeParse(JSON.parse(String(raw))); } catch { parsed = null; }
    if (!parsed?.success) { this.out(ws, { t: 'err', error: 'bad_request' }); return; }
    const inp = parsed.data, st = await this.load();
    if (!st) { try { ws.close(4000, 'closed'); } catch { /* gone */ } return; }
    const m = st.members.find(x => x.uid === uid && !x.left);
    if (!m) { this.out(ws, { t: 'err', error: 'not_member' }); return; }
    const err = (error: string) => { this.out(ws, { t: 'err', error, ref: inp.t }); };
    const isHost = this.hostOf(st) === uid, seat = st.seats.indexOf(uid), before = statusOf(st), g = st.game;
    st.lastActive = Date.now();

    if (inp.t === 'chat' || inp.t === 'react' || inp.t === 'edit') return this.chat(st, ws, m.cn, inp);
    // a phone resending its night choice, vote or "ready" after a drop: already applied, nothing to do
    const key = inp.t === 'night' || inp.t === 'vote' || inp.t === 'ready' ? JSON.stringify(inp) : null;
    if (key && st.lastIn[uid] === key) return;

    const hostOnly = ['setup', 'deal', 'start', 'startDay', 'timer', 'startVote', 'nextNight', 'continue', 'kick', 'unmute', 'ping', 'mark', 'lobby', 'close'];
    if (hostOnly.includes(inp.t) && !isHost) return err('forbidden');
    let e: string | null = null;
    switch (inp.t) {
      case 'setup':
        if (running(st)) return err('started');
        st.rules = { ...inp.rules, tieSkip: true }; st.counts = { mafia: inp.counts.mafia, doctor: 1, detective: inp.counts.detective }; st.buzzMax = inp.buzzMax; if (inp.kick) st.kick = inp.kick;
        st.mode = inp.mode ?? 'classic'; st.bodyguard = inp.bodyguard ?? false;
        break;
      case 'deal': {  // also Play again after the end: the same room, new roles
        if (running(st)) return err('started');
        const players = st.members.filter(x => !x.left), mode = st.mode ?? 'classic';
        // his rulings (S17 Q4, S18): every seat must be on 1.1.0, Classic too (an older app doesn't know the new rules)
        if (players.some(x => !(x.v && x.v >= MODES_BUILD))) return err('old_app');
        const r = createGame({ names: seatNames(players), counts: st.counts, rules: st.rules, mode, bodyguard: !!st.bodyguard }, rng, st.deal + 1);
        if (!r.ok) return err(r.error);
        st.deal++; st.game = r.state; st.seats = players.map(x => x.uid); st.ready = []; st.gameId = null; st.valid = null;
        st.rec = startRecord(r.state); st.lastIn = {};
        st.members = st.members.filter(x => !x.left);
        break;
      }
      case 'start': if (g?.phase !== 'deal') return err('phase'); e = this.play(st, { t: 'begin' }); break;
      case 'ready':
        if (g?.phase !== 'deal' || inp.deal !== st.deal || seat < 0) return err('phase');
        if (!st.ready.includes(uid)) st.ready.push(uid);
        if (st.seats.every(u => st.ready.includes(u))) e = this.play(st, { t: 'begin' });
        break;
      case 'night': if (!g || seat < 0) return err('phase'); e = this.play(st, { t: 'night', seat, choice: inp.choice, day: inp.day }); break;
      case 'vote': if (!g || seat < 0) return err('phase'); e = this.play(st, { t: 'vote', seat, choice: inp.choice, id: inp.id }); break;
      case 'startDay': if (!g) return err('phase'); e = this.play(st, { t: 'startDay' }); break;
      case 'timer':
        if (!g) return err('phase');
        e = this.play(st, inp.op === 'add' ? { t: 'timer', op: 'add', sec: inp.sec ?? 60 } : { t: 'timer', op: inp.op }); break;
      case 'startVote': if (!g) return err('phase'); e = this.play(st, { t: 'startVote', open: inp.open }); break;
      case 'nextNight': if (!g) return err('phase'); e = this.play(st, { t: 'nextNight' }); break;
      case 'continue': {  // skip the turns of players who are offline
        if (!g || (g.phase !== 'night' && g.phase !== 'vote')) return err('phase');
        const pending = g.alive.map((a, i) => i).filter(i => g.alive[i] && (g.phase === 'night' ? !g.night.done[i] : g.vote!.votes[i] === undefined));
        const seats = pending.filter(i => !this.online(st.seats[i]));
        if (!seats.length) return err('nothing');
        e = this.play(st, { t: 'skipPending', seats });
        break;
      }
      case 'kick': {
        if (inp.uid === uid || !st.members.some(x => x.uid === inp.uid)) return err('not_member');
        if (running(st) && (st.kick ?? 'lobby') === 'lobby') return err('lobby_only');  // the host's Settings: kicks in the lobby only
        const s = st.seats.indexOf(inp.uid);
        if (running(st) && s >= 0 && g!.alive[s] && g!.phase !== 'deal') e = this.play(st, { t: 'remove', seat: s });
        if (e) return err(e);
        st.kicked.push(inp.uid);
        await this.drop(st, inp.uid, 'kicked');
        if (st.hostUid === inp.uid) st.hostUid = uid;
        break;
      }
      case 'unmute': { const t = st.members.find(x => x.uid === inp.uid); if (t) t.buzz = 0; break; }
      case 'ping': for (const w of this.sockets()) if (w !== ws) this.out(w, { t: 'ping' }); return;
      case 'buzz': {
        m.buzz++;
        if (!st.buzzMax || m.buzz <= st.buzzMax) this.toUid(this.hostOf(st), { t: 'buzz', from: uid });
        break;
      }
      case 'mark':
        if (g?.phase !== 'end' || !st.gameId) return err('phase');
        await this.env.DB.prepare('UPDATE games SET valid = ? WHERE id = ?').bind(inp.valid ? 1 : 0, st.gameId).run();
        st.valid = inp.valid;
        await this.commit(st, before);  // [1.0.1 hotfix] the host sees the mark at once; the titles are worked out after
        await refreshTitles(this.env, { push: fcmSender, now: () => Date.now() });
        return;
      case 'lobby':
        if (g?.phase !== 'end') return err('phase');
        st.game = null; st.seats = []; st.ready = []; st.gameId = null; st.valid = null; st.rec = null; st.lastIn = {};
        break;
      case 'close': return this.close(st, 'closed');
      case 'leave':
        await this.drop(st, uid, 'left');
        if (!st.members.some(x => !x.left)) return this.close(st, 'closed');
        break;
    }
    if (e) return err(e);
    if (key) st.lastIn[uid] = key;
    await this.commit(st, before);
  }

  private async chat(st: RoomState, ws: WebSocket, me: number, inp: Extract<RoomIn, { t: 'chat' | 'react' | 'edit' }>) {
    const chat = (await this.ctx.storage.get<ChatState>('chat')) ?? newChat(), w = this.who(st), now = Date.now();
    let r: ChatResult;
    if (inp.t === 'chat') r = send(chat, w, me, inp, now);
    else if (inp.t === 'react') r = react(chat, w, me, inp.id, inp.rx, now);
    else r = edit(chat, me, inp.id, inp.text, now);
    if (!r.ok) { this.out(ws, { t: 'err', error: r.error, ref: inp.t === 'chat' ? inp.cid : inp.t }); return; }
    await this.ctx.storage.put('chat', chat);
    await this.save(st);
    const msg: ChatMsg = r.msg;
    for (const s of this.sockets()) {
      const m = st.members.find(x => x.uid === this.uidOf(s) && !x.left);
      if (!m || !canSee(msg, m.cn, w) || this.hides(st, m.uid, msg.from)) continue;  // not across a block
      this.out(s, { t: 'chat', msg, ...(s === ws && inp.t === 'chat' ? { cid: inp.cid } : {}) });
      if (r.mentions.includes(m.cn)) this.out(s, { t: 'mention', id: msg.id, from: me });
    }
  }
}
