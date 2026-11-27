// One random game from a seed, checking what must always hold after every action. Returns its record.
import assert from 'node:assert/strict';
import { apply, createGame, validateSetup, DEFAULT_RULES, hasFramer, hasSilencer, mafiaRange, winnerOf, maxMafia, MODE_MIN, MODES, seeded, startRecord, step, viewFor, type Action, type GameRecord, type GameState, type Mode, type Rules, type SeatView } from '../src/index.ts';

const alive = (s: GameState) => s.alive.map((a, i) => (a ? i : -1)).filter(i => i >= 0);

/** fix: play this exact setup (the every-combination test) instead of a random one */
export interface Fix { n: number; mode: Mode; mafia: number; rules: Partial<Rules> }
export function play(seed: number, fix?: Fix): { steps: number; rec: GameRecord; state: GameState } {
  const r = seeded(seed), pick = <T>(a: T[]) => a[Math.floor(r() * a.length)], chance = (p: number) => r() < p;
  const n = fix?.n ?? 4 + Math.floor(r() * 17);
  let mafia = fix?.mafia ?? 1 + Math.floor(r() * maxMafia(n));
  const rules = fix ? { ...DEFAULT_RULES, skip: chance(.5), ghost: chance(.5), skipVote: chance(.5), nightT: pick([0, 30]), ...fix.rules } : { ...DEFAULT_RULES, skip: chance(.5), norep: chance(.5), saverev: chance(.5), decoy: chance(.5), self: chance(.5),
    rep: chance(.5), reveal: chance(.5), ghost: chance(.5), skipVote: chance(.5), nightT: pick([0, 30, 60]) };
  const names = Array.from({ length: n }, (_, i) => 'Player ' + (i + 1)), mode = fix?.mode ?? pick(MODES.filter(m => MODE_MIN[m] <= n));
  const bodyguard = chance(.5);  // 1.1.0: the Sniper and Jester modes' optional Bodyguard
  const range = mafiaRange(mode, n, rules);  // 1.3.0: Avenger and Shadows pick inside their own range
  if (range && !fix) mafia = range.min + Math.floor(r() * (range.max - range.min + 1));
  const c = createGame({ names, counts: { mafia, doctor: 1, detective: mafia >= 2 ? 1 : 0 }, rules, mode, bodyguard }, r);
  assert.ok(c.ok);
  let s = c.state, now = 1_000_000, steps = 0;
  const rec = startRecord(s);
  // [Quin Q1] rv 3 only for the new modes, or a count 1.3.x would not have dealt (so 1.3.x phones replay the rest)
  const old = validateSetup(names, { mafia, doctor: 1, detective: mafia >= 2 ? 1 : 0 }, mode, bodyguard, rules, true);
  const rv = mode === 'lovers' || mode === 'lonewolves' || old.error || old.counts.mafia !== s.roles.filter(x => x === 'mafia').length ? 3 : 2;
  const go = (a: Action) => {
    const res = step(rec, s, a, { rng: r, now: now += 1000 });
    assert.ok(res.ok, `seed ${seed}: ${a.t} refused (${!res.ok && res.error})`);
    s = res.state; steps++;
    check();
  };
  const check = () => {
    // the every-combination test runs the whole-state and whole-log checks once, at the end (each is the full history)
    const full = !fix || s.phase === 'end';
    if (full) assert.deepEqual(JSON.parse(JSON.stringify(s)), s, 'plain JSON');
    const al = alive(s), m = al.filter(i => s.roles[i] === 'mafia').length;
    assert.equal(s.roles[s.sheikh!], 'mafia', 'the Sheikh is one of the Mafia');
    const last = s.log.at(-1);
    if (s.phase === 'end' && s.winner === 'jester') assert.ok(last?.t === 'win' && last.lead?.k === 'votedOut' && s.roles[last.lead.seat] === 'jester');
    else if (s.phase === 'end') {
      // 1.4.0: the endings with a Serial Killer or a couple (R3), checked one by one
      const k = al.filter(i => s.roles[i] === 'killer').length, w = s.winner;
      if (!s.roles.includes('killer') && !s.lovers) assert.equal(w, m === 0 ? 'citizens' : 'mafia');
      if (w === 'citizens') assert.ok(m === 0 && k === 0, 'the town wins only with the Mafia and the Serial Killer gone');
      if (w === 'mafia') assert.ok(k === 0 && m >= al.length - m);
      if (w === 'killer') assert.ok(k === 1 && al.length <= 2 && m === 0, 'the Serial Killer alone, or with one non-Mafia');
      if (w === 'draw') assert.ok(al.length === 0 || (k === 1 && m === 1 && al.length === 2), 'a draw: nobody, or the Serial Killer and one Mafia');
      if (w === 'lovers') assert.ok(al.length === 2 && s.lovers!.every(x => s.alive[x]) && (s.roles[s.lovers![0]] === 'mafia') !== (s.roles[s.lovers![1]] === 'mafia'));
    }
    else if (s.hunt) { assert.ok(winnerOf(s) !== 'citizens' && !s.alive[s.hunt.seat] && s.roles[s.hunt.seat] === 'hunter', 'a dead Hunter aims, the town has not won');
      assert.ok(s.phase === 'morning' || s.phase === 'verdict'); }
    else assert.equal(winnerOf(s), null, `seed ${seed}: game should have ended`);
    if (s.phase === 'vote' && s.silenced != null && s.alive[s.silenced]) assert.equal(s.vote!.votes[s.silenced], 'abstain', 'the silenced player cannot vote');
    if (s.lovers) assert.notEqual(s.lovers[0], s.lovers[1]);
    // 1.3.0
    assert.ok(!(s.roles.includes('sniper') && s.roles.includes('hunter')), 'never the Sniper and the Hunter');
    if (range) assert.ok(s.roles.filter(x => x === 'mafia').length >= range.min && s.roles.filter(x => x === 'mafia').length <= range.max, 'Mafia inside the range');
    if (s.framer !== undefined) assert.ok(s.roles[s.framer] === 'mafia' && s.framer !== s.sheikh && hasFramer(mode, n), 'the Framer');
    else assert.ok(!hasFramer(mode, n));
    if (s.silencer !== undefined) assert.ok(s.roles[s.silencer] === 'mafia' && s.silencer !== s.sheikh && s.silencer !== s.framer && hasSilencer(mode, n), 'the Silencer');
    else assert.ok(!hasSilencer(mode, n));
    if (s.phase === 'end') assert.equal(s.hunt ?? null, null);
    for (const x of s.mayors ?? []) assert.equal(s.roles[x], 'mayor');
    const powers = ['doctor', 'bodyguard', 'detective', 'sniper', 'mafia', 'killer', 'cupid'];
    if (full) for (const e of s.log) if (e.t === 'night') {
      e.read?.forEach((x, k) => { const q = e.checked[k]; assert.equal(x, (s.roles[q] === 'mafia' && q !== s.sheikh) || q === e.frame?.seat, 'a read is the truth, or the frame'); });
      if (e.frame) assert.notEqual(s.roles[e.frame.seat], 'mafia', 'never frames a teammate');
      for (const [w, t, vs] of e.watch ?? []) { assert.equal(s.roles[w], 'watcher'); assert.notEqual(w, t);
        for (const x of vs) assert.ok(x !== w && powers.includes(s.roles[x]), 'only real powers visit (no decoys)');
        assert.ok(vs.filter(x => s.roles[x] === 'mafia' && x !== s.framer && x !== s.silencer).length <= 1, 'one Mafia visits the victim (E-W1)'); }
    }
    for (const [x, q] of s.stats.hunts ?? []) { assert.equal(s.roles[x], 'hunter'); assert.equal(s.alive[q], false); assert.notEqual(x, q); }
    // the every-combination test looks at one phone a step (in turn), the random games at all of them
    for (const i of fix ? [steps % n] : Array.from({ length: n }, (_, k) => k)) {
      const v = viewFor(s, i, now) as SeatView;
      if (s.phase !== 'end' && !(rules.ghost && !s.alive[i] && s.hunt?.seat !== i)) assert.equal(v.roles, null, 'no roles before the end (and none for the aiming Hunter)');
      assert.equal(v.ph === 'hunt', s.hunt?.seat === i);
      if (s.framer !== undefined && s.phase === 'night' && s.roles[i] === 'detective') assert.equal(v.check, null, 'with a Framer, the result waits for the morning');
      if (s.roles[i] !== 'mafia') assert.deepEqual(v.mates, []);
      if (v.check) { assert.equal(s.roles[i], 'detective'); if (v.check.seat === s.sheikh) assert.equal(v.check.mafia, false, 'the Sheikh reads not Mafia'); }
    }
    for (const [d, q] of s.stats.caught) { assert.equal(s.roles[d], 'detective'); assert.equal(s.roles[q], 'mafia'); assert.notEqual(q, s.sheikh); }
    for (const [x, q] of s.stats.shots ?? []) { assert.equal(s.roles[x], 'sniper'); assert.equal(s.alive[q], false); }
    assert.ok((s.stats.shots ?? []).length <= 1, 'one bullet');
    // 1.1.0
    assert.equal(s.rv, rv);
    const nights = s.log.filter(e => e.t === 'night');
    if (nights[0]?.t === 'night') assert.equal(nights[0].shot, undefined, 'no shot on night 1');
    const checked = nights.flatMap(e => (e.t === 'night' ? e.checked : []));
    if (s.roles.filter(x => x === 'detective').length === 1) assert.equal(new Set(checked).size, checked.length, 'nobody checked twice');
    for (const [b, q] of s.stats.guards ?? []) { assert.equal(s.roles[b], 'bodyguard'); assert.notEqual(b, q); }
    for (const [x, y] of nights.slice(1).map((e, k) => [nights[k], e])) {
      if (x.t === 'night' && y.t === 'night' && x.guard?.length && y.guard?.length && y.day === x.day + 1) assert.notEqual(x.guard[0], y.guard[0], 'not the same player two nights running');
    }
  };

  go({ t: 'begin' });
  while (s.phase !== 'end') {
    assert.ok(s.day <= 100, `seed ${seed}: too many days`);
    if (s.hunt) {  // 1.3.0: the dead Hunter: shoots, holds fire, times out, or the host removes him
      const h = s.hunt.seat, v = viewFor(s, h, now) as SeatView;
      if (chance(.1)) go({ t: 'skipPending' }); else if (chance(.05)) go({ t: 'remove', seat: h });
      else go({ t: 'hunt', seat: h, choice: chance(.2) ? null : pick(v.huntOpts!) });
      continue;
    }
    const mayor = alive(s).find(i => s.roles[i] === 'mayor' && !s.mayors?.includes(i));
    if (mayor != null && (s.phase === 'morning' || s.phase === 'day') && chance(.2)) { go({ t: 'reveal', seat: mayor }); continue; }
    if (s.phase === 'night') {
      const dead = s.alive.findIndex(a => !a);
      if (dead >= 0) assert.equal((apply(s, { t: 'night', seat: dead, choice: 0 }, { rng: r, now }) as any).error, 'dead');
      if (chance(.03)) { go({ t: 'remove', seat: pick(alive(s)) }); continue; }
      if (chance(.05)) { go({ t: 'skipPending' }); continue; }
      const p = pick(alive(s).filter(i => !s.night.done[i]));
      const v = viewFor(s, p, now) as SeatView;
      assert.equal(v.ph, 'night');
      const no = v.night!, opts: (number | 'skip')[] = no.opts.filter(o => !o.disabled).map(o => o.seat);
      if (no.skip) opts.push('skip');
      assert.ok(no.key === 'none' || opts.length, `seed ${seed}: seat ${p} (${s.roles[p]}) has nothing to pick`);
      const extra = { ...(no.frame && chance(.9) ? { frame: chance(.2) || !no.frame.length ? null : pick(no.frame) } : {}), ...(no.reveal && chance(.1) ? { reveal: true } : {}) };
      // 1.4.0: the Silencer's pick; Cupid's second lover (drawn after his first, so the older games draw as before)
      const sil = no.silence && chance(.9) ? { silence: chance(.2) || !no.silence.length ? null : pick(no.silence) } : {};
      const choice = no.key === 'none' ? null : pick(opts);
      const pair = no.key === 'cupid' ? { pair: pick(opts.filter(o => o !== choice) as number[]) } : {};
      go({ t: 'night', seat: p, choice, day: s.day, ...extra, ...sil, ...pair });
    } else if (s.phase === 'morning') go({ t: 'startDay' });
    else if (s.phase === 'day') {
      if (chance(.3)) go({ t: 'decide', choice: chance(.3) ? 'none' : pick(alive(s)) });
      else go({ t: 'startVote', open: chance(.5) });
    } else if (s.phase === 'vote') {
      if (chance(.05)) { go({ t: 'skipPending' }); continue; }
      const p = pick(alive(s).filter(i => s.vote!.votes[i] === undefined));
      const others = alive(s).filter(i => i !== p);
      go({ t: 'vote', seat: p, choice: chance(.2) ? 'none' : pick(others), id: s.vote!.id });
    } else if (s.phase === 'verdict') go({ t: 'nextNight' });
  }
  return { steps, rec, state: s };
}

