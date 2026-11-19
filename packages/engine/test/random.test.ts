// 1,000 random games, each from a fixed seed, checking what must always hold.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { apply, createGame, DEFAULT_RULES, maxMafia, seeded, viewFor, type Action, type GameState, type SeatView } from '../src/index.ts';

const alive = (s: GameState) => s.alive.map((a, i) => (a ? i : -1)).filter(i => i >= 0);

function play(seed: number) {
  const r = seeded(seed), pick = <T>(a: T[]) => a[Math.floor(r() * a.length)], chance = (p: number) => r() < p;
  const n = 4 + Math.floor(r() * 17), mafia = 1 + Math.floor(r() * maxMafia(n));
  const rules = { ...DEFAULT_RULES, skip: chance(.5), norep: chance(.5), saverev: chance(.5), decoy: chance(.5), self: chance(.5),
    rep: chance(.5), reveal: chance(.5), ghost: chance(.5), skipVote: chance(.5), nightT: pick([0, 30, 60]) };
  const names = Array.from({ length: n }, (_, i) => 'Player ' + (i + 1));
  const c = createGame({ names, counts: { mafia, doctor: 1, detective: mafia >= 2 ? 1 : 0 }, rules }, r);
  assert.ok(c.ok);
  let s = c.state, now = 1_000_000, steps = 0;
  const go = (a: Action) => {
    const res = apply(s, a, { rng: r, now: now += 1000 });
    assert.ok(res.ok, `seed ${seed}: ${a.t} refused (${!res.ok && res.error})`);
    s = res.state; steps++;
    check();
  };
  const check = () => {
    assert.deepEqual(JSON.parse(JSON.stringify(s)), s, 'plain JSON');
    const al = alive(s), m = al.filter(i => s.roles[i] === 'mafia').length;
    if (s.phase === 'end') assert.equal(s.winner, m === 0 ? 'citizens' : 'mafia');
    else {
      // 1:1 with the app: removing a player doesn't check for a win; the next night or verdict does
      const lastRemove = s.log.findLastIndex(e => e.t === 'removed'), lastResolve = s.log.findLastIndex(e => e.t !== 'removed');
      if (lastRemove < lastResolve) assert.ok(m > 0 && m < al.length - m, `seed ${seed}: game should have ended`);
    }
    for (let i = 0; i < n; i++) {
      const v = viewFor(s, i, now) as SeatView;
      if (s.phase !== 'end' && !(rules.ghost && !s.alive[i])) assert.equal(v.roles, null, 'no roles before the end');
      if (s.roles[i] !== 'mafia') assert.deepEqual(v.mates, []);
      if (v.check) assert.equal(s.roles[i], 'detective');
    }
    for (const [d, q] of s.stats.caught) { assert.equal(s.roles[d], 'detective'); assert.equal(s.roles[q], 'mafia'); }
  };

  go({ t: 'begin' });
  while (s.phase !== 'end') {
    assert.ok(s.day <= 100, `seed ${seed}: too many days`);
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
      if (no.key !== 'none' && !opts.length) {
        // only after a removal that should have ended the game (see QUIRKS.md): the host's "continue anyway" gets past it
        assert.equal(s.log.at(-1)!.t, 'removed', `seed ${seed}: seat ${p} (${s.roles[p]}) has nothing to pick`);
        go({ t: 'skipPending', seats: [p] }); continue;
      }
      go({ t: 'night', seat: p, choice: no.key === 'none' ? null : pick(opts), day: s.day });
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
  return steps;
}

test('1,000 random games: they all end, the winner is right, nothing leaks, the state stays plain JSON', () => {
  let steps = 0;
  for (let seed = 1; seed <= 1000; seed++) steps += play(seed);
  assert.ok(steps > 10_000);
});
