// Stats (S8-1, S8-2): the old app's titles, leaderboard and player profile, with the same rules, over three sources:
// online games, Wi-Fi games approved into online history, and games imported from the old app. Valid games only.
// "Mine" = the games I played in (and the old games I imported); "Everyone" = all accounts, server-vouched games only
// (online + approved Wi-Fi), 10-game minimum, opted-in accounts.
import { Hono } from 'hono';
import { nameKey, type Role } from '@mafia/engine';
import type { Notification } from '@mafia/protocol';
import { pushTo } from './hub.ts';
import { sendPush } from './push.ts';
import { ApiErr, avatarOf, card, DAY, type AppEnv, type Deps, type Env, type UserRow } from './lib.ts';

export interface SSeat { key: string; userId: string | null; name: string; role: Role; alive: boolean }
export interface SGame {
  id: string; source: 'online' | 'wifi' | 'old'; playedAt: number; winner: 'mafia' | 'citizens'; days: number; seats: SSeat[];
  ev: { first: number | null; kills: number[]; outs: number[]; saves: number[]; caught: number[] };  // caught: detective seats
}
export interface PlayerStat { key: string; userId: string | null; name: string; g: number; w: number; mg: number; mw: number; tg: number; tw: number; sv: number; ct: number; fk: number; q: boolean; r: number }
export type TitleKey = 'best' | 'mafia' | 'det' | 'doc' | 'first';

const won = (g: SGame, i: number) => (g.seats[i].role === 'mafia' ? g.winner === 'mafia' : g.winner === 'citizens');
export const userKey = (id: string) => 'u:' + id;
export const nameKeyOf = (n: string) => 'n:' + nameKey(n);

/** The old app's stats(): totals per player, the board (ranked by win rate with a minimum, then wins, then games), titles. */
export function board(games: SGame[], minGames: number, keep: (p: PlayerStat) => boolean = () => true) {
  const P = new Map<string, PlayerStat>();
  for (const g of games) g.seats.forEach((s, i) => {
    let p = P.get(s.key);
    if (!p) P.set(s.key, p = { key: s.key, userId: s.userId, name: s.name, g: 0, w: 0, mg: 0, mw: 0, tg: 0, tw: 0, sv: 0, ct: 0, fk: 0, q: false, r: 0 });
    const w = won(g, i);
    p.g++; if (w) p.w++;
    if (s.role === 'mafia') { p.mg++; if (w) p.mw++; } else { p.tg++; if (w) p.tw++; }
    if (g.ev.first === i) p.fk++;
    p.sv += g.ev.saves.filter(x => x === i).length;
    p.ct += g.ev.caught.filter(x => x === i).length;
  });
  const all = [...P.values()].filter(keep);
  for (const p of all) { p.q = p.g >= minGames; p.r = p.w / p.g; }
  const ranked = all.slice().sort((a, b) => (+b.q - +a.q) || (b.r - a.r) || (b.w - a.w) || (b.g - a.g));
  const top = (f: (p: PlayerStat) => number) => all.filter(p => f(p) > 0).sort((a, b) => f(b) - f(a))[0] ?? null;
  const bestMafia = all.filter(p => p.mg >= 2 && p.mw > 0).sort((a, b) => (b.mw / b.mg - a.mw / a.mg) || (b.mw - a.mw))[0] ?? null;
  const titles: Record<TitleKey, PlayerStat | null> = {
    best: ranked.find(p => p.q) ?? null, mafia: bestMafia, det: top(p => p.ct), doc: top(p => p.sv), first: top(p => p.fk),
  };
  return { ranked, titles };
}

/** The old app's profileView(), plus the best partner (the Mafia teammate you win with most). */
export function profile(games: SGame[], key: string) {
  const mine = games.filter(g => g.seats.some(s => s.key === key)).sort((a, b) => b.playedAt - a.playedAt);
  const R: Record<Role, [number, number]> = { mafia: [0, 0], doctor: [0, 0], detective: [0, 0], citizen: [0, 0] };
  const by = new Map<string, { name: string; userId: string | null; n: number }>(), mates = new Map<string, { name: string; userId: string | null; n: number }>();
  let w = 0, sv = 0, ct = 0, kd = 0, vo = 0;
  const form: boolean[] = [];
  const bump = (m: typeof by, s: SSeat) => { const x = m.get(s.key) ?? { name: s.name, userId: s.userId, n: 0 }; x.n++; m.set(s.key, x); };
  for (const g of mine) {
    const i = g.seats.findIndex(s => s.key === key), r = g.seats[i].role, x = won(g, i);
    R[r][0]++; if (x) { R[r][1]++; w++; }
    if (form.length < 8) form.push(x);
    sv += g.ev.saves.filter(q => q === i).length;
    ct += g.ev.caught.filter(q => q === i).length;
    vo += g.ev.outs.filter(q => q === i).length;
    for (const q of g.ev.kills) if (q === i) { kd++; g.seats.forEach((s, j) => { if (s.role === 'mafia' && j !== i) bump(by, s); }); }
    if (r === 'mafia' && x) g.seats.forEach((s, j) => { if (s.role === 'mafia' && j !== i) bump(mates, s); });
  }
  const roles = Object.keys(R) as Role[];
  const best = roles.filter(r => R[r][0] >= 2).sort((a, b) => (R[b][1] / R[b][0] - R[a][1] / R[a][0]) || (R[b][0] - R[a][0]))[0]
    ?? roles.slice().sort((a, b) => R[b][0] - R[a][0])[0];
  const side = (['doctor', 'detective', 'citizen'] as const).reduce((a, r) => [a[0] + R[r][0], a[1] + R[r][1]], [0, 0]);
  const most = (m: typeof by) => [...m.values()].sort((a, b) => b.n - a.n)[0] ?? null;
  const seat = mine[0]?.seats.find(s => s.key === key);
  return {
    key, name: seat?.name ?? '', userId: seat?.userId ?? null, games: mine.length, wins: w, best, roles: R,
    mafia: R.mafia, side, nemesis: most(by), partner: most(mates), moments: { saves: sv, caught: ct, killed: kd, out: vo }, form,
  };
}

// ---------------------------------------------------------------- loading the games
interface GRow { id: string; source: string; played_at: number; winner: 'mafia' | 'citizens'; days: number; stats: string }
interface PRow { game_id: string; seat: number; user_id: string | null; name: string; role: Role; alive: number }

/** Online / Wi-Fi games from `games`: all of them (Everyone) or the ones `uid` played in. Valid only. */
async function onlineGames(db: D1Database, uid: string | null, since: number): Promise<SGame[]> {
  const where = `g.valid = 1 AND g.played_at >= ?1${uid ? ' AND g.id IN (SELECT game_id FROM game_players WHERE user_id = ?2)' : ''}`;
  // ponytail: Everyone reads every valid game on each request; materialize per-player totals when games reach the thousands
  const [{ results: gs }, { results: ps }] = await Promise.all([
    db.prepare(`SELECT g.id, g.source, g.played_at, g.winner, g.days, g.stats FROM games g WHERE ${where}`).bind(...(uid ? [since, uid] : [since])).all<GRow>(),
    db.prepare(`SELECT p.game_id, p.seat, p.user_id, p.name, p.role, p.alive FROM game_players p JOIN games g ON g.id = p.game_id WHERE ${where} ORDER BY p.seat`)
      .bind(...(uid ? [since, uid] : [since])).all<PRow>(),
  ]);
  const seats = new Map<string, PRow[]>();
  for (const p of ps) (seats.get(p.game_id) ?? seats.set(p.game_id, []).get(p.game_id)!).push(p);
  return gs.map(g => {
    const st = JSON.parse(g.stats) as { first: number | null; kills: number[]; outs: number[]; saves: number[]; caught: [number, number][] };
    return { id: g.id, source: g.source === 'wifi' ? 'wifi' : 'online', playedAt: g.played_at, winner: g.winner, days: g.days,
      seats: (seats.get(g.id) ?? []).map(p => ({ key: p.user_id ? userKey(p.user_id) : nameKeyOf(p.name), userId: p.user_id, name: p.name, role: p.role, alive: !!p.alive })),
      ev: { first: st.first, kills: st.kills ?? [], outs: st.outs ?? [], saves: st.saves ?? [], caught: (st.caught ?? []).map(c => c[0]) } };
  });
}

/** Old names → accounts: the names claimed in the app ("Which one were you?"), then the settings list (handle or id). */
export async function oldNameOwners(db: D1Database) {
  const own = new Map<string, string>();
  const row = await db.prepare("SELECT value FROM settings WHERE key = 'old_players'").first<{ value: string }>();
  const names = (row ? JSON.parse(row.value).names : {}) as Record<string, string | null>;
  const wanted = Object.entries(names).filter(([, v]) => !!v) as [string, string][];
  if (wanted.length) {
    const { results } = await db.prepare(`SELECT id, handle FROM users WHERE id IN (${wanted.map(() => '?').join(',')}) OR handle IN (${wanted.map(() => '?').join(',')})`)
      .bind(...wanted.map(([, v]) => v), ...wanted.map(([, v]) => v.replace(/^@/, ''))).all<{ id: string; handle: string | null }>();
    for (const [n, v] of wanted) { const u = results.find(x => x.id === v || (x.handle && x.handle.toLowerCase() === v.replace(/^@/, '').toLowerCase())); if (u) own.set(nameKey(n), u.id); }
  }
  const { results: claims } = await db.prepare('SELECT name_key, user_id FROM legacy_claims').all<{ name_key: string; user_id: string }>();
  for (const c of claims) own.set(c.name_key, c.user_id);
  return { own, list: Object.keys(names) };
}

/** Old games I imported, or played in under a name that is mine. Valid only. */
async function oldGames(db: D1Database, uid: string, since: number): Promise<SGame[]> {
  const { own } = await oldNameOwners(db);
  const myNames = [...own].filter(([, u]) => u === uid).map(([k]) => k);
  const { results: gs } = await db.prepare(
    `SELECT id, raw, played_at, winner, days FROM legacy_games WHERE valid = 1 AND played_at >= ? AND (importer_id = ?${myNames.length ? ` OR id IN (SELECT game_id FROM legacy_seats WHERE name_key IN (${myNames.map(() => '?').join(',')}))` : ''})`)
    .bind(since, uid, ...myNames).all<{ id: string; raw: string; played_at: number; winner: 'mafia' | 'citizens'; days: number }>();
  return gs.map(g => fromOld(g.id, JSON.parse(g.raw), g.played_at, own));
}

/** An old app LogEntry as a stats game (its seats owned by an account when the name is someone's). */
export function fromOld(id: string, o: { names: string[]; roles: Role[]; alive: boolean[]; winner: 'mafia' | 'citizens'; days: number; ev?: { first?: number | null; saves?: number[]; caught?: string[]; kills?: number[]; outs?: number[] } }, playedAt: number, own: Map<string, string>): SGame {
  const ev = o.ev ?? {};
  return { id, source: 'old', playedAt, winner: o.winner, days: o.days,
    seats: o.names.map((name, i) => { const u = own.get(nameKey(name)) ?? null; return { key: u ? userKey(u) : nameKeyOf(name), userId: u, name, role: o.roles[i], alive: !!o.alive[i] }; }),
    ev: { first: ev.first ?? null, kills: ev.kills ?? [], outs: ev.outs ?? [], saves: ev.saves ?? [], caught: (ev.caught ?? []).map(x => +String(x).split(':')[0]) } };
}

export const EVERYONE_MIN = 10, MINE_MIN = 3, EVERYONE_TOP = 100;

/** The games a board is built from. */
async function gamesFor(env: Env, uid: string, scope: 'mine' | 'all', source: string, days: number, now: number) {
  const since = days > 0 ? now - days * DAY : 0;
  let games = scope === 'all' ? await onlineGames(env.DB, null, since)
    : [...await onlineGames(env.DB, uid, since), ...(source === 'all' || source === 'old' ? await oldGames(env.DB, uid, since) : [])];
  if (source !== 'all') games = games.filter(g => g.source === source);
  return games;
}

const shownOnBoard = (users: Map<string, UserRow>, id: string | null) => {
  const u = id ? users.get(id) as (UserRow & { on_board: number }) | undefined : undefined;
  return !!u && !u.banned_at && u.on_board === 1;
};

/** Account cards for the board's accounts (Everyone: only those who show themselves, never banned). */
async function people(db: D1Database, ids: string[]) {
  if (!ids.length) return new Map<string, UserRow>();
  const { results } = await db.prepare(`SELECT * FROM users WHERE id IN (${ids.map(() => '?').join(',')})`).bind(...ids).all<UserRow & { on_board: number }>();
  return new Map(results.map(u => [u.id, u]));
}

export const statsRoutes = new Hono<AppEnv>();
const Q = (c: { req: { query(k: string): string | undefined } }) => {
  const scope = c.req.query('board') === 'all' ? 'all' as const : 'mine' as const;
  const source = ['online', 'wifi', 'old'].includes(c.req.query('source') ?? '') ? c.req.query('source')! : 'all';
  const days = c.req.query('days') === '30' ? 30 : 0;
  return { scope, source: scope === 'all' && source === 'old' ? 'all' : source, days };
};

/** GET /v1/stats?board=mine|all&source=all|online|wifi|old&days=0|30 */
statsRoutes.get('/', async c => {
  const { scope, source, days } = Q(c), me = c.var.user, now = c.var.deps.now();
  const games = await gamesFor(c.env, me.id, scope, source, days, now);
  const min = scope === 'all' ? EVERYONE_MIN : MINE_MIN;
  const ids = [...new Set(games.flatMap(g => g.seats.map(s => s.userId)).filter((x): x is string => !!x))];
  const users = await people(c.env.DB, ids);
  // Everyone: accounts only, opted in, never banned (titles go to the best of those)
  const { ranked, titles } = board(games, min, scope === 'all' ? p => shownOnBoard(users, p.userId) : undefined);
  const out = (p: PlayerStat, rank: number | null) => {
    const u = p.userId ? users.get(p.userId) : undefined;
    return { ...p, rank, name: u?.display ?? p.name, handle: u?.handle ?? null, avatar: u ? avatarOf(u) : null, me: p.userId === me.id };
  };
  // equal records share a rank (1, 1, 1, 4), [QA] S8 #5: identical players were numbered in an arbitrary order
  let pos = 0, rk = 0, prev: PlayerStat | null = null;
  const rows = ranked.map(p => {
    if (!p.q) return out(p, null);
    pos++;
    if (!prev || prev.r !== p.r || prev.w !== p.w || prev.g !== p.g) rk = pos;
    prev = p;
    return out(p, rk);
  });
  const mine = rows.find(r => r.me) ?? null;
  return c.json({
    board: scope === 'all' ? rows.slice(0, EVERYONE_TOP) : rows, me: mine, minGames: min, games: games.length,
    titles: Object.fromEntries((Object.keys(titles) as TitleKey[]).map(k => [k, titles[k] ? out(titles[k]!, null) : null])),
  });
});

/** GET /v1/stats/player?key=u:<id>|n:<name>&board&source&days: a player's profile within that board's games. */
statsRoutes.get('/player', async c => {
  const { scope, source, days } = Q(c), key = c.req.query('key') ?? '', me = c.var.user;
  if (!/^(u|n):.{1,64}$/.test(key)) throw new ApiErr(400, 'bad_request');
  const p = profile(await gamesFor(c.env, me.id, scope, source, days, c.var.deps.now()), key);
  if (!p.games) throw new ApiErr(404, 'not_found');
  const ids = [p.userId, p.nemesis?.userId, p.partner?.userId].filter((x): x is string => !!x);
  const users = await people(c.env.DB, ids);
  const named = (x: { name: string; userId: string | null; n: number } | null) => x && { ...x, name: (x.userId && users.get(x.userId)?.display) || x.name };
  const u = p.userId ? users.get(p.userId) : undefined;
  return c.json({ ...p, name: u?.display ?? p.name, card: u ? card(u, 'none') : null, nemesis: named(p.nemesis), partner: named(p.partner) });
});

// ---------------------------------------------------------------- P4: a title taken from you (Everyone board)
const TITLE_NAMES: Record<TitleKey, string> = { best: 'Best player', mafia: 'Best Mafia', det: 'Best Detective', doc: 'Best Doctor', first: 'Most killed first' };
export const TITLE_NOTE_TTL = 7 * DAY;

/** After a game counts (or stops counting): works out the Everyone titles and tells anyone who lost one. */
export async function refreshTitles(env: Env, deps: Pick<Deps, 'push' | 'now'>) {
  try {
    const games = await onlineGames(env.DB, null, 0);
    const users = await people(env.DB, [...new Set(games.flatMap(g => g.seats.map(s => s.userId)).filter((x): x is string => !!x))]);
    const { titles } = board(games, EVERYONE_MIN, p => shownOnBoard(users, p.userId));
    const now = Object.fromEntries((Object.keys(titles) as TitleKey[]).map(k => [k, titles[k]?.userId ?? null])) as Record<TitleKey, string | null>;
    const row = await env.DB.prepare("SELECT value FROM settings WHERE key = 'titles'").first<{ value: string }>();
    const before = (row ? JSON.parse(row.value) : {}) as Record<string, string | null>;
    await env.DB.prepare("INSERT INTO settings (key, value, updated_at) VALUES ('titles', ?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at")
      .bind(JSON.stringify(now), deps.now()).run();
    for (const k of Object.keys(now) as TitleKey[]) {
      const lost = before[k], won = now[k];
      if (!lost || !won || lost === won) continue;
      const by = (await env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(won).first<UserRow>())!;
      const id = crypto.randomUUID(), at = deps.now();
      await env.DB.prepare('INSERT INTO bell_notes (id, user_id, kind, data, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)')
        .bind(id, lost, 'title_lost', JSON.stringify({ title: k, by: won }), at, at + TITLE_NOTE_TTL).run();
      const note: Notification = { id: 'b:' + id, kind: 'title_lost', from: card(by, 'none'), code: null, at, expiresAt: at + TITLE_NOTE_TTL, read: false, title: k };
      if (!(await pushTo(env, lost, { t: 'note', note })))
        await sendPush(env, deps as Deps, lost, 'title_lost', { name: by.display, code: TITLE_NAMES[k], tag: 'title:' + k, data: { id: note.id, title: k } });
    }
  } catch (e) { console.error('titles', e); }  // a title note never fails the game that caused it
}

/** The bell's other notes (titles taken), for the bell list. */
export async function bellNotes(db: D1Database, uid: string, now: number): Promise<Notification[]> {
  const { results } = await db.prepare('SELECT * FROM bell_notes WHERE user_id = ? AND expires_at > ? ORDER BY created_at DESC LIMIT 20').bind(uid, now)
    .all<{ id: string; kind: string; data: string; created_at: number; expires_at: number; read_at: number | null }>();
  const data = results.map(r => ({ r, d: JSON.parse(r.data) as { title: TitleKey; by: string } }));
  const users = await people(db, [...new Set(data.map(x => x.d.by))]);
  const gone: UserRow = { id: '', handle: null, display: '?', avatar_preset: 0, avatar_ver: 0, fav_role: '', show_online: 0, created_at: 0 };
  return data.map(({ r, d }) => ({ id: 'b:' + r.id, kind: 'title_lost' as const, from: card(users.get(d.by) ?? gone, 'none'), code: null, at: r.created_at, expiresAt: r.expires_at, read: r.read_at != null, title: d.title }));
}
export async function readBell(db: D1Database, uid: string, ids: string[] | undefined, now: number) {
  const b = ids?.filter(i => i.startsWith('b:')).map(i => i.slice(2));
  if (b && !b.length) return;
  await db.prepare(`UPDATE bell_notes SET read_at = ? WHERE user_id = ? AND read_at IS NULL${b ? ` AND id IN (${b.map(() => '?').join(',')})` : ''}`).bind(now, uid, ...(b ?? [])).run();
}
export async function dismissBell(db: D1Database, uid: string, id: string | null) {
  await db.prepare(`DELETE FROM bell_notes WHERE user_id = ?${id ? ' AND id = ?' : ''}`).bind(...(id ? [uid, id] : [uid])).run();
}
