// QA load test: many bot players in many online rooms at once, against the LOCAL Worker (port 8790, see
// docs/handoff-2026-11-25.md). Counts what Cloudflare would bill and everything that fails.
//   node load.mjs seed <players>                    → writes load-seed.sql here; apply it to the local D1:
//        cd server && npx wrangler d1 execute mafia-dealer-game --local --file ../scripts/qa/load-seed.sql
//   node load.mjs run <players> [games=1] [pace=1]  → rooms of 6-10 bots play whole games; prints the report
// pace scales the pauses (host steps, chat). Accounts are load0..loadN-1; their tokens come from their number.
import { createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';

const base = process.env.BASE || 'http://127.0.0.1:8790';
const tokenOf = i => createHash('sha256').update('mafia-load-' + i).digest('base64url');  // 43 chars, as the server wants
const sha = s => createHash('sha256').update(s).digest('hex');
const [cmd, nArg, gArg, pArg] = process.argv.slice(2);
const N = +nArg || 100;

if (cmd === 'seed') {
  const now = Date.now(), rows = [];
  for (let i = 0; i < N; i++) rows.push(
    `INSERT OR IGNORE INTO users (id, handle, display, created_at) VALUES ('load-${i}', 'load${i}', 'L${i}', ${now});`,
    `INSERT OR IGNORE INTO sessions (id, token_hash, user_id, device, created_at, last_seen_at, expires_at) VALUES ('load-s${i}', '${sha(tokenOf(i))}', 'load-${i}', 'load', ${now}, ${now}, ${now + 180 * 864e5});`);
  writeFileSync(new URL('./load-seed.sql', import.meta.url), rows.join('\n') + '\n');
  console.log(`load-seed.sql: ${N} accounts`);
  process.exit(0);
}
if (cmd !== 'run') { console.log('usage: node load.mjs seed <players> | run <players> [games] [pace]'); process.exit(1); }

const BUILD = 100017;  // MODES_BUILD in packages/protocol/src/live.ts: the room deals only to 1.0.0 apps
const GAMES = +gArg || 1, PACE = pArg == null ? 1 : +pArg, GAME_MS = 180e3;
const sleep = ms => new Promise(r => setTimeout(r, ms * PACE));
const c = { http: 0, httpErr: 0, wsOpen: 0, wsFail: 0, wsDrop: 0, wsIn: 0, pings: 0, wsOut: 0, outBytes: 0, chats: 0, games: 0, stuck: 0 };
const errs = {}, lat = [], stuckAt = [];

async function api(tok, method, path, body) {
  c.http++;
  const r = await fetch(base + path, { method, headers: { 'content-type': 'application/json', authorization: 'Bearer ' + tok }, body: body && JSON.stringify(body) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) { c.httpErr++; throw new Error(`${method} ${path} ${r.status} ${JSON.stringify(j)}`); }
  return j;
}

/** A socket like the app's: subprotocol auth, a ping every 10 s (the app's), and counters. */
function sock(path, tok, onMsg) {
  return new Promise(res => {
    const ws = new WebSocket(base.replace('http', 'ws') + path, ['mafia.v1', tok]);
    let open = false, done = false;
    ws.onopen = () => { open = true; c.wsOpen++; res(ws); };
    ws.onerror = () => { if (!open) { c.wsFail++; errs['ws connect ' + path.split('/')[2]] = (errs['ws connect ' + path.split('/')[2]] || 0) + 1; res(null); } };
    ws.onclose = () => { if (open && !ws.bye) c.wsDrop++; clearInterval(ws.pinger); done = true; };
    ws.onmessage = ({ data }) => {
      if (data === 'pong') return;
      c.wsOut++; c.outBytes += data.length;
      const m = JSON.parse(data);
      if (m.t === 'err') errs[m.error] = (errs[m.error] || 0) + 1;
      onMsg?.(m);
    };
    ws.out = m => { if (ws.readyState === 1) { c.wsIn++; ws.send(JSON.stringify(m)); } };
    ws.pinger = setInterval(() => { if (ws.readyState === 1) { c.pings++; ws.send('ping'); } }, 10e3);
  });
}

/** One room: the host makes it, everyone joins, they play GAMES games; resolves when done or stuck. */
async function room(seats) {
  const toks = seats.map(tokenOf), bots = [];
  let code;
  try { ({ code } = await api(toks[0], 'POST', '/v1/rooms')); } catch (e) { errs['create room: ' + e.message] = 1; return; }
  let finish, phaseSent = 0, played = 0, deadline;
  const over = new Promise(r => (finish = r));
  for (let k = 0; k < seats.length; k++) {
    const me = { room: null, view: null, acted: new Set(), chatted: new Set() };
    const host = k === 0;
    me.ws = await sock(`/v1/rooms/${code}/ws?v=${BUILD}`, toks[k], m => {
      if (m.t === 'room') me.room = m.room;
      if (m.t === 'err' && host && !me.view) { c.stuck++; stuckAt.push(`${code}: ${m.error}`); finish(); }  // the deal was refused
      if (m.t !== 'view' || !m.view) return;
      const v = (me.view = m.view);
      if (host && phaseSent) { lat.push(Date.now() - phaseSent); phaseSent = 0; }
      // every player: the same actions as the app's buttons
      if (v.phase === 'deal' && !me.acted.has('d' + me.room.deal)) { me.acted.add('d' + me.room.deal); me.ws.out({ t: 'ready', deal: me.room.deal }); }
      if (v.ph === 'night' && !me.acted.has('n' + me.room.deal + ':' + v.day)) {
        me.acted.add('n' + me.room.deal + ':' + v.day);
        const o = v.night.opts.find(o => !o.disabled && !o.teammate);
        sleep(200 + Math.random() * 800).then(() => me.ws.out({ t: 'night', choice: v.night.key === 'none' ? null : o ? o.seat : 'skip', day: v.day }));
      }
      if (v.ph === 'vote' && !me.acted.has('v' + me.room.deal + ':' + v.voteId)) {
        me.acted.add('v' + me.room.deal + ':' + v.voteId);
        const o = v.voteOpts.find(o => !o.disabled && o.seat !== v.seat);
        sleep(200 + Math.random() * 800).then(() => me.ws.out({ t: 'vote', choice: o ? o.seat : 'none', id: v.voteId }));
      }
      if (v.phase === 'day' && !me.chatted.has(me.room.deal + ':' + v.day) && Math.random() < 0.5) {
        me.chatted.add(me.room.deal + ':' + v.day); c.chats++;
        sleep(Math.random() * 1500).then(() => me.ws.out({ t: 'chat', to: -1, text: 'load test ' + v.day, cid: 'l' + Math.random().toString(36).slice(2, 10) }));
      }
      if (!host) return;
      // the host also moves the game on, as the app's host buttons do
      const step = msg => sleep(1500).then(() => { phaseSent = Date.now(); me.ws.out(msg); });
      const key = me.room.deal + ':' + v.phase + ':' + v.day + ':' + (v.voteId ?? '');
      if (me.acted.has(key)) return;
      me.acted.add(key);
      if (v.phase === 'morning') step({ t: 'startDay' });
      else if (v.phase === 'day') step({ t: 'startVote', open: false });
      else if (v.phase === 'verdict') step({ t: 'nextNight' });
      else if (v.phase === 'end') { c.games++; if (++played < GAMES) { deadline = Date.now() + GAME_MS; step({ t: 'deal' }); } else finish(); }
    });
    if (!me.ws) { finish(); break; }
    bots.push(me);
    // the app's other socket: presence and notifications (Hub)
    me.hub = await sock('/v1/hub/ws', toks[k]);
  }
  const host = bots[0];
  if (host?.ws && bots.length === seats.length) {
    // wait for the room to list everyone, as the host would, then set up and deal
    for (let t = 0; t < 100 && host.room?.members.length !== seats.length; t++) await sleep(100);
    const n = seats.length;
    host.ws.out({ t: 'setup', rules: host.room.rules, counts: { mafia: n >= 9 ? 3 : 2, detective: 1 }, buzzMax: 3 });
    await sleep(500);
    deadline = Date.now() + GAME_MS;
    host.ws.out({ t: 'deal' });
    const watch = setInterval(() => { if (Date.now() > deadline) { c.stuck++; stuckAt.push(`${code}: ${host.view?.phase ?? 'no view'}`); finish(); } }, 1000);
    await over; clearInterval(watch);
  }
  for (const b of bots) for (const ws of [b.ws, b.hub]) if (ws) { ws.bye = true; ws.close(); }
}

// rooms of 6..10 players (the app's usual tables) until everyone is seated
const tables = []; for (let i = 0, s = 0; i < N; s++) { const n = Math.min([6, 7, 8, 9, 10][s % 5], N - i); if (n < 4) { tables.at(-1).push(...Array.from({ length: n }, (_, k) => i + k)); i += n; continue; } tables.push(Array.from({ length: n }, (_, k) => i + k)); i += n; }
console.log(`${N} players, ${tables.length} rooms, ${GAMES} game(s) each, against ${base}`);
const t0 = Date.now();
await Promise.all(tables.map(room));
const secs = (Date.now() - t0) / 1000, pct = (a, p) => a.length ? a.sort((x, y) => x - y)[Math.floor(a.length * p)] : 0;

const doRaw = c.wsOpen + c.wsIn, doPaid = c.wsOpen + Math.ceil(c.wsIn / 20), workerReq = c.http + c.wsOpen + c.wsFail;
console.log(`
done in ${secs.toFixed(0)} s
games finished ${c.games} of ${tables.length * GAMES}   stuck rooms ${c.stuck}${stuckAt.length ? ' (' + stuckAt.slice(0, 10).join(', ') + ')' : ''}
sockets opened ${c.wsOpen}   failed ${c.wsFail}   dropped by the server ${c.wsDrop}   HTTP ${c.http} (errors ${c.httpErr})
server errors ${JSON.stringify(errs)}
host step → next view: p50 ${pct(lat, 0.5)} ms, p95 ${pct(lat, 0.95)} ms, max ${pct(lat, 0.999)} ms
messages sent by phones ${c.wsIn} (+ ${c.pings} pings, answered free)   sent by the server ${c.wsOut} (${(c.outBytes / 1e6).toFixed(1)} MB)

What Cloudflare counts (this run):
  Worker requests      ${workerReq}   (${(workerReq / N).toFixed(1)} per player)
  DO requests, raw     ${doRaw}   (${(doRaw / Math.max(c.games, 1)).toFixed(0)} per game, ${(doRaw / N).toFixed(1)} per player)  ← the Free plan's 100K/day
  DO requests, billed  ${doPaid}   (${(doPaid / N).toFixed(1)} per player)  ← Paid: incoming messages count 20:1
  (not seen from here: Room alarms and D1 rows; read them from the local Worker's log)`);
process.exit(c.stuck || c.wsFail || c.httpErr || c.wsDrop ? 1 : 0);
