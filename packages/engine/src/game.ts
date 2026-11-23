// The game as a state machine: apply(state, action) -> new state + events. Ported 1:1 from the app's
// game/night.ts, day.ts, end.ts and mp/hostGame.ts (the host's checks on players' messages included).
import type { Action, Ctx, GameEvent, GameState, LogEvent, NightChoice, NightOptions, Result, TallyLine, Winner } from './types.ts';

export const aliveSeats = (s: GameState) => s.alive.map((a, i) => (a ? i : -1)).filter(i => i >= 0);
const seatOk = (s: GameState, i: unknown): i is number => Number.isInteger(i) && (i as number) >= 0 && (i as number) < s.names.length;

/** What seat p may pick tonight (the target buttons). */
export function nightOptions(s: GameState, p: number): NightOptions {
  const r = s.roles[p], R = s.rules, key = r === 'citizen' && !R.decoy ? 'none' : r;
  const res: NightOptions = { key, opts: [], skip: null };
  if (key === 'none') return res;
  const mates = (pred: (v: NightChoice) => boolean) => Object.entries(s.night.mafia).filter(([k, v]) => +k !== p && pred(v)).length;
  for (const j of aliveSeats(s)) {
    const o = { seat: j, disabled: false, self: j === p, teammate: false, lastTarget: false, lastNight: false, mateVotes: 0 };
    if (r === 'mafia' && s.roles[j] === 'mafia') { o.disabled = true; o.teammate = j !== p; }
    if (r === 'mafia' && R.norep && s.lastTarget === j) { o.disabled = true; o.lastTarget = true; }
    if (r === 'doctor') {
      if (j === p && !R.self) o.disabled = true;
      if (R.rep && s.lastProt[p] === j) { o.disabled = true; o.lastNight = true; }
    }
    if (r === 'detective' && j === p) o.disabled = true;
    if (r === 'mafia') o.mateVotes = mates(v => v === j);
    res.opts.push(o);
  }
  if (r === 'mafia' && R.skip && !s.skipUsed) res.skip = { mateVotes: mates(v => v === 'skip') };
  return res;
}

/** Winner when the Mafia are all gone, or as many as everyone else. */
function winnerOf(s: GameState): Winner | null {
  const a = aliveSeats(s), m = a.filter(i => s.roles[i] === 'mafia').length;
  return m === 0 ? 'citizens' : m >= a.length - m ? 'mafia' : null;
}

/** Applies an action. Never changes the given state. */
export function apply(prev: GameState, a: Action, ctx: Ctx): Result<{ state: GameState; events: GameEvent[] }> {
  const s: GameState = JSON.parse(JSON.stringify(prev)), ev: GameEvent[] = [];
  const fail = (error: string) => ({ ok: false as const, error });
  const phase = (p: GameState['phase']) => { s.phase = p; ev.push({ t: 'phase', phase: p, day: s.day }); };
  const log = (e: LogEvent) => { s.log.push(e); ev.push(e); };
  const pauseTimer = () => { s.timer = { running: false, left: timerLeft(s, ctx.now), at: 0 }; };
  const startNight = () => {
    s.night = { mafia: {}, doctor: {}, detective: {}, done: {}, endsAt: s.rules.nightT ? ctx.now + s.rules.nightT * 1000 : 0 };
    s.morning = null; s.verdict = null; s.vote = null;
    phase('night');
  };
  const checkWin = (lead: { k: 'killed' | 'votedOut'; seat: number } | null) => {
    const w = winnerOf(s); if (!w) return false;
    pauseTimer(); s.winner = w; log({ t: 'win', winner: w, lead }); phase('end'); return true;
  };

  const resolveNight = () => {
    // the Mafia's decision: the most votes among the living Mafia; a tie kills nobody (tieSkip) or, in older games, is
    // broken at random. A tie never spends the one-time skip.
    const votes = Object.values(s.night.mafia); let target: number | null = null, skip = false;
    if (votes.length) {
      const c: Record<string, number> = {}; votes.forEach(v => { c[String(v)] = (c[String(v)] || 0) + 1; });
      const max = Math.max(...Object.values(c)), top = Object.keys(c).filter(k => c[k] === max);
      const w = top.length > 1 && s.rules.tieSkip ? null : top[Math.floor(ctx.rng() * top.length)];
      if (w === 'skip') { skip = true; s.skipUsed = true; } else if (w != null) target = +w;
    }
    const doc = Object.entries(s.night.doctor).filter(([, q]) => q != null) as [string, number][];
    const prot = new Set(doc.map(([, q]) => q));
    s.lastProt = { ...s.night.doctor };
    const saved = target != null && prot.has(target), dead = target != null && !saved ? target : null;
    if (dead != null) s.alive[dead] = false;
    log({ t: 'night', day: s.day, mafia: skip ? { k: 'skip' } : target == null ? { k: 'none' } : saved ? { k: 'saved', seat: target } : { k: 'kill', seat: target },
      prot: doc.map(([, q]) => q), checked: Object.values(s.night.detective).filter((q): q is number => q != null) });
    s.lastTarget = target;
    if (saved) doc.forEach(([p, q]) => { if (q === target) s.stats.saves.push(+p); });
    if (dead != null) { if (s.stats.first == null) s.stats.first = dead; s.stats.kills.push(dead); }
    for (const [p, q] of Object.entries(s.night.detective)) {
      if (q != null && s.roles[q] === 'mafia' && !s.stats.caught.some(([x, y]) => x === +p && y === q)) s.stats.caught.push([+p, q]);
    }
    s.morning = { dead, saved: saved && s.rules.saverev ? target : null };
    if (checkWin(dead != null ? { k: 'killed', seat: dead } : null)) return;
    phase('morning');
  };

  const verdict = (out: number | null, kind: 'out' | 'skipped' | 'tie', tally: TallyLine[] | null) => {
    pauseTimer();
    if (out != null) { s.alive[out] = false; s.stats.outs.push(out); }
    s.verdict = { out, kind, tally };
    log({ t: 'day', day: s.day, out, kind, tally });
    if (checkWin(out != null ? { k: 'votedOut', seat: out } : null)) return;
    phase('verdict');
  };
  const tally = () => {
    const c: Record<string, number> = {};
    Object.values(s.vote!.votes).filter(v => v !== 'abstain' && v != null && (s.rules.skipVote || v !== 'none')).forEach(v => { c[String(v)] = (c[String(v)] || 0) + 1; });
    if (!Object.keys(c).length) return verdict(null, 'skipped', []);
    const max = Math.max(...Object.values(c)), top = Object.keys(c).filter(k => c[k] === max);
    const lines: TallyLine[] = Object.entries(c).sort((x, y) => y[1] - x[1]).map(([k, n]) => ({ k: k === 'none' ? 'none' : +k, n }));
    if (top.length > 1) verdict(null, 'tie', lines); else if (top[0] === 'none') verdict(null, 'skipped', lines); else verdict(+top[0], 'out', lines);
  };
  /** Moves on once everyone alive has acted or voted. */
  const settle = () => {
    if (s.phase === 'night' && aliveSeats(s).every(i => s.night.done[i])) resolveNight();
    else if (s.phase === 'vote' && aliveSeats(s).every(i => s.vote!.votes[i] !== undefined)) tally();
  };

  switch (a.t) {
    case 'begin':
      if (s.phase !== 'deal') return fail('phase');
      startNight(); break;

    case 'night': {
      if (s.phase !== 'night') return fail('phase');
      if (a.day != null && a.day !== s.day) return fail('stale');
      if (!seatOk(s, a.seat)) return fail('seat');
      if (!s.alive[a.seat]) return fail('dead');
      if (s.night.done[a.seat]) return fail('done');
      const no = nightOptions(s, a.seat);
      const ok = no.key === 'none' || (a.choice === 'skip' ? !!no.skip : no.opts.some(o => o.seat === a.choice && !o.disabled));
      if (!ok) return fail('choice');
      const r = s.roles[a.seat];
      if (r === 'mafia') s.night.mafia[a.seat] = a.choice;
      if (r === 'doctor') s.night.doctor[a.seat] = a.choice as number;
      if (r === 'detective') s.night.detective[a.seat] = a.choice as number;
      s.night.done[a.seat] = true;
      settle(); break;
    }

    case 'skipPending': {  // "Continue anyway" for offline players, or the night timer ran out (no seats = everyone pending)
      if (s.phase !== 'night' && s.phase !== 'vote') return fail('phase');
      const seats = a.seats ?? aliveSeats(s);
      if (!seats.every(i => seatOk(s, i))) return fail('seat');
      for (const i of seats) {
        if (!s.alive[i]) continue;
        if (s.phase === 'night') s.night.done[i] = true;
        else if (s.vote!.votes[i] === undefined) s.vote!.votes[i] = 'abstain';
      }
      if (s.phase === 'night' && !a.seats) s.night.endsAt = 0;
      settle(); break;
    }

    case 'startDay':
      if (s.phase !== 'morning') return fail('phase');
      s.timer = { running: false, left: s.rules.timer, at: 0 };
      phase('day'); break;

    case 'timer':
      if (s.phase !== 'day') return fail('phase');
      if (a.op === 'start') { if (!s.timer.running) s.timer = { running: true, left: s.timer.left, at: ctx.now }; }
      else if (a.op === 'pause') pauseTimer();
      else if (a.op === 'reset') s.timer = { running: false, left: s.rules.timer, at: 0 };
      else if (a.op === 'add') {
        if (!Number.isFinite(a.sec) || a.sec <= 0 || a.sec > 3600) return fail('choice');
        s.timer = { running: s.timer.running, left: timerLeft(s, ctx.now) + a.sec, at: s.timer.running ? ctx.now : 0 };
      } else return fail('unknown');
      break;

    case 'startVote':
      if (s.phase !== 'day') return fail('phase');
      pauseTimer();
      s.vote = { id: ctx.now, open: !!a.open, votes: {} };
      phase('vote'); break;

    case 'vote': {
      if (s.phase !== 'vote') return fail('phase');
      if (a.id != null && a.id !== s.vote!.id) return fail('stale');
      if (!seatOk(s, a.seat)) return fail('seat');
      if (!s.alive[a.seat]) return fail('dead');
      if (s.vote!.votes[a.seat] !== undefined) return fail('done');
      if (!(a.choice === 'none' || (seatOk(s, a.choice) && s.alive[a.choice] && a.choice !== a.seat))) return fail('choice');
      s.vote!.votes[a.seat] = a.choice;
      settle(); break;
    }

    case 'decide':  // the table decides together (one phone)
      if (s.phase !== 'day') return fail('phase');
      if (!(a.choice === 'none' || (seatOk(s, a.choice) && s.alive[a.choice]))) return fail('choice');
      verdict(a.choice === 'none' ? null : a.choice, a.choice === 'none' ? 'skipped' : 'out', null); break;

    case 'nextNight':
      if (s.phase !== 'verdict') return fail('phase');
      s.day++; startNight(); break;

    case 'remove':  // the host removes a player mid-game: counts as an elimination
      if (s.phase === 'deal' || s.phase === 'end') return fail('phase');
      if (!seatOk(s, a.seat)) return fail('seat');
      if (!s.alive[a.seat]) return fail('dead');
      s.alive[a.seat] = false;
      if (s.vote) delete s.vote.votes[a.seat];
      s.night.done[a.seat] = true;
      log({ t: 'removed', seat: a.seat });
      // a removal can decide the game (the last Mafia, or the Mafia reach parity): it ends at once
      if (!checkWin(null)) settle();
      break;

    default: return fail('unknown');
  }
  return { ok: true, state: s, events: ev };
}

/** Seconds left on the discussion timer at `now`. */
export function timerLeft(s: GameState, now: number) {
  const t = s.timer;
  return t.running ? Math.max(0, t.left - Math.floor((now - t.at) / 1000)) : t.left;
}
