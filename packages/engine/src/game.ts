// The game as a state machine: apply(state, action) -> new state + events. Ported 1:1 from the app's
// game/night.ts, day.ts, end.ts and mp/hostGame.ts (the host's checks on players' messages included).
import type { Action, Ctx, GameEvent, GameState, LogEvent, NightChoice, NightOptions, Result, TallyLine, Winner } from './types.ts';

export const aliveSeats = (s: GameState) => s.alive.map((a, i) => (a ? i : -1)).filter(i => i >= 0);
const seatOk = (s: GameState, i: unknown): i is number => Number.isInteger(i) && (i as number) >= 0 && (i as number) < s.names.length;

/** What seat p may pick tonight (the target buttons). */
export function nightOptions(s: GameState, p: number): NightOptions {
  const r = s.roles[p], R = s.rules, rv = s.rv !== undefined;
  // the Jester, and the Sniper once his bullet is spent (1.1.0: or on night 1), pick like a Citizen
  const k0 = r === 'jester' || (r === 'sniper' && (s.shotUsed || (rv && s.day === 1))) ? 'citizen' : r, key = k0 === 'citizen' && !R.decoy ? 'none' : k0;
  const res: NightOptions = { key, opts: [], skip: null };
  if (key === 'none') return res;
  const mates = (pred: (v: NightChoice) => boolean) => Object.entries(s.night.mafia).filter(([k, v]) => +k !== p && pred(v)).length;
  const past = rv && r === 'detective' ? checkedBefore(s) : null;  // 1.1.0: never the same player twice
  const sh = s.sheikh, shPick = r === 'mafia' && sh !== undefined && sh !== p && s.alive[sh] ? s.night.mafia[sh] : undefined;
  for (const j of aliveSeats(s)) {
    const o = { seat: j, disabled: false, self: j === p, teammate: false, lastTarget: false, lastNight: false, mateVotes: 0, sheikh: shPick === j };
    if (r === 'mafia' && s.roles[j] === 'mafia') { o.disabled = true; o.teammate = j !== p; }
    if (r === 'mafia' && R.norep && s.lastTarget === j) { o.disabled = true; o.lastTarget = true; }
    if (r === 'doctor') {
      if (j === p && !R.self) o.disabled = true;
      if (R.rep && s.lastProt[p] === j) { o.disabled = true; o.lastNight = true; }
    }
    if ((key === 'detective' || key === 'sniper' || key === 'bodyguard') && j === p) o.disabled = true;
    if (key === 'bodyguard' && s.lastGuard?.[p] === j) { o.disabled = true; o.lastNight = true; }
    if (past?.has(j)) Object.assign(o, { disabled: true, check: s.roles[j] === 'mafia' && j !== s.sheikh });
    if (r === 'mafia') o.mateVotes = mates(v => v === j);
    res.opts.push(o);
  }
  if (r === 'mafia' && R.skip && !s.skipUsed) res.skip = { mateVotes: mates(v => v === 'skip'), sheikh: shPick === 'skip' };
  if (key === 'sniper') res.skip = { mateVotes: 0, sheikh: false };  // keep the bullet
  // everyone else is already checked: nothing to pick tonight
  if (past && res.opts.every(o => o.disabled)) return { key: 'none', opts: [], skip: null };
  return res;
}

/** 1.1.0: the players the Detectives checked on earlier nights. */
export const checkedBefore = (s: GameState) => new Set(s.log.flatMap(e => (e.t === 'night' ? e.checked : [])));

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
  const checkWin = (lead: { k: 'killed' | 'votedOut'; seat: number } | null, forced: Winner | null = null) => {
    const w = forced ?? winnerOf(s); if (!w) return false;
    pauseTimer(); s.winner = w; log({ t: 'win', winner: w, lead }); phase('end'); return true;
  };

  const resolveNight = () => {
    // the Mafia's decision: the most votes among the living Mafia. A tie (1.0.0) goes to the Sheikh's pick, even one
    // nobody else made; with no pick from him (out, or didn't vote) to the lowest seat that voted for a tied pick.
    // Older games: a tie kills nobody (tieSkip, without spending the skip) or, before Sprint 7, a random pick.
    // 1.0.0: only the living count (a Mafia or the Sniper removed mid-night after choosing has no say)
    const live = ([k]: [string, unknown]) => s.sheikh === undefined || s.alive[+k];
    const votes = Object.entries(s.night.mafia).filter(live); let target: number | null = null, skip = false;
    if (votes.length) {
      const c: Record<string, number> = {}; votes.forEach(([, v]) => { c[String(v)] = (c[String(v)] || 0) + 1; });
      const max = Math.max(...Object.values(c)), top = Object.keys(c).filter(k => c[k] === max);
      let w: string | null;
      if (s.sheikh === undefined) w = top.length > 1 && s.rules.tieSkip ? null : top[Math.floor(ctx.rng() * top.length)];
      else if (top.length === 1) w = top[0];
      else {
        const sv = s.alive[s.sheikh] ? s.night.mafia[s.sheikh] : undefined;
        w = sv != null ? String(sv) : String(votes.filter(([, v]) => top.includes(String(v))).sort((x, y) => +x[0] - +y[0])[0][1]);
      }
      if (w === 'skip') { skip = true; s.skipUsed = true; } else if (w != null) target = +w;
    }
    // the Sniper's one bullet: nothing stops it, not even the Doctor
    const sn = Object.entries(s.night.sniper ?? {}).filter(live).find(([, v]) => v !== 'skip'), aim = sn ? (sn[1] as number) : null;
    // 1.1.0, the Bodyguard: a kill or a shot at the player he guards goes to him instead (then the Doctor's save is
    // looked at for him; a bullet nobody stops)
    const bg = s.rv !== undefined && s.roles.includes('bodyguard'), guards = bg ? Object.entries(s.night.bodyguard ?? {}).filter(live) : [];
    const cover = (t: number | null) => {
      const g = t == null || !s.alive[t] ? undefined : guards.find(([b, q]) => q === t && +b !== t);  // [Quin Q3] not for a removed player
      if (!g) return t;
      const pair: [number, number] = [+g[0], t!], gs = (s.stats.guards ??= []);
      if (!gs.some(([x, y], i) => i >= took && x === pair[0] && y === pair[1])) gs.push(pair);
      return +g[0];
    };
    const took = s.stats.guards?.length ?? 0, victim = cover(target), shot = cover(aim);
    const doc = Object.entries(s.night.doctor).filter(([, q]) => q != null) as [string, number][];
    const prot = new Set(doc.map(([, q]) => q));
    s.lastProt = { ...s.night.doctor };
    if (bg) s.lastGuard = { ...(s.night.bodyguard ?? {}) };
    const saved = victim != null && prot.has(victim), dead = victim != null && !saved ? victim : null;
    const kept = saved && shot !== victim;  // a save the Sniper didn't undo
    if (dead != null) s.alive[dead] = false;
    if (shot != null) { s.alive[shot] = false; s.shotUsed = true; (s.stats.shots ??= []).push([+sn![0], shot]); }
    log({ t: 'night', day: s.day, mafia: skip ? { k: 'skip' } : victim == null ? { k: 'none' } : saved ? { k: 'saved', seat: victim } : { k: 'kill', seat: victim },
      prot: doc.map(([, q]) => q), checked: Object.values(s.night.detective).filter((q): q is number => q != null), ...(shot != null ? { shot } : {}),
      ...(bg ? { guard: guards.map(([, q]) => q).filter((q): q is number => q != null) } : {}) });
    s.lastTarget = target;
    if (kept) doc.forEach(([p, q]) => { if (q === victim) s.stats.saves.push(+p); });
    if (dead != null) { if (s.stats.first == null) s.stats.first = dead; s.stats.kills.push(dead); }
    for (const [p, q] of Object.entries(s.night.detective)) {
      if (q != null && s.roles[q] === 'mafia' && q !== s.sheikh && !s.stats.caught.some(([x, y]) => x === +p && y === q)) s.stats.caught.push([+p, q]);
    }
    // the morning names the dead in seat order: nobody can tell which death was the Sniper's
    const deaths = [...new Set([dead, shot].filter((x): x is number => x != null))].sort((x, y) => x - y);
    // [Quin Q2, B15] "Reveal saves" names the Mafia's target, never the Bodyguard who took the kill
    s.morning = { dead: deaths[0] ?? null, saved: kept && s.rules.saverev ? target : null, ...(s.sheikh !== undefined ? { dead2: deaths[1] ?? null } : {}) };
    // the death that decides the game leads its announcement: a Mafia shot by the Sniper when the town wins
    const lead = deaths.find(x => s.roles[x] === 'mafia' && !aliveSeats(s).some(i => s.roles[i] === 'mafia')) ?? dead ?? shot;
    if (checkWin(lead != null ? { k: 'killed', seat: lead } : null)) return;
    phase('morning');
  };

  const verdict = (out: number | null, kind: 'out' | 'skipped' | 'tie', tally: TallyLine[] | null) => {
    pauseTimer();
    if (out != null) { s.alive[out] = false; s.stats.outs.push(out); }
    s.verdict = { out, kind, tally };
    log({ t: 'day', day: s.day, out, kind, tally });
    // the Jester wins alone when the day vote puts him out
    if (checkWin(out != null ? { k: 'votedOut', seat: out } : null, out != null && s.roles[out] === 'jester' ? 'jester' : null)) return;
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
      // [Quin Q1] 1.1.0: "nothing to pick" takes no pick (older records sent anything there)
      const ok = no.key === 'none' ? s.rv === undefined || a.choice == null : a.choice === 'skip' ? !!no.skip : no.opts.some(o => o.seat === a.choice && !o.disabled);
      if (!ok) return fail('choice');
      const r = s.roles[a.seat];
      if (r === 'mafia') s.night.mafia[a.seat] = a.choice;
      if (r === 'doctor') s.night.doctor[a.seat] = a.choice as number;
      if (r === 'detective') s.night.detective[a.seat] = a.choice as number;
      if (no.key === 'sniper') (s.night.sniper ??= {})[a.seat] = a.choice as number | 'skip';
      if (r === 'bodyguard') (s.night.bodyguard ??= {})[a.seat] = a.choice as number | null;
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
