// One Durable Object per online room code. It runs the lobby and the game with the shared engine (the server is the
// judge), sends each phone only its own view, keeps the room chat, and deletes everything when the room ends.
import { DurableObject } from 'cloudflare:workers';
import { apply, createGame, DEFAULT_RULES, nameKey, viewFor, type Action, type Counts, type GameEvent, type GameState, type Rules } from '@mafia/engine';
import { RoomIn, SUBPROTOCOL, type Avatar, type ChatMsg, type RoomInfo, type RoomOut } from '@mafia/protocol';
import { canSee, edit, newChat, react, send, type ChatResult, type ChatState, type Who } from './chat.ts';
import { setRoom } from './hub.ts';
import { avatarOf, type Env, type UserRow } from './lib.ts';

interface Member { uid: string; cn: number; display: string; handle: string | null; avatar: Avatar; buzz: number; left?: true }
interface RoomState {
  code: string; hostUid: string; members: Member[]; kicked: string[]; nextCn: number;
  rules: Rules; counts: Counts; buzzMax: number;
  deal: number; game: GameState | null; seats: string[]; ready: string[]; gameId: string | null; valid: boolean | null;
  lastActive: number;
}

export const IDLE_MS = 12 * 3600e3, MAX_MEMBERS = 20;
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

  private load() { return this.ctx.storage.get<RoomState>('room'); }
  private save(st: RoomState) { return this.ctx.storage.put('room', st); }
  private sockets(uid?: string, except?: WebSocket) {
    return this.ctx.getWebSockets(uid).filter(w => w !== except && w.readyState === WebSocket.OPEN);
  }
  private online(uid: string, except?: WebSocket) { return this.sockets(uid, except).length > 0; }
  private out(ws: WebSocket, msg: RoomOut) { try { ws.send(JSON.stringify(msg)); } catch { /* closing */ } }
  private toUid(uid: string, msg: RoomOut) { for (const w of this.sockets(uid)) this.out(w, msg); }
  private uidOf(ws: WebSocket) { return this.ctx.getTags(ws)[0]; }

  /** The host's controls: the host while connected, otherwise the first connected player in join order. */
  private hostOf(st: RoomState, except?: WebSocket) {
    const here = st.members.filter(m => !m.left);
    if (here.some(m => m.uid === st.hostUid) && this.online(st.hostUid, except)) return st.hostUid;
    return here.find(m => this.online(m.uid, except))?.uid ?? st.hostUid;
  }

  private info(st: RoomState, except?: WebSocket): RoomInfo {
    const host = this.hostOf(st, except);
    return {
      code: st.code, rules: st.rules, counts: st.counts, buzzMax: st.buzzMax, status: statusOf(st), deal: st.deal,
      gameId: st.gameId, valid: st.valid,
      members: st.members.filter(m => !m.left).map(m => ({
        uid: m.uid, cn: m.cn, display: m.display, handle: m.handle, avatar: m.avatar, online: this.online(m.uid, except),
        host: m.uid === host, ready: st.ready.includes(m.uid), muted: st.buzzMax > 0 && m.buzz >= st.buzzMax,
        seat: st.game && st.seats.includes(m.uid) ? st.seats.indexOf(m.uid) : null,
      })),
    };
  }

  /** Everyone gets the room and their own view; game events (minus the private night details) go to all. */
  private broadcast(st: RoomState, except?: WebSocket) {
    const room = this.info(st, except), now = Date.now();
    // the night summary names who the Doctor protected and the Detective checked: only in the history at the end
    const events = this.events.filter(e => e.t !== 'night'); this.events = [];
    for (const ws of this.sockets(undefined, except)) {
      const uid = this.uidOf(ws), m = st.members.find(x => x.uid === uid);
      if (!m) continue;
      if (events.length) this.out(ws, { t: 'events', events });
      this.out(ws, { t: 'room', room, me: { uid, cn: m.cn, host: room.members.find(x => x.uid === uid)?.host ?? false } });
      const seat = st.seats.indexOf(uid);
      this.out(ws, { t: 'view', view: st.game ? viewFor(st.game, seat >= 0 ? seat : 'table', now) : null });
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
    if (!this.sockets().length) at.push(st.lastActive + IDLE_MS);
    if (at.length) await this.ctx.storage.setAlarm(Math.min(...at)); else await this.ctx.storage.deleteAlarm();
  }

  /** Runs an engine action; returns an error code or null. */
  private play(st: RoomState, a: Action) {
    const r = apply(st.game!, a, { rng, now: Date.now() });
    if (!r.ok) return r.error;
    st.game = r.state; this.events.push(...r.events);
    return null;
  }

  /** After every change: save, record a finished game, update presence, the alarm, and tell everyone. */
  private async commit(st: RoomState, before: 'lobby' | 'game', except?: WebSocket) {
    if (st.game?.phase === 'end' && !st.gameId) await this.saveGame(st);
    await this.save(st);
    const now = statusOf(st);
    if (now !== before) {
      await this.env.DB.prepare('UPDATE rooms SET status = ? WHERE code = ? AND closed_at IS NULL').bind(now, st.code).run();
      await Promise.all(st.members.filter(m => !m.left).map(m => setRoom(this.env, m.uid, st.code, now)));
    }
    await this.schedule(st);
    this.broadcast(st, except);
  }

  private async saveGame(st: RoomState) {
    const g = st.game!, id = crypto.randomUUID(), db = this.env.DB;
    await db.batch([
      db.prepare('INSERT INTO games (id, host_id, winner, days, valid, rules, log, stats, played_at) VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?)')
        .bind(id, st.hostUid, g.winner, g.day, JSON.stringify(g.rules), JSON.stringify(g.log), JSON.stringify(g.stats), Date.now()),
      ...g.names.map((name, seat) => db.prepare('INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES (?, ?, (SELECT id FROM users WHERE id = ?), ?, ?, ?)')
        .bind(id, seat, st.seats[seat], name, g.roles[seat], g.alive[seat] ? 1 : 0)),
    ]);
    st.gameId = id; st.valid = true;
  }

  private async close(st: RoomState, why: 'closed') {
    for (const ws of this.sockets()) { this.out(ws, { t: 'bye', why }); try { ws.close(4000, why); } catch { /* gone */ } }
    await this.env.DB.prepare('UPDATE rooms SET closed_at = ? WHERE code = ? AND closed_at IS NULL').bind(Date.now(), st.code).run();
    await Promise.all(st.members.map(m => setRoom(this.env, m.uid, null, '')));
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }

  /** Someone leaves for good (left, kicked): in a running game their seat stays (a leaver may come back). */
  private async drop(st: RoomState, uid: string, why: 'left' | 'kicked') {
    const m = st.members.find(x => x.uid === uid); if (!m) return;
    if (why === 'left' && running(st) && st.seats.includes(uid)) m.left = true;
    else st.members = st.members.filter(x => x.uid !== uid);
    st.ready = st.ready.filter(x => x !== uid);
    for (const w of this.sockets(uid)) { this.out(w, { t: 'bye', why }); try { w.close(4000, why); } catch { /* gone */ } }
    await setRoom(this.env, uid, null, '');
    if (uid === st.hostUid) st.hostUid = st.members.find(x => !x.left)?.uid ?? st.hostUid;
  }

  // ---------------------------------------------------------------- connect

  async fetch(req: Request) {
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
        buzzMax: 3, deal: 0, game: null, seats: [], ready: [], gameId: null, valid: null, lastActive: Date.now() };
    }
    if (st.kicked.includes(user.id)) return refuse('kicked');
    const before = statusOf(st), me = { display: user.display, handle: user.handle, avatar: avatarOf(user) };
    let m = st.members.find(x => x.uid === user.id);
    if (m) { delete m.left; Object.assign(m, me); }
    else {
      if (running(st)) return refuse('started');  // late joiners wait for the next deal; seat holders rejoin above
      if (st.members.length >= MAX_MEMBERS) return refuse('room_full');
      m = { uid: user.id, cn: st.nextCn++, ...me, buzz: 0 };
      st.members.push(m);
    }
    st.lastActive = Date.now();
    this.ctx.acceptWebSocket(server, [user.id]);
    await setRoom(this.env, user.id, st.code, statusOf(st));
    await this.commit(st, before);
    const chat = (await this.ctx.storage.get<ChatState>('chat')) ?? newChat(), w = this.who(st);
    this.out(server, { t: 'chatAll', msgs: chat.msgs.filter(x => canSee(x, m!.cn, w)) });
    return new Response(null, { status: 101, webSocket: client, headers: PROTO });
  }

  async webSocketClose(ws: WebSocket, code: number) {
    try { ws.close(code === 1005 ? 1000 : code, 'bye'); } catch { /* already closed */ }
    const st = await this.load(); if (!st) return;
    st.lastActive = Date.now();
    await this.save(st);
    await this.schedule(st);
    this.broadcast(st, ws);  // online dots and the host's controls may move
  }
  async webSocketError(ws: WebSocket) { await this.webSocketClose(ws, 1011); }

  /** The night timer ran out (unfinished turns are skipped), or the room sat empty for 12 hours. */
  async alarm() {
    const st = await this.load(); if (!st) return;
    const before = statusOf(st);
    if (st.game?.phase === 'night' && st.game.night.endsAt) this.play(st, { t: 'skipPending' });
    if (!this.sockets().length && Date.now() >= st.lastActive + IDLE_MS) return this.close(st, 'closed');
    await this.commit(st, before);
  }

  // ---------------------------------------------------------------- messages

  async webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer) {
    if (raw === 'ping') { ws.send('pong'); return; }
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

    const hostOnly = ['setup', 'deal', 'start', 'startDay', 'timer', 'startVote', 'nextNight', 'continue', 'kick', 'unmute', 'ping', 'mark', 'lobby', 'close'];
    if (hostOnly.includes(inp.t) && !isHost) return err('forbidden');
    let e: string | null = null;
    switch (inp.t) {
      case 'setup':
        if (running(st)) return err('started');
        st.rules = inp.rules; st.counts = { mafia: inp.counts.mafia, doctor: 1, detective: inp.counts.detective }; st.buzzMax = inp.buzzMax;
        break;
      case 'deal': {  // also Play again after the end: the same room, new roles
        if (running(st)) return err('started');
        const players = st.members.filter(x => !x.left);
        const r = createGame({ names: seatNames(players), counts: st.counts, rules: st.rules }, rng, st.deal + 1);
        if (!r.ok) return err(r.error);
        st.deal++; st.game = r.state; st.seats = players.map(x => x.uid); st.ready = []; st.gameId = null; st.valid = null;
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
        break;
      case 'lobby':
        if (g?.phase !== 'end') return err('phase');
        st.game = null; st.seats = []; st.ready = []; st.gameId = null; st.valid = null;
        break;
      case 'close': return this.close(st, 'closed');
      case 'leave':
        await this.drop(st, uid, 'left');
        if (!st.members.some(x => !x.left)) return this.close(st, 'closed');
        break;
    }
    if (e) return err(e);
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
      if (!m || !canSee(msg, m.cn, w)) continue;
      this.out(s, { t: 'chat', msg, ...(s === ws && inp.t === 'chat' ? { cid: inp.cid } : {}) });
      if (r.mentions.includes(m.cn)) this.out(s, { t: 'mention', id: msg.id, from: me });
    }
  }
}
