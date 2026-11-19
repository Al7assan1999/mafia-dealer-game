// Room chat rules (ported from the old app's host): Everyone + 1:1 by chat handle (cn), out players only reach out
// players, reactions, replies, @mentions, edits for 15 minutes, rate limits, the last 50 per conversation.
// Kept in the room's storage and deleted with the room.
import { CHAT_EDIT_MS, CHAT_KEEP, EVERYONE, type ChatMsg } from '@mafia/protocol';

export interface ChatState { seq: number; msgs: ChatMsg[]; sent: Record<number, number[]>; rxs: Record<number, number[]> }
export const newChat = (): ChatState => ({ seq: 0, msgs: [], sent: {}, rxs: {} });
/** Who is in the room (cns) and who is out of the running game (dead seats). */
export interface Who { members: Set<number>; outs: Set<number> }

const SEND_MAX = 8, RX_MAX = 20, WINDOW = 10e3;
const conv = (m: { from: number; to: number }) => (m.to === EVERYONE ? 'all' : [m.from, m.to].sort((a, b) => a - b).join(':'));

/** Can `viewer` see this message? Out players' Everyone messages reach only out players. */
export const canSee = (m: ChatMsg, viewer: number, w: Who) =>
  m.to === EVERYONE ? !m.outOnly || w.outs.has(viewer) : viewer === m.from || viewer === m.to;

/** Within the rate limit? (records the hit) */
function rate(log: Record<number, number[]>, who: number, max: number, now: number) {
  const recent = (log[who] || []).filter(t => now - t < WINDOW);
  if (recent.length >= max) { log[who] = recent; return false; }
  log[who] = [...recent, now]; return true;
}

export type ChatResult = { ok: true; msg: ChatMsg; mentions: number[] } | { ok: false; error: string };

export function send(s: ChatState, w: Who, from: number, inp: { to: number; text: string; reply?: number; mentions?: number[] }, now: number): ChatResult {
  const { to, text } = inp, out = w.outs.has(from);
  if (to !== EVERYONE && (!w.members.has(to) || to === from)) return { ok: false, error: 'to' };
  if (out && to !== EVERYONE && !w.outs.has(to)) return { ok: false, error: 'out' };  // out players reach only out players
  const m: ChatMsg = { id: 0, from, to, text, at: now };
  if (out && to === EVERYONE) m.outOnly = true;
  if (inp.reply != null) {
    const r = s.msgs.find(x => x.id === inp.reply);
    if (!r || conv(r) !== conv(m) || !canSee(r, from, w)) return { ok: false, error: 'reply' };
    m.reply = r.id;
  }
  const mentions = [...new Set(inp.mentions || [])].filter(c => c !== from && w.members.has(c) && canSee(m, c, w));
  if ((inp.mentions || []).some(c => !mentions.includes(c) && c !== from)) return { ok: false, error: 'mention' };
  if (mentions.length) m.mentions = mentions;
  if (!rate(s.sent, from, SEND_MAX, now)) return { ok: false, error: 'slow_down' };
  m.id = ++s.seq;
  s.msgs.push(m);
  const same = s.msgs.filter(x => conv(x) === conv(m));
  if (same.length > CHAT_KEEP) { const drop = new Set(same.slice(0, same.length - CHAT_KEEP).map(x => x.id)); s.msgs = s.msgs.filter(x => !drop.has(x.id)); }
  return { ok: true, msg: m, mentions };
}

/** Toggles a reaction. Out players react only to what only out players see (their Everyone messages, 1:1 with outs). */
export function react(s: ChatState, w: Who, who: number, id: number, rx: number, now: number): ChatResult {
  const m = s.msgs.find(x => x.id === id);
  if (!m || !canSee(m, who, w)) return { ok: false, error: 'not_found' };
  if (w.outs.has(who) && m.to === EVERYONE && !m.outOnly) return { ok: false, error: 'out' };
  if (!rate(s.rxs, who, RX_MAX, now)) return { ok: false, error: 'slow_down' };
  const rxs = (m.rx ||= {}), list = rxs[rx] || [];
  rxs[rx] = list.includes(who) ? list.filter(c => c !== who) : [...list, who];
  if (!rxs[rx].length) delete rxs[rx];
  if (!Object.keys(rxs).length) delete m.rx;
  return { ok: true, msg: m, mentions: [] };
}

/** Edits my own message within 15 minutes. */
export function edit(s: ChatState, who: number, id: number, text: string, now: number): ChatResult {
  const m = s.msgs.find(x => x.id === id);
  if (!m || m.from !== who) return { ok: false, error: 'not_found' };
  if (now - m.at > CHAT_EDIT_MS) return { ok: false, error: 'too_late' };
  m.text = text; m.edited = true;
  return { ok: true, msg: m, mentions: [] };
}
