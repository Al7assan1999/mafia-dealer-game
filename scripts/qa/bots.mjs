// QA: scripted players against the local Worker (port 8790, see docs/handoff-2026-11-25.md); the rules of integration_test/online_test.dart.
// node bots.mjs signup <name>...          → prints name=token lines (accounts made, handle = name)
// node bots.mjs play <code> <token>...     → each token joins room <code> and plays; first one chats once
// node bots.mjs friend <token> <handle>    → friend request to <handle>
const EVERYONE = -1; // packages/protocol/src/live.ts
const base = 'http://127.0.0.1:8790';
// the app build the bots report: 1.0.0 by default; BOT_BUILD=100016 (or 0: none) plays an older phone, which can't be dealt in
const BOT_BUILD = process.env.BOT_BUILD ?? '100017';
const api = async (tok, method, path, body) => {
  const r = await fetch(base + path, { method, headers: { 'content-type': 'application/json', ...(tok ? { authorization: 'Bearer ' + tok } : {}) }, body: body && JSON.stringify(body) });
  const j = await r.json().catch(() => ({})); if (!r.ok) throw new Error(`${method} ${path} ${r.status} ${JSON.stringify(j)}`); return j;
};
const [cmd, ...a] = process.argv.slice(2);
if (cmd === 'signup') for (const n of a) {
  const email = `${n}@example.com`;
  await api(null, 'POST', '/v1/auth/email/start', { email });
  let code; for (let i = 0; i < 50 && !code; i++) { code = (await api(null, 'GET', `/v1/test/last-code/${email}`)).code; if (!code) await new Promise(r => setTimeout(r, 200)); }
  const { token } = await api(null, 'POST', '/v1/auth/email/verify', { email, code, device: 'bot' });
  await api(token, 'PATCH', '/v1/me', { handle: n, display: n[0].toUpperCase() + n.slice(1) });
  console.log(`${n}=${token}`);
}
if (cmd === 'friend') console.log(await api(a[0], 'POST', '/v1/friend-requests', { handle: a[1] }));
if (cmd === 'play') {
  const [code, ...toks] = a;
  toks.forEach((tok, i) => {
    let room, view, readyFor = -1, chatted = false; const sent = new Set();
    const ws = new WebSocket(base.replace('http', 'ws') + `/v1/rooms/${code}/ws${BOT_BUILD !== '0' ? '?v=' + BOT_BUILD : ''}`, ['mafia.v1', tok]);
    const send = m => { const s = JSON.stringify(m); if (!sent.has(s)) { sent.add(s); ws.send(s); } };
    ws.onopen = () => console.log(`bot${i} in ${code}`);
    ws.onclose = e => console.log(`bot${i} closed ${e.code}`);
    ws.onmessage = ({ data }) => {
      if (data === 'pong') return;
      const m = JSON.parse(data);
      if (m.t === 'room') room = m.room;
      if (i === 0 && !chatted && room) { chatted = true; send({ t: 'chat', to: EVERYONE, text: 'Hi from the bot / مرحبا', cid: 'qa' + Date.now() }); }
      if (m.t !== 'view') return;
      view = m.view; if (!view) return;
      if (view.phase === 'deal' && room && readyFor !== room.deal) { readyFor = room.deal; send({ t: 'ready', deal: readyFor }); }
      if (view.ph === 'night') { const no = view.night, opt = no.opts.find(o => !o.disabled); send({ t: 'night', choice: no.key === 'none' ? null : opt?.seat, day: view.day }); }
      if (view.ph === 'vote') { const o = view.voteOpts.filter(o => o.seat !== view.seat); send({ t: 'vote', choice: o.length ? o[0].seat : 'none', id: view.voteId }); }
    };
    setInterval(() => ws.readyState === 1 && ws.send('ping'), 10000);
  });
}
