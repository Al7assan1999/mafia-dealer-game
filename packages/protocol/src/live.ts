// Live messages: the room socket (/v1/rooms/:code/ws) and the hub socket (/v1/hub/ws).
// Sockets authenticate with the subprotocols ['mafia.v1', <session token>].
import { z } from 'zod';
import type { Counts, GameEvent, PublicView, Role, Rules, SeatView } from '@mafia/engine';
import type { Avatar } from './index.ts';

export const SUBPROTOCOL = 'mafia.v1';
export const CHAT_RX = 30, CHAT_MAX = 200, CHAT_KEEP = 50, CHAT_EDIT_MS = 15 * 60e3;
export const EVERYONE = -1;

const seat = z.number().int().min(0).max(19);
const cn = z.number().int().min(EVERYONE).max(999);
const RulesIn = z.object({
  skip: z.boolean(), norep: z.boolean(), saverev: z.boolean(), decoy: z.boolean(), self: z.boolean(), rep: z.boolean(),
  reveal: z.boolean(), timer: z.number().int().min(30).max(900), nightT: z.union([z.literal(0), z.literal(30), z.literal(45), z.literal(60), z.literal(90), z.literal(120), z.literal(180)]),
  ghost: z.boolean(), skipVote: z.boolean(),
}).strict();

/** Everything a phone may send to its room. Seats come from the session, never from the message. */
export const RoomIn = z.discriminatedUnion('t', [
  // host
  z.object({ t: z.literal('setup'), rules: RulesIn, counts: z.object({ mafia: z.number().int().min(1).max(10), detective: z.number().int().min(0).max(1) }).strict(), buzzMax: z.number().int().min(0).max(20) }).strict(),
  z.object({ t: z.literal('deal') }).strict(),          // deal roles (also Play again after the end)
  z.object({ t: z.literal('start') }).strict(),         // begin without waiting for everyone's "ready"
  z.object({ t: z.literal('startDay') }).strict(),
  z.object({ t: z.literal('timer'), op: z.enum(['start', 'pause', 'reset', 'add']), sec: z.number().int().min(1).max(3600).optional() }).strict(),
  z.object({ t: z.literal('startVote'), open: z.boolean() }).strict(),
  z.object({ t: z.literal('nextNight') }).strict(),
  z.object({ t: z.literal('continue') }).strict(),      // skip the turns of players who are offline
  z.object({ t: z.literal('kick'), uid: z.string().max(64) }).strict(),
  z.object({ t: z.literal('unmute'), uid: z.string().max(64) }).strict(),
  z.object({ t: z.literal('ping') }).strict(),          // buzz every phone
  z.object({ t: z.literal('mark'), valid: z.boolean() }).strict(),  // the finished game counts in stats or not
  z.object({ t: z.literal('lobby') }).strict(),         // back to the lobby after the end
  z.object({ t: z.literal('close') }).strict(),
  // players (the host is a player too)
  z.object({ t: z.literal('ready'), deal: z.number().int() }).strict(),
  z.object({ t: z.literal('night'), choice: z.union([seat, z.literal('skip'), z.null()]), day: z.number().int() }).strict(),
  z.object({ t: z.literal('vote'), choice: z.union([seat, z.literal('none')]), id: z.number() }).strict(),
  z.object({ t: z.literal('buzz') }).strict(),
  z.object({ t: z.literal('leave') }).strict(),
  // chat
  z.object({ t: z.literal('chat'), to: cn, text: z.string().trim().min(1).max(CHAT_MAX), reply: z.number().int().optional(), mentions: z.array(cn).max(10).optional(), cid: z.string().max(40) }).strict(),
  z.object({ t: z.literal('react'), id: z.number().int(), rx: z.number().int().min(0).max(CHAT_RX - 1) }).strict(),
  z.object({ t: z.literal('edit'), id: z.number().int(), text: z.string().trim().min(1).max(CHAT_MAX) }).strict(),
]);
export type RoomIn = z.infer<typeof RoomIn>;

export interface RoomMember { uid: string; cn: number; display: string; handle: string | null; avatar: Avatar; online: boolean; host: boolean; ready: boolean; muted: boolean; seat: number | null }
export interface RoomInfo {
  code: string; members: RoomMember[]; rules: Rules; counts: Counts; buzzMax: number;
  status: 'lobby' | 'game'; deal: number; gameId: string | null; valid: boolean | null;
}
export interface ChatMsg { id: number; from: number; to: number; text: string; at: number; reply?: number; mentions?: number[]; rx?: Record<number, number[]>; edited?: true; outOnly?: true }

/** Everything the room sends a phone. */
export type RoomOut =
  | { t: 'room'; room: RoomInfo; me: { uid: string; cn: number; host: boolean } }
  | { t: 'view'; view: SeatView | PublicView | null }
  | { t: 'events'; events: GameEvent[] }
  | { t: 'chatAll'; msgs: ChatMsg[] }
  | { t: 'chat'; msg: ChatMsg; cid?: string }
  | { t: 'mention'; id: number; from: number }
  | { t: 'buzz'; from: string }            // to the host: a player buzzed
  | { t: 'ping' }                          // the host pinged everyone
  | { t: 'err'; error: string; ref?: string }
  | { t: 'bye'; why: 'kicked' | 'closed' | 'left' };

/** What the hub (one per account, while the app is open) pushes. */
export type HubOut =
  | { t: 'presence'; uid: string; on: boolean; st: '' | 'lobby' | 'game'; op: boolean }
  | { t: 'note'; note: Notification }
  | { t: 'unread'; n: number };

export interface Notification { id: string; kind: 'invite' | 'join_request' | 'let_in' | 'friend_request' | 'friend_accept'; from: import('./index.ts').UserCard; code: string | null; at: number; expiresAt: number; read: boolean }

export const Invite = z.object({ userId: z.string().max(64), code: z.string().regex(/^\d{6}$/) }).strict();
export const JoinRequest = z.object({ userId: z.string().max(64) }).strict();
export const MarkRead = z.object({ ids: z.array(z.string().max(64)).max(100).optional() }).strict();
export const MarkGame = z.object({ valid: z.boolean() }).strict();

export type { Role };
