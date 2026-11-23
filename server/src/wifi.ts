// Adding a finished Wi-Fi game to online history (S7-2). The host's phone sends the game's record; automatic rules
// judge it at once (the record must replay on our engine, plus the limits in settings.wifi_rules); then every other
// player confirms from the bell. All confirm: approved (the game joins `games` with source 'wifi'). Any "Not me":
// declined. The window runs out: expired. Every request is kept raw with the rules version that judged it.
import { Hono } from 'hono';
import { replay, type GameRecord, type Role } from '@mafia/engine';
import { WifiAnswer, WifiRequestIn, type Notification, type WifiGameInfo, type WifiNote, type WifiStatus } from '@mafia/protocol';
import { pushTo } from './hub.ts';
import { sendPush, type PushKind } from './push.ts';
import { refreshTitles } from './stats.ts';
import { ApiErr, body, card, DAY, HOUR, sha256, type AppEnv, type Deps, type Env, type UserRow } from './lib.ts';

export interface WifiRules { version: number; minPlayers: number; maxPlayers: number; minSecondsPerRound: number; maxAgeDays: number; perHostPerDay: number; confirmHours: number }
const FALLBACK: WifiRules = { version: 1, minPlayers: 4, maxPlayers: 20, minSecondsPerRound: 60, maxAgeDays: 7, perHostPerDay: 10, confirmHours: 48 };
export const RESULT_TTL = 30 * DAY;  // a decided request stays in the host's bell this long (N8)

export async function wifiRules(db: D1Database): Promise<WifiRules> {
  const r = await db.prepare("SELECT value FROM settings WHERE key = 'wifi_rules'").first<{ value: string }>();
  return { ...FALLBACK, ...(r ? JSON.parse(r.value) : {}) };
}

interface ReqRow { id: string; host_id: string | null; record: string; record_hash: string; game_key: string; played_at: number; status: WifiStatus; reason: string | null; created_at: number; expires_at: number; decided_at: number | null; game_id: string | null; host_seen: number }
interface SeatRow { request_id: string; seat: number; user_id: string | null; name: string; answer: string | null; seen: number }

/** What a stored record says, read defensively (it's kept raw). */
function sum(raw: string, seat: number | null) {
  try {
    const r = JSON.parse(raw) as GameRecord;
    return { players: r.names.length, winner: r.winner ?? null, role: seat == null ? null : (r.roles[seat] as Role) ?? null };
  } catch { return { players: 0, winner: null, role: null }; }
}
const note = (r: ReqRow, seat: number | null): WifiNote => ({ request: r.id, status: r.status, reason: r.reason, playedAt: r.played_at, seat, ...sum(r.record, seat) });

/** The checks, in order; the first failure is the reason. Seats were already shape-checked by WifiRequestIn. */
async function judge(env: Env, me: UserRow, rec: GameRecord, seats: { seat: number; userId: string; name: string }[], rules: WifiRules, hash: string, now: number) {
  const x = replay(rec);
  if (!x.ok || !x.state.winner) return { reason: 'replay' as const };
  const s = x.state, n = s.names.length;
  const bySeat = new Map(seats.map(p => [p.seat, p]));
  if (seats.length !== n || bySeat.size !== n || s.names.some((name, i) => bySeat.get(i)?.name !== name)) return { reason: 'seats' as const };
  const ids = new Set(seats.map(p => p.userId));
  if (ids.size !== n || !ids.has(me.id)) return { reason: 'seats' as const };
  const known = await env.DB.prepare(`SELECT COUNT(*) AS n FROM users WHERE id IN (${seats.map(() => '?').join(',')})`).bind(...ids).first<{ n: number }>();
  if (known?.n !== n) return { reason: 'seats' as const };
  if (n < rules.minPlayers || n > rules.maxPlayers) return { reason: 'players' as const };
  const first = rec.actions[0]?.at ?? 0, last = rec.actions.at(-1)?.at ?? 0;
  if ((last - first) / 1000 < rules.minSecondsPerRound * s.day) return { reason: 'short' as const };
  if (last > now + 10 * 60e3 || now - last > rules.maxAgeDays * DAY) return { reason: 'old' as const };
  const dup = await env.DB.prepare("SELECT 1 FROM wifi_requests WHERE record_hash = ? AND status IN ('pending', 'approved')").bind(hash).first();
  if (dup) return { reason: 'dup' as const };
  return { reason: null, state: s, playedAt: last };
}

export const wifiRoutes = new Hono<AppEnv>();
/** The host asks. Answers { id, status, reason }: 'rejected' with the failed check, or 'pending' (now confirming). */
wifiRoutes.post('/', async c => {
  const inp = await body(c, WifiRequestIn), db = c.env.DB, me = c.var.user, now = c.var.deps.now(), rules = await wifiRules(db);
  // the daily limit is checked before anything is kept (it is the one thing that stops a phone filling the table)
  const today = await db.prepare('SELECT COUNT(*) AS n FROM wifi_requests WHERE host_id = ? AND created_at > ?').bind(me.id, now - DAY).first<{ n: number }>();
  if ((today?.n ?? 0) >= rules.perHostPerDay) throw new ApiErr(429, 'slow_down');
  const raw = JSON.stringify(inp.record), hash = await sha256(raw), id = crypto.randomUUID();
  const j = await judge(c.env, me, inp.record as unknown as GameRecord, inp.seats, rules, hash, now);
  const status: WifiStatus = j.reason ? 'rejected' : 'pending', expires = now + rules.confirmHours * HOUR;
  const playedAt = j.reason ? (inp.record as unknown as GameRecord).actions?.at?.(-1)?.at ?? now : j.playedAt!;
  await db.batch([
    // a rejection never shows in the host's bell (host_seen 2): the app shows the reason at once
    db.prepare(`INSERT INTO wifi_requests (id, host_id, record, record_hash, game_key, app_version, played_at, rules_version, status, reason, created_at, expires_at, decided_at, host_seen)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .bind(id, me.id, raw, hash, inp.key, inp.app ?? '', Number.isFinite(playedAt) ? playedAt : now, rules.version, status, j.reason, now, expires, j.reason ? now : null, j.reason ? 2 : 0),
    ...inp.seats.map(p => db.prepare('INSERT INTO wifi_seats (request_id, seat, user_id, name, answer, answered_at) VALUES (?, ?, (SELECT id FROM users WHERE id = ?), ?, ?, ?)')
      .bind(id, p.seat, p.userId, p.name, p.userId === me.id ? 'yes' : null, p.userId === me.id ? now : null)),
  ]);
  if (!j.reason) {
    const r = (await db.prepare('SELECT * FROM wifi_requests WHERE id = ?').bind(id).first<ReqRow>())!;
    await Promise.all(inp.seats.filter(p => p.userId !== me.id).map(p => tell(c.env, c.var.deps, p.userId, me, 'wifi_confirm', r, p.seat)));
  }
  return c.json({ id, status, reason: j.reason });
});

/** A player answers: Confirm (yes) or Not me (no). The last "yes" approves; any "no" declines. */
wifiRoutes.post('/:id/answer', async c => {
  const { yes } = await body(c, WifiAnswer), db = c.env.DB, me = c.var.user, now = c.var.deps.now(), id = c.req.param('id');
  await expire(c.env, c.var.deps, now);
  const r = await db.prepare('SELECT * FROM wifi_requests WHERE id = ?').bind(id).first<ReqRow>();
  const seat = r && await db.prepare('SELECT * FROM wifi_seats WHERE request_id = ? AND user_id = ?').bind(id, me.id).first<SeatRow>();
  if (!r || !seat) throw new ApiErr(404, 'not_found');
  if (r.status !== 'pending') return c.json({ status: r.status });
  const set = await db.prepare('UPDATE wifi_seats SET answer = ?, answered_at = ?, seen = 1 WHERE request_id = ? AND user_id = ? AND answer IS NULL')
    .bind(yes ? 'yes' : 'no', now, id, me.id).run();
  if (!set.meta.changes) return c.json({ status: r.status });  // answered already (a repeat tap)
  if (!yes) return c.json({ status: await decide(c.env, c.var.deps, r, 'declined', now) });
  const left = await db.prepare("SELECT COUNT(*) AS n FROM wifi_seats WHERE request_id = ? AND (answer IS NULL OR answer <> 'yes')").bind(id).first<{ n: number }>();
  if ((left?.n ?? 1) > 0) return c.json({ status: 'pending' });
  return c.json({ status: await decide(c.env, c.var.deps, r, 'approved', now) });
});

/** History → Wi-Fi: my requests as host (with progress) and approved games I played in. */
wifiRoutes.get('/', async c => {
  const db = c.env.DB, me = c.var.user, now = c.var.deps.now();
  await expire(c.env, c.var.deps, now);
  const { results } = await db.prepare(
    `SELECT r.*, s.seat AS my_seat,
            (SELECT COUNT(*) FROM wifi_seats q WHERE q.request_id = r.id AND q.answer IS NULL) AS waiting,
            (SELECT COUNT(*) FROM wifi_seats q WHERE q.request_id = r.id) AS total FROM wifi_requests r JOIN wifi_seats s ON s.request_id = r.id AND s.user_id = ?1
     WHERE (r.host_id = ?1 AND r.status <> 'rejected') OR r.status = 'approved'
     ORDER BY r.played_at DESC LIMIT 100`).bind(me.id).all<ReqRow & { my_seat: number; waiting: number; total: number }>();
  const games: WifiGameInfo[] = results.map(r => {
    const n = note(r, r.my_seat);
    return { id: r.id, key: r.game_key, status: r.status, reason: r.reason, playedAt: r.played_at, players: n.players, winner: n.winner,
      host: r.host_id === me.id, waiting: r.waiting, total: r.total, gameId: r.game_id, seat: r.my_seat, role: n.role,
      record: r.status === 'approved' ? JSON.parse(r.record) : null };
  });
  return c.json({ games });
});

/** approved / declined / expired: once (the status only leaves 'pending' once); the host is told. */
async function decide(env: Env, deps: Deps, r: ReqRow, to: 'approved' | 'declined' | 'expired', now: number): Promise<WifiStatus> {
  const db = env.DB, steps: D1PreparedStatement[] = [];
  const gameId = to === 'approved' ? 'w-' + r.id : null;
  steps.push(db.prepare("UPDATE wifi_requests SET status = ?, reason = ?, decided_at = ?, game_id = ? WHERE id = ? AND status = 'pending'")
    .bind(to, to === 'approved' ? null : to === 'declined' ? 'not_me' : 'expired', now, null, r.id));
  if (gameId) {
    const x = replay(JSON.parse(r.record) as GameRecord);
    if (!x.ok) return 'pending';  // judged at request time; unreachable unless the engine changed under it
    const s = x.state, { results: seats } = await db.prepare('SELECT seat, user_id, name FROM wifi_seats WHERE request_id = ? ORDER BY seat').bind(r.id).all<SeatRow>();
    steps.push(
      db.prepare(`INSERT INTO games (id, host_id, winner, days, valid, rules, log, stats, played_at, record, source)
                  SELECT ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, 'wifi' WHERE changes() > 0 ON CONFLICT DO NOTHING`)
        .bind(gameId, r.host_id, s.winner, s.day, JSON.stringify(s.rules), JSON.stringify(s.log), JSON.stringify(s.stats), r.played_at, r.record),
      ...seats.map(p => db.prepare(`INSERT INTO game_players (game_id, seat, user_id, name, role, alive)
                                    SELECT ?, ?, (SELECT id FROM users WHERE id = ?), ?, ?, ? WHERE EXISTS (SELECT 1 FROM games WHERE id = ?) ON CONFLICT DO NOTHING`)
        .bind(gameId, p.seat, p.user_id, s.names[p.seat], s.roles[p.seat], s.alive[p.seat] ? 1 : 0, gameId)),
      db.prepare('UPDATE wifi_requests SET game_id = ? WHERE id = ? AND EXISTS (SELECT 1 FROM games WHERE id = ?)').bind(gameId, r.id, gameId),
    );
  }
  const res = await db.batch(steps);
  if (!res[0].meta.changes) return (await db.prepare('SELECT status FROM wifi_requests WHERE id = ?').bind(r.id).first<{ status: WifiStatus }>())?.status ?? to;
  if (r.host_id) {
    const host = await db.prepare('SELECT * FROM users WHERE id = ?').bind(r.host_id).first<UserRow>();
    const fresh = (await db.prepare('SELECT * FROM wifi_requests WHERE id = ?').bind(r.id).first<ReqRow>())!;
    const hs = await db.prepare('SELECT seat FROM wifi_seats WHERE request_id = ? AND user_id = ?').bind(r.id, r.host_id).first<{ seat: number }>();
    if (host) await tell(env, deps, host.id, host, to, fresh, hs?.seat ?? null);
  }
  if (to === 'approved') await refreshTitles(env, deps);
  return to;
}

/** Requests past their window become 'expired' (called on reads and by the hourly cron). */
export async function expire(env: Env, deps: Deps, now: number) {
  const { results } = await env.DB.prepare("SELECT * FROM wifi_requests WHERE status = 'pending' AND expires_at <= ? LIMIT 50").bind(now).all<ReqRow>();
  for (const r of results) await decide(env, deps, r, 'expired', now);
}

/** A bell item (live if the app is open, else a push). kind: wifi_confirm to a player, or the result to the host. */
async function tell(env: Env, deps: Deps, to: string, from: UserRow, kind: 'wifi_confirm' | 'approved' | 'declined' | 'expired', r: ReqRow, seat: number | null) {
  const n: Notification = { id: 'w:' + r.id, kind: kind === 'wifi_confirm' ? 'wifi_confirm' : 'wifi_result', from: card(from, 'none'), code: null,
    at: kind === 'wifi_confirm' ? r.created_at : r.decided_at ?? r.created_at, expiresAt: kind === 'wifi_confirm' ? r.expires_at : (r.decided_at ?? 0) + RESULT_TTL,
    read: false, wifi: note(r, seat) };
  const open = await pushTo(env, to, { t: 'note', note: n });
  if (!open) await sendPush(env, deps, to, kind as PushKind, { name: from.display, tag: 'wifi:' + r.id, data: { id: n.id } });
}

/** The Wi-Fi items of someone's bell: confirmations waiting for me, and my decided requests. */
export async function wifiNotes(db: D1Database, uid: string, now: number): Promise<Notification[]> {
  const { results: asks } = await db.prepare(
    `SELECT r.*, s.seat AS my_seat, s.seen AS my_seen, u.id AS uid FROM wifi_seats s JOIN wifi_requests r ON r.id = s.request_id
     LEFT JOIN users u ON u.id = r.host_id
     WHERE s.user_id = ? AND s.answer IS NULL AND r.status = 'pending' AND r.expires_at > ? ORDER BY r.created_at DESC LIMIT 20`)
    .bind(uid, now).all<ReqRow & { my_seat: number; my_seen: number }>();
  const { results: done } = await db.prepare(
    `SELECT r.*, (SELECT seat FROM wifi_seats s WHERE s.request_id = r.id AND s.user_id = ?1) AS my_seat FROM wifi_requests r
     WHERE r.host_id = ?1 AND r.status IN ('approved', 'declined', 'expired') AND r.host_seen < 2 AND r.decided_at > ?2 ORDER BY r.decided_at DESC LIMIT 20`)
    .bind(uid, now - RESULT_TTL).all<ReqRow & { my_seat: number | null }>();
  const ids = [...new Set([...asks.map(a => a.host_id), uid].filter((x): x is string => !!x))];
  const { results: users } = await db.prepare(`SELECT * FROM users WHERE id IN (${ids.map(() => '?').join(',')})`).bind(...ids).all<UserRow>();
  const byId = new Map(users.map(u => [u.id, u])), gone: UserRow = { id: '', handle: null, display: '?', avatar_preset: 0, avatar_ver: 0, fav_role: '', show_online: 0, created_at: 0 };
  return [
    ...asks.map(r => ({ id: 'w:' + r.id, kind: 'wifi_confirm' as const, from: card(byId.get(r.host_id ?? '') ?? gone, 'none'), code: null, at: r.created_at,
      expiresAt: r.expires_at, read: !!r.my_seen, wifi: note(r, r.my_seat) })),
    ...done.map(r => ({ id: 'w:' + r.id, kind: 'wifi_result' as const, from: card(byId.get(uid) ?? gone, 'none'), code: null, at: r.decided_at!,
      expiresAt: r.decided_at! + RESULT_TTL, read: r.host_seen > 0, wifi: note(r, r.my_seat) })),
  ];
}

/** Marks Wi-Fi bell items read (ids 'w:<request>'; none = all of them). */
export async function readWifi(db: D1Database, uid: string, ids: string[] | undefined) {
  const req = ids?.filter(i => i.startsWith('w:')).map(i => i.slice(2));
  if (req && !req.length) return;
  const where = req ? ` AND request_id IN (${req.map(() => '?').join(',')})` : '', where2 = req ? ` AND id IN (${req.map(() => '?').join(',')})` : '';
  await db.batch([
    db.prepare(`UPDATE wifi_seats SET seen = 1 WHERE user_id = ?${where}`).bind(uid, ...(req ?? [])),
    db.prepare(`UPDATE wifi_requests SET host_seen = 1 WHERE host_id = ? AND host_seen = 0 AND status <> 'pending'${where2}`).bind(uid, ...(req ?? [])),
  ]);
}
/** Dismisses decided results from the bell (a confirmation can't be dismissed, only answered). */
export async function dismissWifi(db: D1Database, uid: string, id: string | null) {
  await db.prepare(`UPDATE wifi_requests SET host_seen = 2 WHERE host_id = ? AND status <> 'pending'${id ? ' AND id = ?' : ''}`).bind(...(id ? [uid, id] : [uid])).run();
}
