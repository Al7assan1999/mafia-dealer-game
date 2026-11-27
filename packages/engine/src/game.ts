// The game as a state machine: apply(state, action) -> new state + events. Ported 1:1 from the app's
// game/night.ts, day.ts, end.ts and mp/hostGame.ts (the host's checks on players' messages included).
import type { Action, Ctx, GameEvent, GameState, LogEvent, NightChoice, NightOptions, Result, TallyLine, Winner } from './types.ts';

export const aliveSeats = (s: GameState) => s.alive.map((a, i) => (a ? i : -1)).filter(i => i >= 0);
const seatOk = (s: GameState, i: unknown): i is number => Number.isInteger(i) && (i as number) >= 0 && (i as number) < s.names.length;

/** What seat p may pick tonight (the target buttons). */
export function nightOptions(s: GameState, p: number): NightOptions {
  const r = s.roles[p], R = s.rules, rv = s.rv !== undefined;
  // the Jester, and the Sniper once his bullet is spent (1.1.0: or on night 1), pick like a Citizen
  // 1.3.0: the Hunter and the Mayor have no night power either
  // 1.4.0: Cupid links his couple on night 1 only, then picks like a Citizen
  const k0 = r === 'jester' || r === 'hunter' || r === 'mayor' || (r === 'cupid' && s.day !== 1) || (r === 'sniper' && (s.shotUsed || (rv && s.day === 1))) ? 'citizen' : r, key = k0 === 'citizen' && !R.decoy ? 'none' : k0;
  const res: NightOptions = { key, opts: [], skip: null };
  if (r === 'mayor' && !s.mayors?.includes(p)) res.reveal = true;  // pass-and-play: reveal himself in the morning
  if (key === 'none') return res;
  const mates = (pred: (v: NightChoice) => boolean) => Object.entries(s.night.mafia).filter(([k, v]) => +k !== p && pred(v)).length;
  const past = rv && r === 'detective' ? readsOf(s) : null;  // 1.1.0: never the same player twice
  const sh = s.sheikh, shPick = r === 'mafia' && sh !== undefined && sh !== p && s.alive[sh] ? s.night.mafia[sh] : undefined;
  for (const j of aliveSeats(s)) {
    const o = { seat: j, disabled: false, self: j === p, teammate: false, lastTarget: false, lastNight: false, mateVotes: 0, sheikh: shPick === j };
    if (r === 'mafia' && s.roles[j] === 'mafia') { o.disabled = true; o.teammate = j !== p; }
    if (r === 'mafia' && R.norep && s.lastTarget === j) { o.disabled = true; o.lastTarget = true; }
    if (r === 'doctor') {
      if (j === p && !R.self) o.disabled = true;
      if (R.rep && s.lastProt[p] === j) { o.disabled = true; o.lastNight = true; }
    }
    if (r === 'doctor' && s.mayors?.includes(j)) Object.assign(o, { disabled: true, mayor: true });  // 1.3.0: a revealed Mayor
    if ((key === 'detective' || key === 'sniper' || key === 'bodyguard' || key === 'watcher' || key === 'killer') && j === p) o.disabled = true;
    if (key === 'bodyguard' && s.lastGuard?.[p] === j) { o.disabled = true; o.lastNight = true; }
    if (past?.has(j)) Object.assign(o, { disabled: true, check: past.get(j)! });
    if (r === 'mafia') o.mateVotes = mates(v => v === j);
    res.opts.push(o);
  }
  if (r === 'mafia' && R.skip && !s.skipUsed) res.skip = { mateVotes: mates(v => v === 'skip'), sheikh: shPick === 'skip' };
  if (key === 'sniper') res.skip = { mateVotes: 0, sheikh: false };  // keep the bullet
  if (r === 'mafia' && p === s.framer) res.frame = aliveSeats(s).filter(j => s.roles[j] !== 'mafia');  // 1.3.0: never a teammate
  // 1.4.0: the Silencer: anyone but himself and his last pick (teammates too, R8)
  if (r === 'mafia' && p === s.silencer) res.silence = aliveSeats(s).filter(j => j !== p && j !== s.lastSilence);
  // everyone else is already checked: nothing to pick tonight. 1.3.0: the same for any power left with no target (the
  // Doctor with "self" off and "not twice" on, next to a revealed Mayor, found by the every-combination test), so a
  // night can never wait for a pick that can't be made
  if ((past || rv) && res.opts.every(o => o.disabled) && !res.skip) return { key: 'none', opts: [], skip: null, ...(res.reveal ? { reveal: true } : {}) };
  return res;
}

/** 1.1.0: the players the Detectives checked on earlier nights. */
export const checkedBefore = (s: GameState) => new Set(s.log.flatMap(e => (e.t === 'night' ? e.checked : [])));
/** 1.3.0: what each check read (seat → Mafia?). A Framer's game keeps the reads in the log (a framed Citizen read Mafia);
 *  older games work them out from the roles, as before. */
export function readsOf(s: GameState) {
  const m = new Map<number, boolean>();
  for (const e of s.log) if (e.t === 'night') e.checked.forEach((q, k) => m.set(q, e.read ? e.read[k] : s.roles[q] === 'mafia' && q !== s.sheikh));
  return m;
}

/** Winner when the Mafia are all gone, or as many as everyone else. 1.4.0 (his rulings R3, the PRD): a mixed couple who
 *  are the last two win; while the Serial Killer lives nobody else wins: he wins alone or as one of two with a
 *  non-Mafia, and he with one Mafia is a draw; nobody left is a draw. */
export function winnerOf(s: GameState): Winner | null {
  const a = aliveSeats(s), m = a.filter(i => s.roles[i] === 'mafia').length, k = a.filter(i => s.roles[i] === 'killer').length, L = s.lovers;
  if (!a.length) return 'draw';
  if (L && a.length === 2 && a.includes(L[0]) && a.includes(L[1]) && (s.roles[L[0]] === 'mafia') !== (s.roles[L[1]] === 'mafia')) return 'lovers';
  if (k) return a.length === k ? 'killer' : a.length === 2 ? (m ? 'draw' : 'killer') : null;
  return m === 0 ? 'citizens' : m >= a.length - m ? 'mafia' : null;
}

/** Applies an action. Never changes the given state. */
export function apply(prev: GameState, a: Action, ctx: Ctx): Result<{ state: GameState; events: GameEvent[] }> {
  const s: GameState = JSON.parse(JSON.stringify(prev)), ev: GameEvent[] = [];
  const fail = (error: string) => ({ ok: false as const, error });
  const phase = (p: GameState['phase']) => { s.phase = p; ev.push({ t: 'phase', phase: p, day: s.day }); };
  const log = (e: LogEvent) => { s.log.push(e); ev.push(e); };
  const pauseTimer = () => { s.timer = { running: false, left: timerLeft(s, ctx.now), at: 0 }; };
  /** 1.3.0: a Hunter who just died takes aim before the game goes on, unless the town has already won (E-H2). */
  const takeAim = (seats: number[], from: 'night' | 'day') => {
    const h = seats.find(x => s.roles[x] === 'hunter');
    if (h != null && winnerOf(s) !== 'citizens') s.hunt = { seat: h, from, endsAt: s.rules.nightT ? ctx.now + s.rules.nightT * 1000 : 0 };
  };
  /** 1.4.0: a lover just died: the other dies too ("of a broken heart"), once. Returns who did. */
  const heartbreak = (dead: number[]) => {
    const L = s.lovers, out: number[] = [];
    if (L) for (const [x, y] of [[L[0], L[1]], [L[1], L[0]]]) if (dead.includes(x) && s.alive[y]) { s.alive[y] = false; out.push(y); (s.stats.hearts ??= []).push(y); }
    return out;
  };
  const shoot = (target: number | null) => {
    const h = s.hunt!;
    s.hunt = null;
    if (target != null) { s.alive[target] = false; (s.stats.hunts ??= []).push([h.seat, target]); }
    const hearts = target != null ? heartbreak([target]) : [];
    log({ t: 'hunt', day: s.day, seat: h.seat, target, from: h.from, ...(hearts.length ? { hearts } : {}) });
    checkWin(target != null ? { k: 'killed', seat: target } : { k: h.from === 'night' ? 'killed' : 'votedOut', seat: h.seat });
  };
  const startNight = () => {
    s.night = { mafia: {}, doctor: {}, detective: {}, done: {}, endsAt: s.rules.nightT ? ctx.now + s.rules.nightT * 1000 : 0 };
    s.morning = null; s.verdict = null; s.vote = null;
    if (s.silenced !== undefined) s.silenced = null;  // 1.4.0: a silence lasts one day
    phase('night');
  };
  const checkWin = (lead: { k: 'killed' | 'votedOut'; seat: number } | null, forced: Winner | null = null) => {
    const w = forced ?? winnerOf(s); if (!w) return false;
    if (w !== 'citizens' && !forced && s.hunt) return false;  // 1.3.0: the Hunter shoots first (E-H1); 1.4.0 (D9): before any win but the town's
    if (s.hunt) s.hunt = null;
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
    // 1.4.0: the Serial Killer's kill: the Bodyguard covers it and the Doctor saves it, as the Mafia's (R2)
    const kp = Object.entries(s.night.killer ?? {}).filter(live).find(([, v]) => v != null), kaim = kp ? (kp[1] as number) : null;
    const took = s.stats.guards?.length ?? 0, victim = cover(target), shot = cover(aim), kvictim = cover(kaim);
    const doc = Object.entries(s.night.doctor).filter(([, q]) => q != null) as [string, number][];
    const prot = new Set(doc.map(([, q]) => q));
    s.lastProt = { ...s.night.doctor };
    if (bg) s.lastGuard = { ...(s.night.bodyguard ?? {}) };
    const saved = victim != null && prot.has(victim), dead = victim != null && !saved ? victim : null;
    const kept = saved && shot !== victim;  // a save the Sniper didn't undo
    const ksaved = kvictim != null && prot.has(kvictim), kdead = kvictim != null && !ksaved ? kvictim : null, kkept = ksaved && shot !== kvictim && kvictim !== victim;
    // 1.4.0: Cupid's couple (night 1; not if the host removed him) and the Silencer's pick, before anyone dies
    const cu = s.day === 1 ? Object.entries(s.night.cupid ?? {}).find(([c]) => s.alive[+c]) : undefined, link = cu ? cu[1] : null;
    if (link) { s.lovers = [link[0], link[1]]; s.stats.lovers = [link[0], link[1]]; }
    const sil = s.silencer !== undefined && s.alive[s.silencer] ? s.night.silence?.[s.silencer] ?? null : null;
    // 1.3.0, before anyone dies (the night is one moment): the Framer's frame (not if the host removed him), what the
    // checks read, and who visited whom for the Watcher. One Mafia goes to the victim: the Sheikh if he voted for him,
    // else the lowest seat that did (E-W1).
    const framed = s.framer !== undefined && s.alive[s.framer] ? s.night.frame?.[s.framer] ?? null : null;
    const checks = Object.values(s.night.detective).filter((q): q is number => q != null);
    const reads = checks.map(q => (s.roles[q] === 'mafia' && q !== s.sheikh) || q === framed);
    const voters = target == null ? [] : votes.filter(([, v]) => v === target).map(([k]) => +k);
    const visits: [number, number][] = [
      ...doc.map(([p, q]): [number, number] => [+p, q]),
      ...guards.filter(([, q]) => q != null).map(([b, q]): [number, number] => [+b, q as number]),
      ...Object.entries(s.night.detective).filter(([, q]) => q != null).map(([p, q]): [number, number] => [+p, q as number]),
      ...(framed != null ? [[s.framer!, framed] as [number, number]] : []),
      ...(aim != null ? [[+sn![0], aim] as [number, number]] : []),
      ...(voters.length ? [[s.sheikh !== undefined && voters.includes(s.sheikh) ? s.sheikh : Math.min(...voters), target!] as [number, number]] : []),
      ...(kaim != null ? [[+kp![0], kaim] as [number, number]] : []),
      ...(cu ? [[+cu[0], cu[1][0]], [+cu[0], cu[1][1]]] as [number, number][] : []),
      ...(sil != null ? [[s.silencer!, sil] as [number, number]] : []),
    ];
    const watch = Object.entries(s.night.watch ?? {}).filter(live).filter(([, t]) => t != null)
      .map(([w, t]): [number, number, number[]] => [+w, t as number, [...new Set(visits.filter(([x, y]) => y === t && x !== +w).map(([x]) => x))].sort((a, b) => a - b)]);
    if (dead != null) s.alive[dead] = false;
    if (kdead != null) s.alive[kdead] = false;
    if (shot != null) { s.alive[shot] = false; s.shotUsed = true; (s.stats.shots ??= []).push([+sn![0], shot]); }
    const hearts = heartbreak([dead, kdead, shot].filter((x): x is number => x != null));
    if (s.silencer !== undefined) { s.silenced = sil != null && s.alive[sil] ? sil : null; s.lastSilence = sil; }
    const newRoles = s.roles.includes('killer') || s.roles.includes('cupid');
    log({ t: 'night', day: s.day, mafia: skip ? { k: 'skip' } : victim == null ? { k: 'none' } : saved ? { k: 'saved', seat: victim } : { k: 'kill', seat: victim },
      prot: doc.map(([, q]) => q), checked: Object.values(s.night.detective).filter((q): q is number => q != null), ...(shot != null ? { shot } : {}),
      ...(bg ? { guard: guards.map(([, q]) => q).filter((q): q is number => q != null) } : {}),
      ...(s.framer !== undefined ? { read: reads, ...(framed != null ? { frame: { seat: framed, hit: checks.includes(framed) } } : {}) } : {}),
      ...(s.roles.includes('watcher') ? { watch } : {}),
      ...(s.roles.includes('killer') ? { sk: kvictim == null ? { k: 'none' as const } : ksaved ? { k: 'saved' as const, seat: kvictim } : { k: 'kill' as const, seat: kvictim } } : {}),
      ...(link ? { link: [link[0], link[1]] as [number, number] } : {}), ...(hearts.length ? { hearts } : {}),
      ...(s.silencer !== undefined ? { silence: sil } : {}) });
    s.lastTarget = target;
    if (kept) doc.forEach(([p, q]) => { if (q === victim) s.stats.saves.push(+p); });
    if (kkept) doc.forEach(([p, q]) => { if (q === kvictim) s.stats.saves.push(+p); });
    if (dead != null) { if (s.stats.first == null) s.stats.first = dead; s.stats.kills.push(dead); }
    if (kdead != null && kdead !== dead) { if (s.stats.first == null) s.stats.first = kdead; s.stats.kills.push(kdead); }
    for (const [p, q] of Object.entries(s.night.detective)) {
      if (q != null && s.roles[q] === 'mafia' && q !== s.sheikh && !s.stats.caught.some(([x, y]) => x === +p && y === q)) s.stats.caught.push([+p, q]);
    }
    // the morning names the dead in seat order: nobody can tell which death was the Sniper's
    const deaths = [...new Set([dead, kdead, shot].filter((x): x is number => x != null))].sort((x, y) => x - y);
    // [Quin Q2, B15] "Reveal saves" names the Mafia's target, never the Bodyguard who took the kill
    s.morning = { dead: deaths[0] ?? null, saved: kept && s.rules.saverev ? target : null, ...(s.sheikh !== undefined ? { dead2: deaths[1] ?? null } : {}),
      ...(newRoles ? { deaths, hearts } : {}) };
    // the death that decides the game leads its announcement: a Mafia shot by the Sniper when the town wins
    const lead = deaths.find(x => s.roles[x] === 'mafia' && !aliveSeats(s).some(i => s.roles[i] === 'mafia')) ?? dead ?? kdead ?? shot;
    // 1.3.0, pass-and-play: a Mayor who chose to reveal himself on his turn, if he lived
    for (const m of Object.keys(s.night.reveal ?? {}).map(Number)) if (s.alive[m]) { (s.mayors ??= []).push(m); log({ t: 'reveal', day: s.day, seat: m }); }
    takeAim([...deaths, ...hearts], 'night');
    if (checkWin(lead != null ? { k: 'killed', seat: lead } : hearts.length ? { k: 'killed', seat: hearts[0] } : null)) return;
    phase('morning');
  };

  const verdict = (out: number | null, kind: 'out' | 'skipped' | 'tie', tally: TallyLine[] | null) => {
    pauseTimer();
    if (out != null) { s.alive[out] = false; s.stats.outs.push(out); }
    s.verdict = { out, kind, tally };
    const hearts = out != null ? heartbreak([out]) : [];  // 1.4.0: a lover voted out takes the other with him
    log({ t: 'day', day: s.day, out, kind, tally, ...(hearts.length ? { hearts } : {}) });
    if (out != null) takeAim([out, ...hearts], 'day');
    // the Jester wins alone when the day vote puts him out
    if (checkWin(out != null ? { k: 'votedOut', seat: out } : null, out != null && s.roles[out] === 'jester' ? 'jester' : null)) return;
    phase('verdict');
  };
  const tally = () => {
    const c: Record<string, number> = {};
    // 1.3.0: a revealed Mayor's vote counts twice
    Object.entries(s.vote!.votes).filter(([, v]) => v !== 'abstain' && v != null && (s.rules.skipVote || v !== 'none'))
      .forEach(([k, v]) => { c[String(v)] = (c[String(v)] || 0) + (s.mayors?.includes(+k) ? 2 : 1); });
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
      // 1.3.0: the Framer's frame (null = none) and a Mayor's "reveal me in the morning" (pass-and-play)
      if (a.frame !== undefined && !(no.frame && (a.frame === null || no.frame.includes(a.frame)))) return fail('choice');
      if (a.reveal !== undefined && !(a.reveal === false || no.reveal)) return fail('choice');
      // 1.4.0: Cupid's second lover (another living player), the Silencer's pick (null = nobody)
      if (no.key === 'cupid' ? !(seatOk(s, a.pair) && s.alive[a.pair] && a.pair !== a.choice) : a.pair !== undefined) return fail('choice');
      if (a.silence !== undefined && !(no.silence && (a.silence === null || no.silence.includes(a.silence)))) return fail('choice');
      const r = s.roles[a.seat];
      if (no.key === 'killer') (s.night.killer ??= {})[a.seat] = a.choice as number;
      if (no.key === 'cupid') (s.night.cupid ??= {})[a.seat] = [a.choice as number, a.pair!];
      if (a.silence != null) (s.night.silence ??= {})[a.seat] = a.silence;
      if (r === 'watcher') (s.night.watch ??= {})[a.seat] = a.choice as number;
      if (a.frame != null) (s.night.frame ??= {})[a.seat] = a.frame;
      if (a.reveal) (s.night.reveal ??= {})[a.seat] = true;
      // 1.4.0 (found by the every-combination test): a Mafia with no target left (only the Serial Killer they hit last,
      // under "not twice") picks nothing, and nothing is no vote
      if (r === 'mafia' && a.choice != null) s.night.mafia[a.seat] = a.choice;
      if (r === 'doctor') s.night.doctor[a.seat] = a.choice as number;
      if (r === 'detective') s.night.detective[a.seat] = a.choice as number;
      if (no.key === 'sniper') (s.night.sniper ??= {})[a.seat] = a.choice as number | 'skip';
      if (r === 'bodyguard') (s.night.bodyguard ??= {})[a.seat] = a.choice as number | null;
      s.night.done[a.seat] = true;
      settle(); break;
    }

    case 'skipPending': {  // "Continue anyway" for offline players, or the night timer ran out (no seats = everyone pending)
      if (s.hunt) {  // 1.3.0: the Hunter holds fire
        if (a.seats && !a.seats.includes(s.hunt.seat)) return fail('seat');
        shoot(null); break;
      }
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

    case 'hunt':  // 1.3.0: the dead Hunter's shot
      if (!s.hunt) return fail('phase');
      if (a.seat !== s.hunt.seat) return fail('seat');
      if (!(a.choice === null || (seatOk(s, a.choice) && s.alive[a.choice] && a.choice !== a.seat))) return fail('choice');
      shoot(a.choice); break;

    case 'reveal':  // 1.3.0: a Mayor reveals himself, before the vote
      if (s.phase !== 'morning' && s.phase !== 'day') return fail('phase');
      if (!seatOk(s, a.seat)) return fail('seat');
      if (!s.alive[a.seat]) return fail('dead');
      if (s.roles[a.seat] !== 'mayor' || s.mayors?.includes(a.seat)) return fail('choice');
      (s.mayors ??= []).push(a.seat);
      log({ t: 'reveal', day: s.day, seat: a.seat });
      break;

    case 'startDay':
      if (s.hunt) return fail('hunt');
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
      // 1.4.0 (D7): the silenced player can't vote: he abstains from the start
      if (s.silenced != null && s.alive[s.silenced]) s.vote.votes[s.silenced] = 'abstain';
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
      if (s.hunt) return fail('hunt');
      if (s.phase !== 'verdict') return fail('phase');
      s.day++; startNight(); break;

    case 'remove':  // the host removes a player mid-game: counts as an elimination
      if (s.phase === 'deal' || s.phase === 'end') return fail('phase');
      if (!seatOk(s, a.seat)) return fail('seat');
      if (s.hunt?.seat === a.seat) { shoot(null); break; }  // 1.3.0: removing the Hunter while he aims = he holds fire (E-X5)
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
