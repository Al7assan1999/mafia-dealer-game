import { runDurableObjectAlarm, runInDurableObject } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_RULES } from '@mafia/engine';
import { setup } from './helpers.ts';
import { account, api, befriend, connect, DB, roomStub, sleep, type Sock } from './live.ts';

beforeEach(async () => { await setup(); });

const rules = (o = {}) => ({ ...DEFAULT_RULES, ...o });
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

  it('a kick mid-game eliminates the player, who cannot come back', async () => {
    const t = await table(5), [host, , , , e] = t.players;
    await deal(t);
    const seat = e.view.seat;
    host.send({ t: 'kick', uid: t.accts[4].id });
    await e.until(() => e.got(m => m.t === 'bye' && m.why === 'kicked'), 'bye');
    await host.until(() => host.view.roster[seat].alive === false || host.view.phase === 'end', 'out');
    const again = await connect(`/v1/rooms/${t.code}/ws`, t.accts[4].token);
    await again.until(() => again.got(m => m.t === 'err' && m.error === 'kicked'), 'kicked');
  });

  it('the night timer skips unfinished turns, even with every phone gone; "continue" skips offline players', async () => {
    const t = await table(4), [host] = t.players;
    await deal(t, { rules: rules({ nightT: 30 }), counts: { mafia: 1, detective: 0 } });
    expect(host.view.timer.end).toBeGreaterThan(Date.now());
    for (const p of t.players) p.ws.close();
    await sleep(50);
    const stub = roomStub(t.code);
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
    expect((await api('GET', '/v1/notifications', a.token)).json.notifications).toEqual([]);  // the request was answered
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
