// What each seat may see (replaces the app's mpPriv), and the player of the game.
import { aliveSeats, checkedBefore, nightOptions, timerLeft } from './game.ts';
import type { GameState, Mode, NightOptions, Role, Stats, TallyLine, Winner } from './types.ts';

/** The public result on screen in the morning / after a verdict. role only when the reveal rule is on. */
export type Result =
  // also: a second death; sheikh: the revealed role is the Godfather's (his ruling: named on reveal) (1.0.0)
  | { k: 'killed'; seat: number; role: Role | null; sheikh?: true; also?: { seat: number; role: Role | null; sheikh?: true } }
  | { k: 'saved'; seat: number }
  | { k: 'nobody' }
  | { k: 'out'; seat: number; role: Role | null; sheikh?: true; tally: TallyLine[] | null }
  | { k: 'tie' | 'skipped'; tally: TallyLine[] | null };

export interface Recap { winner: Winner; names: string[]; roles: Role[]; alive: boolean[]; day: number; stats: Stats; mode?: Mode; sheikh?: number }

/** What everyone may see: the table (host screen) and every phone get at least this. */
export interface PublicView {
  deal: number; phase: GameState['phase']; day: number;
  roster: { name: string; alive: boolean }[];
  timer: { end: number } | { left: number } | null;   // night timer end, or the discussion timer
  progress: { done: number; total: number } | null;  // night turns / votes in so far
  board: { seat: number; v: number | 'none' | 'abstain' | null }[] | null;  // open (table) vote only
  voteId: number | null;
  result: Result | null;
  winner: Winner | null;
  roles: Role[] | null;    // at the end only (and for ghosts, in SeatView)
  recap: Recap | null;
}

export type SeatView = PublicView & {
  seat: number; role: Role; alive: boolean;
  mates: number[];                                  // the other Mafia (Mafia only)
  sheikh: number | null;                            // the Sheikh's seat (Mafia only; may be this seat)
  check: { seat: number; mafia: boolean } | null;   // the Detective's result, until the next night
  checks: { seat: number; mafia: boolean }[] | null;  // 1.1.0, Detective: every result so far (his role card)
  ph: 'night' | 'nightDone' | 'vote' | 'voted' | 'dead' | 'table' | 'end';
  night: NightOptions | null;                       // ph 'night': what to pick
  voteOpts: { seat: number; disabled: boolean }[] | null;  // ph 'vote' ('no one' is always allowed)
};

function publicView(s: GameState, now: number): PublicView {
  const al = aliveSeats(s), R = s.rules;
  const timer = s.phase === 'night' && s.night.endsAt ? { end: s.night.endsAt }
    : s.phase === 'day' ? (s.timer.running ? { end: s.timer.at + s.timer.left * 1000 } : { left: timerLeft(s, now) }) : null;
  const progress = s.phase === 'night' ? { done: al.filter(i => s.night.done[i]).length, total: al.length }
    : s.phase === 'vote' ? { done: al.filter(i => s.vote!.votes[i] !== undefined).length, total: al.length } : null;
  let result: Result | null = null;
  const sh = (i: number) => (R.reveal && i === s.sheikh ? { sheikh: true as const } : {});  // the Godfather, named on reveal
  if (s.phase === 'morning' && s.morning) {
    const d = s.morning.dead, d2 = s.morning.dead2;
    result = d != null ? { k: 'killed', seat: d, role: R.reveal ? s.roles[d] : null, ...sh(d), ...(d2 != null ? { also: { seat: d2, role: R.reveal ? s.roles[d2] : null, ...sh(d2) } } : {}) }
      : s.morning.saved != null ? { k: 'saved', seat: s.morning.saved } : { k: 'nobody' };
  } else if (s.phase === 'verdict' && s.verdict) {
    const v = s.verdict;
    result = v.out != null ? { k: 'out', seat: v.out, role: R.reveal ? s.roles[v.out] : null, ...sh(v.out), tally: v.tally } : { k: v.kind === 'tie' ? 'tie' : 'skipped', tally: v.tally };
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
      ...(s.sheikh !== undefined ? { mode: s.mode ?? 'classic', sheikh: s.sheikh } : {}) } : null,
  };
}

/** What one seat's phone may show. 'table' = only the public part (the host screen, spectators). */
export function viewFor(s: GameState, who: number | 'table', now: number): PublicView | SeatView {
  const pub = publicView(s, now);
  if (who === 'table') return pub;
  const i = who, r = s.roles[i], q = r === 'detective' ? s.night.detective[i] : null;
  const v: SeatView = {
    ...pub, seat: i, role: r, alive: s.alive[i],
    mates: r === 'mafia' ? s.roles.map((x, j) => (x === 'mafia' && j !== i ? j : -1)).filter(j => j >= 0) : [],
    sheikh: r === 'mafia' && s.sheikh !== undefined ? s.sheikh : null,
    check: q != null ? { seat: q, mafia: s.roles[q] === 'mafia' && q !== s.sheikh } : null,  // the Sheikh reads "not Mafia"
    checks: s.rv !== undefined && r === 'detective' ? [...checkedBefore(s)].map(j => ({ seat: j, mafia: s.roles[j] === 'mafia' && j !== s.sheikh })) : null,
    ph: 'table', night: null, voteOpts: null,
  };
  if (s.phase === 'end') v.ph = 'end';
  else if (!s.alive[i]) { v.ph = 'dead'; if (s.rules.ghost) v.roles = s.roles.slice(); }
  else if (s.phase === 'night') { if (s.night.done[i]) v.ph = 'nightDone'; else { v.ph = 'night'; v.night = nightOptions(s, i); } }
  else if (s.phase === 'vote') {
    if (s.vote!.votes[i] !== undefined) v.ph = 'voted';
    else { v.ph = 'vote'; v.voteOpts = aliveSeats(s).map(j => ({ seat: j, disabled: j === i })); }
  }
  return v;
}

/** Player of the game, with the reason (the app writes the text). */
export function mvp(g: { winner: Winner; roles: Role[]; alive: boolean[]; stats: Stats }):
  { seat: number; why: 'mafia' | 'mafia2' | 'det' | 'doc' | 'guard' | 'surv' | 'jester'; n?: number } | null {
  const idx = g.roles.map((_, i) => i);
  if (g.winner === 'jester') { const j = idx.find(i => g.roles[i] === 'jester'); return j == null ? null : { seat: j, why: 'jester' }; }
  const top = (a: number[]) => { const c: Record<string, number> = {}; a.forEach(x => { c[x] = (c[x] || 0) + 1; }); return Object.entries(c).sort((x, y) => y[1] - x[1])[0]; };
  if (g.winner === 'mafia') { const m = idx.filter(i => g.roles[i] === 'mafia'), al = m.filter(i => g.alive[i]); return { seat: (al.length ? al : m)[0], why: al.length ? 'mafia' : 'mafia2' }; }
  const c = top(g.stats.caught.map(([d]) => d)); if (c) return { seat: +c[0], why: 'det', n: c[1] };
  const d = top(g.stats.saves); if (d) return { seat: +d[0], why: 'doc', n: d[1] };
  const b = top((g.stats.guards ?? []).map(([x]) => x)); if (b) return { seat: +b[0], why: 'guard', n: b[1] };
  const sv = idx.filter(i => g.alive[i] && g.roles[i] !== 'mafia' && g.roles[i] !== 'jester');
  return sv.length ? { seat: sv[0], why: 'surv' } : null;
}
