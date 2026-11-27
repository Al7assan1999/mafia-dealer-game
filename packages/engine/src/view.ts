// What each seat may see (replaces the app's mpPriv), and the player of the game.
import { aliveSeats, nightOptions, readsOf, timerLeft } from './game.ts';
import type { GameState, Mode, NightOptions, Role, Stats, TallyLine, Winner } from './types.ts';

/** The public result on screen in the morning / after a verdict. role only when the reveal rule is on. */
export type Result =
  // also: a second death; sheikh: the revealed role is the Godfather's (his ruling: named on reveal) (1.0.0)
  // framer (1.3.0, Quin Q13): the revealed Mafia was the Framer
  // 1.4.0: more (a third death and on), hearts (who died of a broken heart), in games with the Serial Killer or Cupid
  | { k: 'killed'; seat: number; role: Role | null; sheikh?: true; framer?: true; silencer?: true; also?: Shown; more?: Shown[]; hearts?: Shown[] }
  | { k: 'saved'; seat: number }
  | { k: 'nobody' }
  | { k: 'out'; seat: number; role: Role | null; sheikh?: true; framer?: true; silencer?: true; tally: TallyLine[] | null; hearts?: Shown[] }
  | { k: 'tie' | 'skipped'; tally: TallyLine[] | null };
/** One death on screen: the seat, and its role with the reveal rule */
export type Shown = { seat: number; role: Role | null; sheikh?: true; framer?: true };

export interface Recap { winner: Winner; names: string[]; roles: Role[]; alive: boolean[]; day: number; stats: Stats; mode?: Mode; sheikh?: number; framer?: number;
  silencer?: number }

/** What everyone may see: the table (host screen) and every phone get at least this. */
export interface PublicView {
  deal: number; phase: GameState['phase']; day: number;
  roster: { name: string; alive: boolean }[];
  timer: { end: number } | { left: number } | null;   // night timer end, or the discussion timer
  progress: { done: number; total: number } | null;  // night turns / votes in so far
  board: { seat: number; v: number | 'none' | 'abstain' | null }[] | null;  // open (table) vote only; every vote for an out seat (1.1.1)
  voteId: number | null;
  result: Result | null;
  winner: Winner | null;
  roles: Role[] | null;    // at the end only (and for ghosts, in SeatView)
  recap: Recap | null;
  // 1.3.0, only in games with the role: the revealed Mayors; the Hunter taking aim (ends: the timer); his shot, while
  // its morning or verdict is on screen (role only with the reveal rule)
  mayors?: number[];
  hunt?: { seat: number } | null;
  hunted?: { by: number; seat: number | null; role: Role | null; sheikh?: true; framer?: true; silencer?: true; hearts?: Shown[] } | null;
  silenced?: number | null;   // 1.4.0, games with the Silencer: who can't vote today (public, R8)
}

export type SeatView = PublicView & {
  seat: number; role: Role; alive: boolean;
  mates: number[];                                  // the other Mafia (Mafia only)
  sheikh: number | null;                            // the Sheikh's seat (Mafia only; may be this seat)
  check: { seat: number; mafia: boolean } | null;   // the Detective's result, until the next night
  checks: { seat: number; mafia: boolean }[] | null;  // 1.1.0, Detective: every result so far (his role card)
  ph: 'night' | 'nightDone' | 'vote' | 'voted' | 'dead' | 'table' | 'end' | 'hunt';  // hunt: 1.3.0, this dead Hunter aims
  framer?: number | null;                           // 1.3.0: the Framer's seat (Mafia only; may be this seat)
  framed?: { seat: number; hit: boolean } | null;   // 1.3.0, the Framer: last night's frame, and whether a Detective checked it (R4)
  watch?: { seat: number; visitors: number[] }[] | null;  // 1.3.0, the Watcher: every result so far, the last one last
  huntOpts?: number[] | null;                       // ph 'hunt': who he may shoot
  silencer?: number | null;                         // 1.4.0: the Silencer's seat (Mafia only; may be this seat)
  lover?: { seat: number; side: 'mafia' | 'town' } | null;  // 1.4.0, a lover: the partner and their side (R4)
  night: NightOptions | null;                       // ph 'night': what to pick
  voteOpts: { seat: number; disabled: boolean }[] | null;  // ph 'vote' ('no one' is always allowed)
};

function publicView(s: GameState, now: number): PublicView {
  const al = aliveSeats(s), R = s.rules;
  const timer = s.hunt?.endsAt ? { end: s.hunt.endsAt } : s.phase === 'night' && s.night.endsAt ? { end: s.night.endsAt }
    : s.phase === 'day' ? (s.timer.running ? { end: s.timer.at + s.timer.left * 1000 } : { left: timerLeft(s, now) }) : null;
  const progress = s.phase === 'night' ? { done: al.filter(i => s.night.done[i]).length, total: al.length }
    : s.phase === 'vote' ? { done: al.filter(i => s.vote!.votes[i] !== undefined).length, total: al.length } : null;
  let result: Result | null = null;
  const sh = (i: number) => flags(s, i), shown = (i: number) => shownOf(s, i);
  if (s.phase === 'morning' && s.morning) {
    const d = s.morning.dead, d2 = s.morning.dead2, more = (s.morning.deaths ?? []).slice(2), hearts = s.morning.hearts ?? [];
    result = d != null ? { k: 'killed', seat: d, role: R.reveal ? s.roles[d] : null, ...sh(d), ...(d2 != null ? { also: shown(d2) } : {}),
      ...(more.length ? { more: more.map(shown) } : {}), ...(hearts.length ? { hearts: hearts.map(shown) } : {}) }
      : s.morning.saved != null ? { k: 'saved', seat: s.morning.saved } : { k: 'nobody' };
  } else if (s.phase === 'verdict' && s.verdict) {
    const v = s.verdict, dl = [...s.log].reverse().find(e => e.t === 'day'), hearts = dl?.t === 'day' ? dl.hearts ?? [] : [];
    result = v.out != null ? { k: 'out', seat: v.out, role: R.reveal ? s.roles[v.out] : null, ...sh(v.out), tally: v.tally, ...(hearts.length ? { hearts: hearts.map(shown) } : {}) }
      : { k: v.kind === 'tie' ? 'tie' : 'skipped', tally: v.tally };
  }
  const end = s.phase === 'end';
  return {
    deal: s.deal, phase: s.phase, day: s.day,
    roster: s.names.map((name, i) => ({ name, alive: s.alive[i] })),
    timer, progress,
    board: s.phase === 'vote' && s.vote!.open ? al.map(k => ({ seat: k, v: s.vote!.votes[k] ?? null })) : null,
    voteId: s.phase === 'vote' ? s.vote!.id : null,
    result, winner: s.winner,
    roles: end ? s.roles.slice() : null,
    recap: end ? { winner: s.winner!, names: s.names, roles: s.roles, alive: s.alive, day: s.day, stats: s.stats,
      ...(s.sheikh !== undefined ? { mode: s.mode ?? 'classic', sheikh: s.sheikh } : {}), ...(s.framer !== undefined ? { framer: s.framer } : {}),
      ...(s.silencer !== undefined ? { silencer: s.silencer } : {}) } : null,
    ...newRoles(s),
  };
}

/** The Godfather (the Framer, [Quin Q10] the Silencer), named on reveal. */
function flags(s: GameState, i: number): { sheikh?: true; framer?: true; silencer?: true } {
  return !s.rules.reveal ? {} : i === s.sheikh ? { sheikh: true } : i === s.framer ? { framer: true } : i === s.silencer ? { silencer: true } : {};
}
/** One death on screen: the seat, and its role and flags with the reveal rule. */
const shownOf = (s: GameState, i: number): Shown => ({ seat: i, role: s.rules.reveal ? s.roles[i] : null, ...flags(s, i) });

/** 1.3.0: the public part of the new roles, only in games that have them (older games' views stay as they were). */
function newRoles(s: GameState): Partial<PublicView> {
  const o: Partial<PublicView> = {};
  if (s.roles.includes('mayor')) o.mayors = [...(s.mayors ?? [])];
  if (s.roles.includes('hunter')) {
    o.hunt = s.hunt ? { seat: s.hunt.seat } : null;
    const h = s.log.find(e => e.t === 'hunt');
    o.hunted = h?.t === 'hunt' && h.day === s.day && ((s.phase === 'morning' && h.from === 'night') || (s.phase === 'verdict' && h.from === 'day'))
      ? { by: h.seat, seat: h.target, role: h.target != null && s.rules.reveal ? s.roles[h.target] : null, ...(h.target != null ? flags(s, h.target) : {}),
        ...(h.hearts?.length ? { hearts: h.hearts.map(x => shownOf(s, x)) } : {}) } : null;
  }
  if (s.silencer !== undefined) o.silenced = s.silenced ?? null;
  return o;
}

/** What one seat's phone may show. 'table' = only the public part (the host screen, spectators). */
export function viewFor(s: GameState, who: number | 'table', now: number): PublicView | SeatView {
  const pub = publicView(s, now);
  if (who === 'table') return pub;
  const i = who, r = s.roles[i], reads = readsOf(s);
  // 1.3.0: with a Framer, tonight's result waits for the morning (the frame may not be in yet), then reads from the log
  const q = r === 'detective' && !(s.framer !== undefined && s.phase === 'night') ? s.night.detective[i] : null;
  const lastNight = [...s.log].reverse().find(e => e.t === 'night');
  const v: SeatView = {
    ...pub, seat: i, role: r, alive: s.alive[i],
    mates: r === 'mafia' ? s.roles.map((x, j) => (x === 'mafia' && j !== i ? j : -1)).filter(j => j >= 0) : [],
    sheikh: r === 'mafia' && s.sheikh !== undefined ? s.sheikh : null,
    check: q != null ? { seat: q, mafia: s.framer !== undefined ? reads.get(q) ?? false : s.roles[q] === 'mafia' && q !== s.sheikh } : null,  // the Sheikh reads "not Mafia"
    checks: s.rv !== undefined && r === 'detective' ? [...reads].map(([j, m]) => ({ seat: j, mafia: m })) : null,
    ph: 'table', night: null, voteOpts: null,
  };
  if (s.framer !== undefined && r === 'mafia') {
    v.framer = s.framer;
    // last night's frame: from the morning until his next night turn is over (pass-and-play shows it on that turn)
    const fresh = lastNight?.t === 'night' && (s.phase === 'night' ? lastNight.day === s.day - 1 : lastNight.day === s.day);
    if (i === s.framer) v.framed = fresh && lastNight?.t === 'night' ? lastNight.frame ?? null : null;
  }
  if (r === 'watcher') v.watch = s.log.flatMap(e => (e.t === 'night' ? (e.watch ?? []).filter(([w]) => w === i).map(([, t, vs]) => ({ seat: t, visitors: vs })) : []));
  if (s.silencer !== undefined && r === 'mafia') v.silencer = s.silencer;
  // 1.4.0: each lover learns the other and their side, once Cupid's night is over (R4)
  const L = s.lovers;
  if (L && L.includes(i)) { const o = L[0] === i ? L[1] : L[0]; v.lover = { seat: o, side: s.roles[o] === 'mafia' ? 'mafia' : 'town' }; }
  if (s.phase === 'end') v.ph = 'end';
  else if (s.hunt?.seat === i) { v.ph = 'hunt'; v.huntOpts = aliveSeats(s).filter(j => j !== i); }  // 1.3.0: no ghost view before his shot (E-H8)
  else if (!s.alive[i]) {
    v.ph = 'dead'; if (s.rules.ghost) v.roles = s.roles.slice();
    // [1.1.1 hotfix] an out player (the host too) follows the vote live, open or secret: they can't vote any more
    if (s.phase === 'vote') v.board = aliveSeats(s).map(k => ({ seat: k, v: s.vote!.votes[k] ?? null }));
  }
  else if (s.phase === 'night') { if (s.night.done[i]) v.ph = 'nightDone'; else { v.ph = 'night'; v.night = nightOptions(s, i); } }
  else if (s.phase === 'vote') {
    if (s.vote!.votes[i] !== undefined) v.ph = 'voted';
    else { v.ph = 'vote'; v.voteOpts = aliveSeats(s).map(j => ({ seat: j, disabled: j === i })); }
  }
  return v;
}

/** Player of the game, with the reason (the app writes the text). */
export function mvp(g: { winner: Winner; roles: Role[]; alive: boolean[]; stats: Stats }):
  { seat: number; why: 'mafia' | 'mafia2' | 'det' | 'doc' | 'guard' | 'hunter' | 'surv' | 'jester' | 'killer' | 'lovers'; n?: number } | null {
  const idx = g.roles.map((_, i) => i);
  if (g.winner === 'jester') { const j = idx.find(i => g.roles[i] === 'jester'); return j == null ? null : { seat: j, why: 'jester' }; }
  // 1.4.0: the Serial Killer's win is his; the Lovers' win goes to the first of the couple; a draw has no player of the game
  if (g.winner === 'killer') { const k = idx.find(i => g.roles[i] === 'killer'); return k == null ? null : { seat: k, why: 'killer' }; }
  if (g.winner === 'lovers') return g.stats.lovers ? { seat: g.stats.lovers[0], why: 'lovers' } : null;
  if (g.winner === 'draw') return null;
  const top = (a: number[]) => { const c: Record<string, number> = {}; a.forEach(x => { c[x] = (c[x] || 0) + 1; }); return Object.entries(c).sort((x, y) => y[1] - x[1])[0]; };
  if (g.winner === 'mafia') { const m = idx.filter(i => g.roles[i] === 'mafia'), al = m.filter(i => g.alive[i]); return { seat: (al.length ? al : m)[0], why: al.length ? 'mafia' : 'mafia2' }; }
  const c = top(g.stats.caught.map(([d]) => d)); if (c) return { seat: +c[0], why: 'det', n: c[1] };
  const d = top(g.stats.saves); if (d) return { seat: +d[0], why: 'doc', n: d[1] };
  const b = top((g.stats.guards ?? []).map(([x]) => x)); if (b) return { seat: +b[0], why: 'guard', n: b[1] };
  const h = (g.stats.hunts ?? []).find(([, t]) => g.roles[t] === 'mafia'); if (h) return { seat: h[0], why: 'hunter' };  // 1.3.0: shot a Mafia
  const sv = idx.filter(i => g.alive[i] && g.roles[i] !== 'mafia' && g.roles[i] !== 'jester');
  return sv.length ? { seat: sv[0], why: 'surv' } : null;
}
