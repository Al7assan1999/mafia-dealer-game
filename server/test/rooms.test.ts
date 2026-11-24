import { env, runDurableObjectAlarm, runInDurableObject } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_RULES, replay } from '@mafia/engine';
import { STALE_MS } from '../src/room.ts';
import { setup } from './helpers.ts';
import { account, api, befriend, connect, DB, roomStub, sleep, type Sock } from './live.ts';

beforeEach(async () => { await setup(); });

const rules = (o = {}) => ({ ...DEFAULT_RULES, ...o });
/** Changes the room's saved state (to make time pass without waiting). */
async function shift(stub: ReturnType<typeof roomStub>, f: (st: any) => void) {
  await runInDurableObject(stub, async (_o, state) => { const st = await state.storage.get<any>('room'); f(st); await state.storage.put('room', st); });
}
/** n players in a new room, connected in join order (players[0] is the host). */
async function table(n: number) {
  const accts = await Promise.all(Array.from({ length: n }, (_, i) => account('P' + (i + 1) + 'x' + Math.random().toString(36).slice(2, 6))));
  const { json } = await api('POST', '/v1/rooms', accts[0].token);
  const players: Sock[] = [];
  for (const a of accts) { players.push(await connect(`/v1/rooms/${json.code}/ws`, a.token)); await players.at(-1)!.until(() => players.at(-1)!.room, 'room'); }
  await players[0].until(() => players[0].room?.members.length === n, n + ' members');
  return { code: json.code as string, players, accts };
}
async function deal(t: Awaited<ReturnType<typeof table>>, setupMsg?: object) {
  const [host] = t.players;
  if (setupMsg) host.send({ t: 'setup', buzzMax: 3, ...setupMsg });
  host.send({ t: 'deal' });
  await Promise.all(t.players.map(p => p.until(() => p.view?.phase === 'deal', 'deal')));
  for (const p of t.players) p.send({ t: 'ready', deal: p.room.deal });
  await Promise.all(t.players.map(p => p.until(() => p.view?.phase === 'night', 'night')));
}
const phaseOf = (p: Sock) => p.view?.phase;
async function playNight(players: Sock[]) {
  const day = players[0].view.day;
  for (const p of players) {
    const v = p.view; if (v.ph !== 'night') continue;
    const opts = v.night.opts.filter((o: any) => !o.disabled && !o.teammate);
    p.send({ t: 'night', choice: v.night.key === 'none' ? null : opts[0].seat, day });
  }
  await players[0].until(() => phaseOf(players[0]) !== 'night', 'dawn');
}
async function playVote(players: Sock[], roleOf: string[]) {
  const id = players[0].view.voteId;
  for (const p of players) {
    const v = p.view; if (v.ph !== 'vote') continue;
    const target = v.voteOpts.find((o: any) => !o.disabled && roleOf[o.seat] === 'mafia');
    p.send({ t: 'vote', choice: target ? target.seat : 'none', id });
  }
  await players[0].until(() => phaseOf(players[0]) !== 'vote', 'verdict');
}

describe('a full online game', () => {
  it('six phones play to the end; each sees only its own role; the game is saved', async () => {
    const t = await table(6), [host] = t.players;
    await deal(t, { rules: rules(), counts: { mafia: 2, detective: 1 } });
    const roleOf: string[] = [];
    for (const p of t.players) { roleOf[p.view.seat] = p.view.role; expect(p.view.roles).toBeNull(); }
    expect([...roleOf].sort()).toEqual(['citizen', 'citizen', 'detective', 'doctor', 'mafia', 'mafia']);
    for (const p of t.players) expect(p.view.mates.length).toBe(p.view.role === 'mafia' ? 1 : 0);
    for (let step = 0; step < 40 && phaseOf(host) !== 'end'; step++) {
      const ph = phaseOf(host);
      if (ph === 'night') await playNight(t.players);
      else if (ph === 'morning') { host.send({ t: 'startDay' }); await host.until(() => phaseOf(host) !== 'morning'); }
      else if (ph === 'day') { host.send({ t: 'startVote', open: false }); await host.until(() => phaseOf(host) === 'vote'); }
      else if (ph === 'vote') await playVote(t.players, roleOf);
      else if (ph === 'verdict') { host.send({ t: 'nextNight' }); await host.until(() => phaseOf(host) === 'night' || phaseOf(host) === 'end'); }
    }
    expect(phaseOf(host)).toBe('end');
    await Promise.all(t.players.map(p => p.until(() => p.view?.roles, 'roles at the end')));
    expect(t.players[3].view.roles).toEqual(roleOf);
    // narration events reach every phone; the private night summary never does
    for (const p of t.players) {
      const evs = p.msgs.filter(m => m.t === 'events').flatMap(m => m.events);
      expect(evs.some((e: any) => e.t === 'phase' && e.phase === 'night')).toBe(true);
      expect(evs.some((e: any) => e.t === 'night')).toBe(false);
      expect(evs.some((e: any) => e.t === 'win')).toBe(true);
    }
    await host.until(() => host.room.gameId, 'game id');
    const mine = await api('GET', '/v1/games', t.accts[2].token);
    expect(mine.json.games).toHaveLength(1);
    expect(mine.json.games[0]).toMatchObject({ winner: host.view.winner, players: 6, valid: true, role: roleOf[t.players[2].view.seat] });
    const full = await api('GET', '/v1/games/' + host.room.gameId, t.accts[2].token);
    expect(full.json.players).toHaveLength(6);
    expect(full.json.log.some((e: any) => e.t === 'night')).toBe(true);  // the full history, after the end
    host.send({ t: 'mark', valid: false });
    await host.until(() => host.room.valid === false);
    expect((await api('PATCH', '/v1/games/' + host.room.gameId, t.accts[2].token, { valid: true })).status).toBe(404);  // only the host
    expect((await api('GET', '/v1/games/' + host.room.gameId, (await account('stranger')).token)).status).toBe(404);
    // Play again: new roles for the same room
    host.send({ t: 'deal' });
    await host.until(() => host.room.deal === 2 && phaseOf(host) === 'deal', 'second deal');
  });
});

describe('the room', () => {
  it('only the host deals; the room needs 4 players; late joiners wait, seat holders come back', async () => {
    const t = await table(4), [host, b] = t.players;
    b.send({ t: 'deal' });
    await b.until(() => b.got(m => m.t === 'err' && m.error === 'forbidden'), 'forbidden');
    await deal(t);
    const late = await connect(`/v1/rooms/${t.code}/ws`, (await account('late')).token);
    await late.until(() => late.got(m => m.t === 'err' && m.error === 'started'), 'started');
    const seat = b.view.seat, role = b.view.role;
    b.ws.close();
    await host.until(() => host.room.members.find((m: any) => m.uid === t.accts[1].id)?.online === false, 'b offline');
    const again = await connect(`/v1/rooms/${t.code}/ws`, t.accts[1].token);
    await again.until(() => again.view?.seat === seat);
    expect(again.view.role).toBe(role);
    const small = await table(3);
    small.players[0].send({ t: 'deal' });
    await small.players[0].until(() => small.players[0].got(m => m.t === 'err' && m.error === 'tooFew'), 'tooFew');
  });

  it('host controls pass to the first player who joined, and come back', async () => {
    const t = await table(4), [a, b, c] = t.players;
    expect(b.me.host).toBe(false);
    a.ws.close();
    await b.until(() => b.me.host === true, 'b is host');
    expect(c.me.host).toBe(false);
    const back = await connect(`/v1/rooms/${t.code}/ws`, t.accts[0].token);
    await back.until(() => back.me?.host === true, 'a host again');
    await b.until(() => b.me.host === false);
    back.send({ t: 'leave' });  // leaving for good hands it over for good
    await b.until(() => b.me.host === true && b.room.members.length === 3, 'b host for good');
    expect((await DB().prepare('SELECT room_code FROM users WHERE id = ?').bind(t.accts[0].id).first<any>()).room_code).toBeNull();
  });

  it('[QA S13] left in the lobby and back: the same number, so the earlier chat is still theirs; a leaver frees the place', async () => {
    const t = await table(3), [a, b] = t.players, cn = b.me.cn;
    b.send({ t: 'chat', to: -1, text: 'before', cid: 'c1' });
    await a.until(() => a.got(m => m.t === 'chat' && m.msg.text === 'before'), 'chat');
    b.send({ t: 'leave' });
    await a.until(() => a.room.members.length === 2, 'b gone from the list');
    const back = await connect(`/v1/rooms/${t.code}/ws`, t.accts[1].token);
    await back.until(() => back.me, 'back in');
    expect(back.me.cn).toBe(cn);
    await back.until(() => back.got(m => m.t === 'chatAll'), 'history');
    expect(back.got(m => m.t === 'chatAll').msgs.find((m: any) => m.text === 'before').from).toBe(cn);
    await a.until(() => a.room.members.length === 3, 'listed again');
  });

  it("kicks follow the host Settings: lobby only refuses one mid-game; any time eliminates the player, who cannot come back", async () => {
    const t = await table(5), [host] = t.players;
    await deal(t);
    host.send({ t: 'kick', uid: t.accts[4].id });  // the old app's default: lobby only
    await host.until(() => host.got(m => m.t === 'err' && m.error === 'lobby_only'), 'refused');
    expect(host.room.kick).toBe('lobby');

    const u = await table(5), [h, , , , e] = u.players;
    await deal(u, { rules: rules(), counts: { mafia: 1, detective: 0 }, kick: 'any' });
    expect(h.room.kick).toBe('any');
    const seat = e.view.seat;
    h.send({ t: 'kick', uid: u.accts[4].id });
    await e.until(() => e.got(m => m.t === 'bye' && m.why === 'kicked'), 'bye');
    await h.until(() => h.view.roster[seat].alive === false || h.view.phase === 'end', 'out');
    const again = await connect(`/v1/rooms/${u.code}/ws`, u.accts[4].token);
    await again.until(() => again.got(m => m.t === 'err' && m.error === 'kicked'), 'kicked');
  });

  it('a kicked player stays out, until the host invites them back (Sprint 10 N5)', async () => {
    const t = await table(4), [host, , , d] = t.players;
    host.send({ t: 'kick', uid: t.accts[3].id });  // in the lobby: allowed
    await d.until(() => d.got(m => m.t === 'bye' && m.why === 'kicked'), 'bye');
    let again = await connect(`/v1/rooms/${t.code}/ws`, t.accts[3].token);
    await again.until(() => again.got(m => m.t === 'err' && m.error === 'kicked'), 'still kicked');
    await befriend(t.accts[0], t.accts[3]);
    await DB().prepare('UPDATE users SET room_code = ? WHERE id = ?').bind(t.code, t.accts[0].id).run();  // the host is in this room
    expect((await api('POST', '/v1/invites', t.accts[0].token, { userId: t.accts[3].id, code: t.code })).json).toMatchObject({ ok: true });
    again = await connect(`/v1/rooms/${t.code}/ws`, t.accts[3].token);
    await again.until(() => again.room?.members.some((m: any) => m.uid === t.accts[3].id), 'back in');
  });

  it('the night timer skips unfinished turns, even with every phone gone; "continue" skips offline players', async () => {
    const t = await table(4), [host] = t.players;
    await deal(t, { rules: rules({ nightT: 30 }), counts: { mafia: 1, detective: 0 } });
    expect(host.view.timer.end).toBeGreaterThan(Date.now());
    for (const p of t.players) p.ws.close();
    await sleep(50);
    const stub = roomStub(t.code);
    await shift(stub, st => { st.game.night.endsAt = Date.now() - 1; });  // the 30 s have passed
    expect(await runDurableObjectAlarm(stub)).toBe(true);
    const back = await connect(`/v1/rooms/${t.code}/ws`, t.accts[0].token);
    await back.until(() => back.view?.phase === 'morning', 'morning after the timer');
    const u = await table(4), h = u.players[0];
    await deal(u);
    u.players[3].ws.close();
    await h.until(() => h.room.members.filter((m: any) => m.online).length === 3);
    for (const p of u.players.slice(0, 3)) {
      const v = p.view; const o = v.night.opts.find((x: any) => !x.disabled && !x.teammate);
      p.send({ t: 'night', choice: v.night.key === 'none' ? null : o.seat, day: v.day });
    }
    await h.until(() => h.view.progress?.done === 3);
    expect(phaseOf(h)).toBe('night');
    h.send({ t: 'continue' });
    await h.until(() => phaseOf(h) !== 'night', 'continued');
  });

  it('closing the room ends it for everyone and deletes its data', async () => {
    const t = await table(4), [host, b] = t.players;
    b.send({ t: 'chat', to: -1, text: 'hi', cid: 'c1' });
    await host.until(() => host.got(m => m.t === 'chat'));
    host.send({ t: 'close' });
    await b.until(() => b.got(m => m.t === 'bye' && m.why === 'closed'), 'closed');
    expect((await api('GET', '/v1/rooms/' + t.code, t.accts[1].token)).json).toEqual({ error: 'no_room' });
    const stub = roomStub(t.code);
    expect(await runInDurableObject(stub, async (_o, state) => [await state.storage.get('room'), await state.storage.get('chat')])).toEqual([undefined, undefined]);
    const users = await DB().prepare('SELECT COUNT(*) AS n FROM users WHERE room_code IS NOT NULL').first<any>();
    expect(users.n).toBe(0);
  });

  it('buzz reaches the host up to the limit; ping reaches everyone', async () => {
    const t = await table(4), [host, b, c] = t.players;
    for (let i = 0; i < 4; i++) b.send({ t: 'buzz' });
    await host.until(() => host.room.members.find((m: any) => m.uid === t.accts[1].id).muted, 'muted');
    expect(host.msgs.filter(m => m.t === 'buzz')).toHaveLength(3);
    host.send({ t: 'ping' });
    await c.until(() => c.got(m => m.t === 'ping'), 'ping');
  });
});

describe('chat', () => {
  it('Everyone, 1:1, replies, reactions, edits, mentions, limits', async () => {
    const t = await table(4), [a, b, c] = t.players, cn = (p: Sock) => p.me.cn;
    a.send({ t: 'chat', to: -1, text: 'hello all', cid: 'x1', mentions: [cn(b)] });
    await c.until(() => c.got(m => m.t === 'chat' && m.msg.text === 'hello all'));
    await a.until(() => a.got(m => m.t === 'chat' && m.cid === 'x1'), 'ack with cid');
    await b.until(() => b.got(m => m.t === 'mention'), 'mention');
    const id = a.got(m => m.t === 'chat').msg.id;
    a.send({ t: 'chat', to: cn(b), text: 'psst', cid: 'x2', reply: undefined });
    await b.until(() => b.got(m => m.t === 'chat' && m.msg.text === 'psst'));
    await sleep(30);
    expect(c.got(m => m.t === 'chat' && m.msg.text === 'psst')).toBeUndefined();
    c.send({ t: 'chat', to: -1, text: 'reply', cid: 'x3', reply: id });
    await a.until(() => a.got(m => m.t === 'chat' && m.msg.reply === id));
    b.send({ t: 'react', id, rx: 4 });
    await a.until(() => a.got(m => m.t === 'chat' && m.msg.id === id && m.msg.rx?.[4]?.length === 1), 'reaction');
    a.send({ t: 'edit', id, text: 'hello everyone' });
    await c.until(() => c.got(m => m.t === 'chat' && m.msg.id === id && m.msg.edited), 'edited');
    b.send({ t: 'edit', id, text: 'not mine' });
    await b.until(() => b.got(m => m.t === 'err' && m.error === 'not_found'));
    for (let i = 0; i < 9; i++) c.send({ t: 'chat', to: -1, text: 'spam ' + i, cid: 's' + i });
    await c.until(() => c.got(m => m.t === 'err' && m.error === 'slow_down'), '8 per 10 s');
    const late = await connect(`/v1/rooms/${t.code}/ws`, t.accts[3].token);
    await late.until(() => late.got(m => m.t === 'chatAll'));
    expect(late.got(m => m.t === 'chatAll').msgs.some((m: any) => m.text === 'psst')).toBe(false);
  });

  it('out players reach only out players', async () => {
    const t = await table(5);
    await deal(t, { rules: rules(), counts: { mafia: 1, detective: 0 } });
    // the Doctor protects themselves and the Mafia kill someone else: one player is out for sure
    const doc = t.players.find(p => p.view.role === 'doctor')!.view.seat, day = t.players[0].view.day;
    for (const p of t.players) {
      const v = p.view, opts = v.night.opts.filter((o: any) => !o.disabled && !o.teammate);
      const choice = v.night.key === 'none' ? null : v.role === 'doctor' ? doc : opts.find((o: any) => o.seat !== doc).seat;
      p.send({ t: 'night', choice, day });
    }
    await t.players[0].until(() => t.players[0].view.phase !== 'night', 'dawn');
    const out = t.players.find(p => p.view.alive === false)!;
    expect(out).toBeTruthy();
    const alive = t.players.filter(p => p !== out);
    out.send({ t: 'chat', to: -1, text: 'boo', cid: 'o1' });
    await out.until(() => out.got(m => m.t === 'chat' && m.msg.outOnly));
    await sleep(30);
    for (const p of alive) expect(p.got(m => m.t === 'chat' && m.msg.text === 'boo')).toBeUndefined();
    out.send({ t: 'chat', to: alive[0].me.cn, text: 'hey', cid: 'o2' });
    await out.until(() => out.got(m => m.t === 'err' && m.error === 'out'), 'refused');
  });
});

describe('invites, join requests, presence', () => {
  it('presence reaches online friends; an invite and a join request arrive live; answering is "let you in"', async () => {
    const a = await account('Alhassan'), b = await account('Dareer'), x = await account('Stranger');
    await befriend(a, b);
    const hb = await connect('/v1/hub/ws', b.token);
    await hb.until(() => hb.got(m => m.t === 'unread'));
    const ha = await connect('/v1/hub/ws', a.token);
    await hb.until(() => hb.got(m => m.t === 'presence' && m.uid === a.id && m.on), 'a online');
    const { json } = await api('POST', '/v1/rooms', a.token);
    const ra = await connect(`/v1/rooms/${json.code}/ws`, a.token);
    await hb.until(() => hb.got(m => m.t === 'presence' && m.uid === a.id && m.st === 'lobby' && m.op), 'a in a lobby');
    const friends = await api('GET', '/v1/friends', b.token);
    expect(friends.json.friends[0]).toMatchObject({ id: a.id, on: true, st: 'lobby', op: true });
    // b asks to join; a answers with an invite: "let you in"
    expect((await api('POST', '/v1/join-requests', b.token, { userId: a.id })).json).toEqual({ ok: true });
    await ha.until(() => ha.got(m => m.t === 'note' && m.note.kind === 'join_request'), 'join request');
    const inv = await api('POST', '/v1/invites', a.token, { userId: b.id, code: json.code });
    expect(inv.json).toEqual({ ok: true, letIn: true });
    await hb.until(() => hb.got(m => m.t === 'note' && m.note.kind === 'let_in' && m.note.code === json.code), 'let in');
    // the request was answered: kept 24 h in the bell as "Let in", read-only, not counted
    expect((await api('GET', '/v1/notifications', a.token)).json).toMatchObject({ unread: 0, notifications: [{ kind: 'join_request', result: 'let_in', read: true }] });
    const bell = await api('GET', '/v1/notifications', b.token);
    expect(bell.json).toMatchObject({ unread: 1, notifications: [{ kind: 'let_in', from: { id: a.id } }] });
    expect(JSON.stringify(bell.json)).not.toContain('@');
    await api('POST', '/v1/notifications/read', b.token, {});
    expect((await api('GET', '/v1/notifications', b.token)).json.unread).toBe(0);
    // strangers can't invite or ask; a non-member can't invite into the room
    expect((await api('POST', '/v1/invites', x.token, { userId: a.id, code: json.code })).json).toEqual({ error: 'not_friends' });
    expect((await api('POST', '/v1/join-requests', x.token, { userId: a.id })).json).toEqual({ error: 'not_friends' });
    expect((await api('POST', '/v1/invites', b.token, { userId: a.id, code: json.code })).json).toEqual({ error: 'not_member' });
    // the room ends: a is no longer in a lobby, so b can't ask to join
    ra.send({ t: 'close' });
    await hb.until(() => hb.msgs.filter(m => m.t === 'presence' && m.uid === a.id).at(-1)?.st === '', 'a out of the room');
    expect((await api('POST', '/v1/join-requests', b.token, { userId: a.id })).json).toEqual({ error: 'not_open' });
    ha.ws.close();
    await hb.until(() => hb.msgs.filter(m => m.t === 'presence' && m.uid === a.id).at(-1)?.on === false, 'a offline');
  });

  it('friend requests and accepts show up in the bell live', async () => {
    const a = await account('Sami'), b = await account('Hokan');
    const hb = await connect('/v1/hub/ws', b.token), ha = await connect('/v1/hub/ws', a.token);
    await api('POST', '/v1/friend-requests', a.token, { handle: 'Hokan' });
    await hb.until(() => hb.got(m => m.t === 'note' && m.note.kind === 'friend_request' && m.note.from.id === a.id));
    await api('POST', `/v1/friend-requests/${a.id}/accept`, b.token);
    await ha.until(() => ha.got(m => m.t === 'note' && m.note.kind === 'friend_accept'));
  });

  it('a hidden user looks offline to friends', async () => {
    const a = await account('Fater'), b = await account('Farouq');
    await befriend(a, b);
    await DB().prepare('UPDATE users SET show_online = 0 WHERE id = ?').bind(a.id).run();
    const hb = await connect('/v1/hub/ws', b.token);
    await connect('/v1/hub/ws', a.token);
    await hb.until(() => hb.got(m => m.t === 'presence' && m.uid === a.id), 'presence');
    expect(hb.got(m => m.t === 'presence' && m.uid === a.id)).toMatchObject({ on: false, st: '' });
  });
});

it('rooms: create, look up, unknown codes, sockets need a session', async () => {
  const a = await account('Khaddour');
  const { json } = await api('POST', '/v1/rooms', a.token);
  expect(json.code).toMatch(/^\d{6}$/);
  expect((await api('GET', '/v1/rooms/' + json.code, a.token)).json).toEqual({ open: true, status: 'lobby', host: 'Khaddour' });
  expect((await api('GET', '/v1/rooms/000000', a.token)).json).toEqual({ error: 'no_room' });
  const nope = await connect('/v1/rooms/123456/ws', a.token);
  await nope.until(() => nope.got(m => m.t === 'err' && m.error === 'no_room'));
  await expect(connect(`/v1/rooms/${json.code}/ws`, 'x'.repeat(43))).rejects.toThrow(/401/);
});

describe('resilience (Sprint 1)', () => {
  const inDO = <T>(code: string, f: (state: DurableObjectState) => T | Promise<T>) => runInDurableObject(roomStub(code), (_o, state) => f(state));
  const fresh = (n: number, p: string) => Promise.all(Array.from({ length: n }, (_, i) => account(p + i + 'x' + Math.random().toString(36).slice(2, 6))));
  const choose = (p: Sock) => { const v = p.view, o = v.night.opts.find((x: any) => !x.disabled && !x.teammate); return v.night.key === 'none' ? null : o.seat; };

  it('S1-1: ten players joining at the same moment all get in (20 rounds)', async () => {
    const accts = await fresh(10, 'J');
    for (let round = 0; round < 20; round++) {
      const { json } = await api('POST', '/v1/rooms', accts[round % 10].token);
      const socks = await Promise.all(accts.map(a => connect(`/v1/rooms/${json.code}/ws`, a.token)));
      await socks[0].until(() => socks.every(x => x.room), 'everyone in');
      const st = await inDO(json.code, s => s.storage.get<any>('room'));
      expect(st.members.length, `round ${round}`).toBe(10);
      expect(new Set(st.members.map((m: any) => m.cn)).size, `round ${round}: chat numbers`).toBe(10);
      for (const x of socks) x.ws.close();
    }
  }, 120_000);

  it('S1-1: joins, chat and setup changes at the same moment lose nothing', async () => {
    const t = await table(5), late = await fresh(5, 'L'), [host] = t.players;
    const joining = late.map(a => connect(`/v1/rooms/${t.code}/ws`, a.token));
    t.players.forEach((p, i) => { for (let k = 0; k < 5; k++) p.send({ t: 'chat', to: -1, text: `m${i}.${k}`, cid: `c${i}.${k}` }); });
    for (let k = 0; k < 5; k++) host.send({ t: 'setup', buzzMax: k, rules: rules(), counts: { mafia: 1, detective: 0 } });
    const socks = await Promise.all(joining);
    await host.until(() => host.room.members.length === 10 && host.msgs.filter(m => m.t === 'chat').length === 25, '10 members, 25 messages');
    const st = await inDO(t.code, s => s.storage.get<any>('room'));
    expect(st.members.length).toBe(10);
    const chat = await inDO(t.code, s => s.storage.get<any>('chat'));
    expect(new Set(chat.msgs.map((m: any) => m.text)).size).toBe(25);
    for (const x of socks) await x.until(() => x.room, 'late room');
  }, 30_000);

  it('S1-1 + S1-6: a game-ending vote racing repeats and chat saves the game exactly once, with a record that replays', async () => {
    const t = await table(4), [host] = t.players;
    await deal(t, { rules: rules(), counts: { mafia: 1, detective: 0 } });
    const roleOf: string[] = [];
    for (const p of t.players) roleOf[p.view.seat] = p.view.role;
    await playNight(t.players);
    host.send({ t: 'startDay' }); await host.until(() => phaseOf(host) === 'day', 'day');
    host.send({ t: 'startVote', open: false }); await host.until(() => phaseOf(host) === 'vote', 'vote');
    const mafia = roleOf.indexOf('mafia'), id = host.view.voteId;
    for (const p of t.players) {  // everyone at once: the vote (twice), a chat, and the host marks the game
      if (p.view.ph !== 'vote') continue;
      const choice = p.view.seat === mafia ? 'none' : mafia;
      p.send({ t: 'vote', choice, id }); p.send({ t: 'vote', choice, id }); p.send({ t: 'chat', to: -1, text: 'gg', cid: 'g' + p.view.seat });
      host.send({ t: 'mark', valid: true });
    }
    await host.until(() => phaseOf(host) === 'end', 'end');
    await sleep(100);
    const rows = await DB().prepare('SELECT record, winner FROM games WHERE host_id = ?').bind(t.accts[0].id).all<{ record: string; winner: string }>();
    expect(rows.results.length).toBe(1);
    const rec = JSON.parse(rows.results[0].record), r = replay(rec);
    expect(r.ok).toBe(true);
    expect(r.ok && r.state.winner).toBe(rows.results[0].winner);
    expect(rec.roles).toEqual(roleOf);
  }, 30_000);

  it('S1-2: a phone that goes silent is shown offline, loses the host controls, can be skipped, and comes back', async () => {
    const t = await table(4), [host, b, c, d] = t.players;
    await deal(t, { rules: rules(), counts: { mafia: 1, detective: 0 } });
    expect(await inDO(t.code, s => s.storage.getAlarm())).toBeLessThanOrEqual(Date.now() + STALE_MS);
    // the host's phone loses its signal: the socket stays open, but nothing comes from it
    const hostSeat = host.view.seat;
    await inDO(t.code, s => { for (const w of s.getWebSockets(t.accts[0].id)) w.serializeAttachment({ at: Date.now() - STALE_MS - 1 }); });
    expect(await runDurableObjectAlarm(roomStub(t.code))).toBe(true);
    await b.until(() => b.room.members.find((m: any) => m.uid === t.accts[0].id)?.online === false, 'host shown offline');
    expect(b.me.host).toBe(true);
    await host.until(() => host.closed, 'the silent socket is closed');
    for (const p of [b, c, d]) p.send({ t: 'night', choice: choose(p), day: p.view.day });
    await b.until(() => b.view.progress?.done === 3, '3 done');
    b.send({ t: 'continue' });
    await b.until(() => phaseOf(b) !== 'night', 'the silent host was skipped');
    const t0 = Date.now(), back = await connect(`/v1/rooms/${t.code}/ws`, t.accts[0].token);
    await b.until(() => b.room.members.find((m: any) => m.uid === t.accts[0].id)?.online === true, 'host back online');
    await back.until(() => back.view?.seat === hostSeat, 'same seat');
    expect(Date.now() - t0).toBeLessThan(2000);
    expect(back.me.host).toBe(true);  // the room's host gets the controls back while connected
  }, 30_000);

  it('S1-2: live sockets are not closed by the check', async () => {
    const t = await table(4), [host] = t.players;
    await runDurableObjectAlarm(roomStub(t.code));
    await sleep(50);
    expect(t.players.every(p => !p.closed)).toBe(true);
    expect(host.room.members.every((m: any) => m.online)).toBe(true);
  });

  it('S1-5: keep-alives are answered without waking the room', async () => {
    const t = await table(4), [host] = t.players;
    const before = await inDO(t.code, s => s.getWebSockets(t.accts[0].id)[0].deserializeAttachment() as { at: number });
    await sleep(5);
    host.ws.send('ping');
    await host.until(() => host.pongs === 1, 'pong');
    const [after, auto] = await inDO(t.code, s => {
      const w = s.getWebSockets(t.accts[0].id)[0];
      return [w.deserializeAttachment(), s.getWebSocketAutoResponseTimestamp(w)?.getTime() ?? null] as const;
    });
    expect(after).toEqual(before);  // the room's handler never ran (it stamps every message it sees)
    expect(auto).toBeGreaterThan(before.at);
  });

  it('S1-3: a phone that reconnects gets the events it missed, once, in order; too far behind it gets "missed"', async () => {
    const t = await table(5), [host, , , , e] = t.players;
    await deal(t, { rules: rules(), counts: { mafia: 1, detective: 0 } });
    const last = Math.max(...e.msgs.filter(m => m.rev).map(m => m.rev));
    e.ws.close();
    await host.until(() => host.room.members.filter((m: any) => m.online).length === 4, 'e offline');
    for (const p of t.players.slice(0, 4)) p.send({ t: 'night', choice: choose(p), day: p.view.day });
    await host.until(() => host.view.progress?.done === 4, '4 done');
    host.send({ t: 'continue' });
    await host.until(() => phaseOf(host) === 'morning', 'morning');
    const back = await connect(`/v1/rooms/${t.code}/ws?rev=${last}`, t.accts[4].token);
    await back.until(() => back.view?.phase === 'morning', 'back in the morning');
    const evs = back.msgs.filter(m => m.t === 'events'), revs = back.msgs.filter(m => m.rev != null).map(m => m.rev);
    expect(evs.length).toBeGreaterThan(0);
    expect(evs.every(m => m.rev > last)).toBe(true);
    expect(revs).toEqual([...revs].sort((x, y) => x - y));
    const all = evs.flatMap(m => m.events);
    expect(all.filter((x: any) => x.t === 'phase' && x.phase === 'morning').length).toBe(1);
    expect(all.some((x: any) => x.t === 'night')).toBe(false);  // the private night summary stays out
    expect(back.got(m => m.t === 'missed')).toBeUndefined();
    const hr = host.msgs.filter(m => m.rev != null).map(m => m.rev);
    expect(hr).toEqual([...hr].sort((x, y) => x - y));

    await shift(roomStub(t.code), st => { st.cut = st.rev; });  // as if more than 200 events had happened since
    back.ws.close();
    const behind = await connect(`/v1/rooms/${t.code}/ws?rev=1`, t.accts[4].token);
    await behind.until(() => behind.got(m => m.t === 'missed'), 'missed');
    await behind.until(() => behind.view?.phase === 'morning', 'current view');
    expect(behind.got(m => m.t === 'events')).toBeUndefined();
  }, 30_000);

  it('S1-4: a repeated night choice or vote changes nothing and answers nothing; an old one is stale', async () => {
    const t = await table(4), [host] = t.players;
    await deal(t, { rules: rules(), counts: { mafia: 1, detective: 0 } });
    const p = t.players[1], day = p.view.day, choice = choose(p);
    p.send({ t: 'night', choice, day }); p.send({ t: 'night', choice, day });
    p.send({ t: 'night', choice, day: day - 1 });
    await p.until(() => p.got(m => m.t === 'err'), 'an error');
    await sleep(50);
    expect(p.msgs.filter(m => m.t === 'err').map(m => m.error)).toEqual(['stale']);
    await playNight(t.players);
    host.send({ t: 'startDay' }); await host.until(() => phaseOf(host) === 'day', 'day');
    host.send({ t: 'startVote', open: false }); await host.until(() => phaseOf(host) === 'vote', 'vote');
    const v = t.players.find(x => x.view.ph === 'vote')!, id = v.view.voteId, before = v.msgs.filter(m => m.t === 'err').length;
    v.send({ t: 'vote', choice: 'none', id }); v.send({ t: 'vote', choice: 'none', id });
    v.send({ t: 'vote', choice: 'none', id: id - 1 });
    await v.until(() => v.msgs.filter(m => m.t === 'err').length > before, 'an error');
    await sleep(50);
    expect(v.msgs.filter(m => m.t === 'err').slice(before).map(m => m.error)).toEqual(['stale']);
    await host.until(() => host.view.progress?.done === 1, 'one vote counted');
  }, 30_000);
});

describe('hub keep-alive (Sprint 3)', () => {
  it('pings are answered by Cloudflare without waking the hub', async () => {
    const a = await account('Ha' + Math.random().toString(36).slice(2, 6));
    const h = await connect('/v1/hub/ws', a.token);
    await h.until(() => h.got(m => m.t === 'unread'), 'unread');
    h.ws.send('ping');
    await h.until(() => h.pongs === 1, 'pong');
    const ns = (env as unknown as { HUB: DurableObjectNamespace }).HUB;
    const auto = await runInDurableObject(ns.get(ns.idFromName(a.id)), (_o, state) =>
      state.getWebSocketAutoResponseTimestamp(state.getWebSockets()[0])?.getTime() ?? null);
    expect(auto).not.toBeNull();
  });
});

describe('the room I am in (Sprint 4)', () => {
  it('GET /v1/me says which room I am in, lobby or game, and nothing once it is closed', async () => {
    const t = await table(4), [host] = t.players;
    const me = async () => (await api('GET', '/v1/me', t.accts[1].token)).json.user.room;
    expect(await me()).toEqual({ code: t.code, status: 'lobby' });
    await deal(t, { rules: rules(), counts: { mafia: 1, detective: 0 } });
    expect(await me()).toEqual({ code: t.code, status: 'game' });
    host.send({ t: 'close' });
    await t.players[1].until(() => t.players[1].got(m => m.t === 'bye'), 'bye');
    await sleep(50);
    expect(await me()).toBeNull();
  });
});

describe('safety in the room (Sprint 5)', () => {
  it('a block stops chat both ways at once (Everyone, DMs, history on rejoin); a reported message is snapshotted from the room', async () => {
    const t = await table(4), [a, b, c] = t.players;
    expect(typeof a.got(m => m.t === 'room').now).toBe('number');
    expect((await api('POST', '/v1/blocks', t.accts[0].token, { userId: t.accts[1].id })).json).toEqual({ ok: true });
    b.send({ t: 'chat', to: -1, text: 'hello room', cid: 'h1' });
    await c.until(() => c.got(m => m.t === 'chat' && m.msg.text === 'hello room'), 'C gets it');
    b.send({ t: 'chat', to: a.me.cn, text: 'psst', cid: 'h2' });
    await b.until(() => b.got(m => m.t === 'chat' && m.cid === 'h2'), 'B sees it sent');
    await sleep(100);
    expect(a.got(m => m.t === 'chat' && m.msg.from === b.me.cn)).toBeUndefined();
    a.ws.close();
    const back = await connect(`/v1/rooms/${t.code}/ws`, t.accts[0].token);
    await back.until(() => back.got(m => m.t === 'chatAll'), 'history');
    expect(back.got(m => m.t === 'chatAll').msgs.some((m: any) => m.from === b.me.cn)).toBe(false);
    // C reports B's message: the room supplies the text
    const id = c.got(m => m.t === 'chat' && m.msg.text === 'hello room').msg.id;
    expect((await api('POST', '/v1/reports', t.accts[2].token, { userId: t.accts[1].id, reason: 'harassment', room: t.code, msgId: id })).json).toEqual({ ok: true });
    const snap = JSON.parse((await DB().prepare('SELECT snapshot FROM reports').first<{ snapshot: string }>())!.snapshot);
    expect(snap.message.text).toBe('hello room');
    expect(snap.room).toBe(t.code);
    // a message by someone else can't be pinned on B
    expect((await api('POST', '/v1/reports', t.accts[2].token, { userId: t.accts[3].id, reason: 'spam', room: t.code, msgId: id })).status).toBe(404);
  });
});
