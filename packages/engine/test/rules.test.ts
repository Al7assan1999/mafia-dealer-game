// One test per game rule (CONTEXT "Game design decisions") plus the host's checks on players' messages.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { apply, mvp, nightOptions, seeded, viewFor, type SeatView } from '../src/index.ts';
import { ctx, game, must, night, refuse } from './util.ts';

// seats: 0 mafia, 1 mafia, 2 doctor, 3 detective, 4-7 citizens
const R8 = ['mafia', 'mafia', 'doctor', 'detective', 'citizen', 'citizen', 'citizen', 'citizen'] as const;
const g8 = (rules = {}) => game([...R8], rules);
const seat = (s: any, i: number) => viewFor(s, i, 1_000_000) as SeatView;

test('the Mafia: most votes wins; a tie is broken at random', () => {
  let s = night(g8(), { 0: 4, 1: 4, 2: 5 });
  assert.equal(s.phase, 'morning'); assert.deepEqual(s.morning, { dead: 4, saved: null }); assert.equal(s.alive[4], false);
  const outcomes = new Set<number | null>();
  for (let seed = 1; seed <= 30; seed++) outcomes.add(night(g8(), { 0: 4, 1: 5, 2: 6 }, seed).morning!.dead);
  assert.deepEqual([...outcomes].sort(), [4, 5]);
});
test('Mafia see teammates and their picks live; they can\'t target a teammate', () => {
  let s = g8();
  s = must(s, { t: 'night', seat: 0, choice: 6 }).state;
  const o = nightOptions(s, 1);
  assert.equal(o.opts.find(x => x.seat === 6)!.mateVotes, 1);
  assert.ok(o.opts.find(x => x.seat === 0)!.teammate && o.opts.find(x => x.seat === 0)!.disabled);
  refuse(s, { t: 'night', seat: 1, choice: 0 }, 'choice');
  refuse(s, { t: 'night', seat: 1, choice: null }, 'choice');
  assert.deepEqual(seat(s, 1).mates, [0]);
});
test('one-time skip: used only when the skip actually wins', () => {
  let s = night(g8(), { 0: 'skip', 1: 'skip', 2: 5 });
  assert.equal(s.skipUsed, true); assert.equal(s.morning!.dead, null);
  assert.deepEqual(s.log.at(-1), { t: 'night', day: 1, mafia: { k: 'skip' }, prot: [5], checked: [0] });
  s = must(must(s, { t: 'startDay' }).state, { t: 'decide', choice: 'none' }).state;
  s = must(s, { t: 'nextNight' }).state;
  assert.equal(nightOptions(s, 0).skip, null);
  refuse(s, { t: 'night', seat: 0, choice: 'skip' }, 'choice');
  // a skip that loses the vote doesn't use it up (find a seed where the target wins the tie)
  let lost = false;
  for (let seed = 1; seed <= 30 && !lost; seed++) { const t = night(g8(), { 0: 'skip', 1: 6, 2: 5 }, seed); if (t.morning!.dead === 6) { lost = true; assert.equal(t.skipUsed, false); } }
  assert.ok(lost);
  assert.equal(nightOptions(g8({ skip: false }), 0).skip, null);
});
test('norep: the Mafia can\'t target last night\'s target', () => {
  let s = night(g8({ norep: true }), { 0: 4, 1: 4, 2: 4 });  // saved
  s = must(must(must(s, { t: 'startDay' }).state, { t: 'decide', choice: 'none' }).state, { t: 'nextNight' }).state;
  const o = nightOptions(s, 0).opts.find(x => x.seat === 4)!;
  assert.ok(o.disabled && o.lastTarget);
  assert.ok(!nightOptions(night(g8(), { 0: 4, 1: 4, 2: 4 }), 0).opts.find(x => x.seat === 4)?.disabled);
});
test('saverev: the morning names who the Doctor saved; off: "nobody died"', () => {
  let s = night(g8({ saverev: true }), { 0: 4, 1: 4, 2: 4 });
  assert.deepEqual(s.morning, { dead: null, saved: 4 });
  assert.deepEqual(viewFor(s, 'table', 0).result, { k: 'saved', seat: 4 });
  assert.deepEqual(s.stats.saves, [2]);
  s = night(g8(), { 0: 4, 1: 4, 2: 4 });
  assert.deepEqual(viewFor(s, 'table', 0).result, { k: 'nobody' });
});
test('the Doctor: self-protection and no repeat, by rule', () => {
  assert.ok(!nightOptions(g8({ self: true }), 2).opts.find(x => x.seat === 2)!.disabled);
  assert.ok(nightOptions(g8({ self: false }), 2).opts.find(x => x.seat === 2)!.disabled);
  let s = night(g8({ rep: true }), { 0: 4, 1: 4, 2: 5 });
  s = must(must(must(s, { t: 'startDay' }).state, { t: 'decide', choice: 'none' }).state, { t: 'nextNight' }).state;
  const o = nightOptions(s, 2).opts.find(x => x.seat === 5)!;
  assert.ok(o.disabled && o.lastNight);
});
test('decoy turns: Citizens pick too (ignored); off: nothing to pick', () => {
  const s = g8();
  assert.equal(nightOptions(s, 4).key, 'citizen');
  refuse(s, { t: 'night', seat: 4, choice: null }, 'choice');
  const t = must(s, { t: 'night', seat: 4, choice: 0 }).state;
  assert.ok(t.night.done[4]); assert.deepEqual(t.night.mafia, {});
  const off = g8({ decoy: false });
  assert.equal(nightOptions(off, 4).key, 'none');
  assert.ok(must(off, { t: 'night', seat: 4, choice: null }).state.night.done[4]);
});
test('the Detective: not themselves; the result stays until the next night', () => {
  let s = g8();
  refuse(s, { t: 'night', seat: 3, choice: 3 }, 'choice');
  s = must(s, { t: 'night', seat: 3, choice: 1 }).state;
  assert.equal(seat(s, 3).ph, 'nightDone'); assert.deepEqual(seat(s, 3).check, { seat: 1, mafia: true });
  s = night(s, { 0: 4, 1: 4, 2: 5 });
  assert.deepEqual(seat(s, 3).check, { seat: 1, mafia: true });
  assert.deepEqual(s.stats.caught, [[3, 1]]);
  s = must(must(must(s, { t: 'startDay' }).state, { t: 'decide', choice: 'none' }).state, { t: 'nextNight' }).state;
  assert.equal(seat(s, 3).check, null);
  assert.equal(seat(s, 4).check, null);
});
test('reveal: the eliminated player\'s role only with the rule', () => {
  assert.deepEqual(viewFor(night(g8(), { 0: 4, 1: 4, 2: 5 }), 'table', 0).result, { k: 'killed', seat: 4, role: 'citizen' });
  assert.deepEqual(viewFor(night(g8({ reveal: false }), { 0: 4, 1: 4, 2: 5 }), 'table', 0).result, { k: 'killed', seat: 4, role: null });
});
const toVote = (rules = {}, open = false) => {
  const s = night(g8(rules), { 0: 4, 1: 4, 2: 5 });
  return must(must(s, { t: 'startDay' }).state, { t: 'startVote', open }, 2_000_000).state;
};
const voteAll = (s: any, votes: Record<number, number | 'none'>) => { for (const [k, v] of Object.entries(votes)) s = must(s, { t: 'vote', seat: +k, choice: v }).state; return s; };
test('secret vote: most votes out; a tie or "no one" keeps everyone', () => {
  let s = voteAll(toVote(), { 0: 5, 1: 5, 2: 0, 3: 0, 5: 0, 6: 0, 7: 'none' });
  assert.equal(s.phase, 'verdict'); assert.equal(s.verdict!.out, 0);
  assert.deepEqual(s.verdict!.tally, [{ k: 0, n: 4 }, { k: 5, n: 2 }, { k: 'none', n: 1 }]);
  s = voteAll(toVote(), { 0: 5, 1: 5, 2: 0, 3: 0, 5: 'none', 6: 'none', 7: 'none' });
  assert.equal(s.verdict!.kind, 'skipped');
  s = voteAll(toVote(), { 0: 5, 1: 5, 2: 0, 3: 0, 5: 7, 6: 7, 7: 'none' });
  assert.equal(s.verdict!.kind, 'tie'); assert.equal(s.verdict!.out, null);
});
test('skipVote off: "no one" votes don\'t count', () => {
  const s = voteAll(toVote({ skipVote: false }), { 0: 5, 1: 'none', 2: 'none', 3: 'none', 5: 'none', 6: 'none', 7: 'none' });
  assert.equal(s.verdict!.out, 5);
});
test('vote checks: not yourself, not twice, not when dead, not a stale vote', () => {
  const s = toVote();
  refuse(s, { t: 'vote', seat: 0, choice: 0 }, 'choice');
  refuse(s, { t: 'vote', seat: 4, choice: 0 }, 'dead');
  refuse(s, { t: 'vote', seat: 0, choice: 4 }, 'choice');
  refuse(s, { t: 'vote', seat: 0, choice: 5, id: 123 }, 'stale');
  refuse(must(s, { t: 'vote', seat: 0, choice: 5 }).state, { t: 'vote', seat: 0, choice: 6 }, 'done');
});
test('open (table) vote shows the live board; a secret one doesn\'t', () => {
  const s = must(toVote({}, true), { t: 'vote', seat: 0, choice: 5 }).state;
  assert.deepEqual(viewFor(s, 'table', 0).board!.slice(0, 2), [{ seat: 0, v: 5 }, { seat: 1, v: null }]);
  assert.equal(viewFor(must(toVote(), { t: 'vote', seat: 0, choice: 5 }).state, 'table', 0).board, null);
});
test('night checks: stale day, twice, dead, out of phase', () => {
  const s = g8();
  refuse(s, { t: 'night', seat: 4, choice: 0, day: 2 }, 'stale');
  refuse(must(s, { t: 'night', seat: 4, choice: 0 }).state, { t: 'night', seat: 4, choice: 1 }, 'done');
  refuse(s, { t: 'night', seat: 99, choice: 0 }, 'seat');
  refuse(s, { t: 'vote', seat: 0, choice: 5 }, 'phase');
  const m = night(s, { 0: 4, 1: 4, 2: 5 });
  refuse(m, { t: 'night', seat: 0, choice: 5 }, 'phase');
});
test('night timer: unfinished turns are skipped; "continue anyway" skips only the given seats', () => {
  let s = game([...R8], { nightT: 60 }, 5_000);
  assert.equal(s.night.endsAt, 65_000);
  assert.deepEqual(viewFor(s, 'table', 5_000).timer, { end: 65_000 });
  s = must(s, { t: 'night', seat: 0, choice: 4 }).state;
  const part = must(s, { t: 'skipPending', seats: [5, 6] }).state;
  assert.equal(part.phase, 'night'); assert.ok(part.night.done[5] && !part.night.done[7]);
  const all = must(s, { t: 'skipPending' }).state;
  assert.equal(all.phase, 'morning'); assert.equal(all.morning!.dead, 4);
});
test('removing a player counts as an elimination and can finish the night', () => {
  let s = g8();
  for (const i of [0, 1, 2, 3, 4, 5, 6]) s = must(s, { t: 'night', seat: i, choice: i === 0 || i === 1 ? 4 : i === 2 ? 5 : 0 }).state;
  s = must(s, { t: 'remove', seat: 7 }).state;
  assert.equal(s.phase, 'morning');
  assert.deepEqual(s.log[0], { t: 'removed', seat: 7 });
  refuse(s, { t: 'remove', seat: 7 }, 'dead');
});
test('removing the last Mafia, or down to parity, ends the game at once', () => {
  let s = must(night(g8(), { 0: 4, 1: 4, 2: 5 }), { t: 'startDay' }).state;  // 2 Mafia, 5 others left
  s = must(s, { t: 'remove', seat: 0 }).state;
  assert.equal(s.phase, 'day');
  s = must(s, { t: 'remove', seat: 1 }).state;
  assert.equal(s.phase, 'end'); assert.equal(s.winner, 'citizens');
  assert.deepEqual(s.log.slice(-2), [{ t: 'removed', seat: 1 }, { t: 'win', winner: 'citizens', lead: null }]);
  let p = game(['mafia', 'doctor', 'citizen', 'citizen', 'citizen']);
  p = must(p, { t: 'remove', seat: 2 }).state;  // 1 vs 3: on
  assert.equal(p.phase, 'night');
  p = must(p, { t: 'remove', seat: 3 }).state;  // 1 vs 2: on
  p = must(p, { t: 'remove', seat: 4 }).state;  // 1 vs 1: Mafia win, mid-night
  assert.equal(p.winner, 'mafia'); assert.equal(p.phase, 'end');
  assert.equal(viewFor(p, 'table', 0).progress, null);
});
test('wins: the Mafia at parity, the Citizens when no Mafia are left', () => {
  // 4 players: 1 mafia, doctor, 2 citizens. Kill one: 1 vs 2 → go on; vote out a citizen: 1 vs 1 → Mafia win
  let s = game(['mafia', 'doctor', 'citizen', 'citizen']);
  s = night(s, { 0: 2, 1: 3 });
  assert.equal(s.phase, 'morning');
  s = must(must(s, { t: 'startDay' }).state, { t: 'decide', choice: 3 }).state;
  assert.equal(s.phase, 'end'); assert.equal(s.winner, 'mafia');
  assert.deepEqual(s.log.at(-1), { t: 'win', winner: 'mafia', lead: { k: 'votedOut', seat: 3 } });
  let c = game(['mafia', 'doctor', 'citizen', 'citizen']);
  c = night(c, { 0: 2, 1: 2 });
  c = must(must(c, { t: 'startDay' }).state, { t: 'decide', choice: 0 }).state;
  assert.equal(c.winner, 'citizens');
  const k = night(game(['mafia', 'doctor', 'citizen', 'citizen']), { 0: 2, 1: 3 });
  const k2 = night(must(must(must(k, { t: 'startDay' }).state, { t: 'decide', choice: 'none' }).state, { t: 'nextNight' }).state, { 0: 3, 1: 1 });
  assert.equal(k2.winner, 'mafia'); assert.deepEqual(k2.log.at(-1), { t: 'win', winner: 'mafia', lead: { k: 'killed', seat: 3 } });
});
test('privacy: a Citizen never sees roles before the end; ghosts only with the rule', () => {
  let s = g8();
  const v = seat(s, 4);
  assert.equal(v.roles, null); assert.deepEqual(v.mates, []); assert.equal(v.role, 'citizen');
  s = night(s, { 0: 4, 1: 4, 2: 5 });
  assert.equal(seat(s, 4).ph, 'dead'); assert.equal(seat(s, 4).roles, null);
  const gh = night(g8({ ghost: true }), { 0: 4, 1: 4, 2: 5 });
  assert.deepEqual(seat(gh, 4).roles, [...R8]);
  assert.equal(seat(gh, 5).roles, null);
});
test('discussion timer: start, pause, +1 minute, reset', () => {
  let s = must(night(g8(), { 0: 4, 1: 4, 2: 5 }), { t: 'startDay' }).state;
  assert.deepEqual(viewFor(s, 'table', 0).timer, { left: 180 });
  s = must(s, { t: 'timer', op: 'start' }, 10_000).state;
  assert.deepEqual(viewFor(s, 'table', 40_000).timer, { end: 190_000 });
  s = must(s, { t: 'timer', op: 'pause' }, 40_000).state;
  assert.deepEqual(viewFor(s, 'table', 99_000).timer, { left: 150 });
  s = must(s, { t: 'timer', op: 'add', sec: 60 }, 99_000).state;
  assert.deepEqual(viewFor(s, 'table', 0).timer, { left: 210 });
  refuse(s, { t: 'timer', op: 'add', sec: -5 }, 'choice');
  s = must(s, { t: 'timer', op: 'reset' }).state;
  assert.deepEqual(viewFor(s, 'table', 0).timer, { left: 180 });
});
test('MVP', () => {
  assert.deepEqual(mvp({ winner: 'mafia', roles: ['citizen', 'mafia', 'mafia'], alive: [true, false, true], stats: { first: null, kills: [], outs: [], saves: [], caught: [] } }), { seat: 2, why: 'mafia' });
  assert.deepEqual(mvp({ winner: 'mafia', roles: ['citizen', 'mafia'], alive: [true, false], stats: { first: null, kills: [], outs: [], saves: [], caught: [] } }), { seat: 1, why: 'mafia2' });
  assert.deepEqual(mvp({ winner: 'citizens', roles: ['detective', 'mafia', 'doctor'], alive: [true, false, true], stats: { first: null, kills: [], outs: [], saves: [2], caught: [[0, 1]] } }), { seat: 0, why: 'det', n: 1 });
  assert.deepEqual(mvp({ winner: 'citizens', roles: ['detective', 'mafia', 'doctor'], alive: [true, false, true], stats: { first: null, kills: [], outs: [], saves: [2, 2], caught: [] } }), { seat: 2, why: 'doc', n: 2 });
  assert.deepEqual(mvp({ winner: 'citizens', roles: ['citizen', 'mafia', 'doctor'], alive: [false, false, true], stats: { first: null, kills: [], outs: [], saves: [], caught: [] } }), { seat: 2, why: 'surv' });
});
test('apply never changes the state it is given; refused actions change nothing', () => {
  const s = g8(), before = JSON.stringify(s);
  apply(s, { t: 'night', seat: 0, choice: 4 }, { rng: seeded(1), now: 0 });
  apply(s, { t: 'night', seat: 0, choice: 1 }, { rng: seeded(1), now: 0 });
  assert.equal(JSON.stringify(s), before);
  assert.deepEqual(apply(s, { t: 'nope' } as any, ctx()), { ok: false, error: 'unknown' });
});
