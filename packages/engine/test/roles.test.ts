// 1.0.0 (Sprint 17): شيخ المافيا in every game, the Sniper, the Jester and the modes. Each scripted game is also saved
// to fixtures/records-roles.json, which the Dart engine must replay to the same result (engine_test.dart).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  createGame, DEFAULT_RULES, modeCounts, mvp, nightOptions, replay, seeded, startRecord, step, validateSetup, viewFor,
  type Action, type GameRecord, type GameState, type Mode, type Role, type Rules, type SeatView,
} from '../src/index.ts';

const FILE = new URL('../fixtures/records-roles.json', import.meta.url), games: GameRecord[] = [];
const M = 'mafia', D = 'doctor', T = 'detective', C = 'citizen', S = 'sniper', J = 'jester';

/** A recorded game with exactly these roles and this Sheikh, in the night of day 1. */
function deal(roles: Role[], sheikh: number, mode: Mode = 'classic', rules: Partial<Rules> = {}) {
  const names = roles.map((_, i) => 'P' + (i + 1)), n = (r: Role) => roles.filter(x => x === r).length;
  const c = createGame({ names, counts: { mafia: n(M), doctor: 1, detective: n(T) }, rules: { ...DEFAULT_RULES, ...rules }, mode }, seeded(1));
  assert.ok(c.ok, !c.ok ? c.error : '');
  let s: GameState = { ...c.state, roles: [...roles], sheikh }, now = 1_000_000;
  delete s.rv;  // these are 1.0.0 games (1.1.0's rules: s18.test.ts); their records are the 1.0.0 fixtures
  const rec = startRecord(s);
  games.push(rec);
  const go = (a: Action) => { const r = step(rec, s, a, { rng: seeded(1), now: now += 1000 }); assert.ok(r.ok, `${a.t}: ${!r.ok && r.error}`); s = r.state; };
  const night = (picks: Record<number, number | 'skip'>) => {
    for (const [i, a] of s.alive.entries()) {
      if (!a || s.phase !== 'night') continue;
      const o = nightOptions(s, i);
      go({ t: 'night', seat: i, choice: picks[i] ?? (o.key === 'none' ? null : o.opts.find(x => !x.disabled)!.seat) });
    }
  };
  const day = (out: number | 'none') => { go({ t: 'startDay' }); go({ t: 'decide', choice: out }); };
  go({ t: 'begin' });
  return { get s() { return s; }, go, night, day, rec, see: (i: number) => viewFor(s, i, now) as SeatView };
}

// 12 players: seats 0-4 Mafia (4 = the Sheikh), 5 Doctor, 6 Detective, 7-11 Citizens
const R12: Role[] = [M, M, M, M, M, D, T, C, C, C, C, C];

test('his example: a tie goes to the Sheikh, even a pick nobody else made (2 on P8, 2 on P9, the Sheikh on P10)', () => {
  const g = deal(R12, 4);
  g.night({ 0: 7, 1: 7, 2: 8, 3: 8, 4: 9, 5: 11, 6: 0 });
  assert.equal(g.s.morning!.dead, 9); assert.equal(g.s.alive[9], false);
});

test('his example: the Mafia beat the Sheikh only with a clear majority (2 on P6, the Sheikh on P7)', () => {
  const g = deal([M, M, M, D, T, C, C, C, C, C], 2);
  g.night({ 0: 5, 1: 5, 2: 6, 3: 9 });
  assert.equal(g.s.morning!.dead, 5);
});

test('a tie never kills nobody: with the Sheikh out, the lowest seat that voted for a tied pick decides', () => {
  const g = deal(R12, 0);
  g.night({ 0: 7, 1: 7, 2: 8, 3: 8, 4: 8, 5: 11 }); // 3 on P9: no tie
  assert.equal(g.s.morning!.dead, 8);
  g.day(0);                                         // the Sheikh is voted out: never passed on
  assert.equal(g.s.sheikh, 0); assert.equal(g.s.alive[0], false);
  g.go({ t: 'nextNight' });
  g.night({ 1: 9, 2: 10, 3: 10, 4: 9, 5: 11 });     // 2-2 tie: seat 1 is the lowest seat that voted (for P10)
  assert.equal(g.s.morning!.dead, 9);
  assert.equal(g.see(1).sheikh, 0, 'the Mafia still see who the Sheikh was');
});

test('the Sheikh didn\'t vote (timer, offline): the lowest seat decides the tie', () => {
  const g = deal(R12, 2);
  for (const [i, c] of [[0, 9], [1, 10], [3, 9], [4, 10]] as const) g.go({ t: 'night', seat: i, choice: c });
  for (const i of [5, 6, 7, 8, 9, 10, 11]) g.go({ t: 'night', seat: i, choice: nightOptions(g.s, i).opts.find(o => !o.disabled)!.seat });
  g.go({ t: 'skipPending' });                       // only the Sheikh (seat 2) is left
  assert.equal(g.s.morning!.dead, 9);               // seat 0 voted for P10
});

test('the Sheikh\'s "skip" decides a tie and spends the one-time skip', () => {
  const g = deal([M, M, M, D, T, C, C, C, C, C], 1);
  g.night({ 0: 5, 1: 'skip', 2: 6, 3: 9 });
  assert.equal(g.s.morning!.dead, null); assert.equal(g.s.skipUsed, true);
  assert.equal(g.s.log.at(-1)!.t === 'night' && (g.s.log.at(-1) as any).mafia.k, 'skip');
});

test('the Mafia see the Sheikh\'s pick; the Sheikh sees himself as the Sheikh; others don\'t see him', () => {
  const g = deal([M, M, M, D, T, C, C, C, C, C], 1);
  g.go({ t: 'night', seat: 1, choice: 7 });
  const o = nightOptions(g.s, 0);
  assert.equal(o.opts.find(x => x.seat === 7)!.sheikh, true); assert.equal(o.opts.find(x => x.seat === 6)!.sheikh, false);
  assert.equal(g.see(1).sheikh, 1); assert.equal(g.see(0).sheikh, 1);
  assert.equal(g.see(4).sheikh, null); assert.equal(g.see(5).sheikh, null);
});

test('the Detective always reads the Sheikh "not Mafia", and finds the other Mafia', () => {
  const g = deal([M, M, D, T, C, C, C, C], 0);
  g.night({ 0: 5, 1: 5, 2: 4, 3: 0 });
  assert.deepEqual(g.see(3).check, { seat: 0, mafia: false }); assert.deepEqual(g.s.stats.caught, []);
  g.day('none'); g.go({ t: 'nextNight' });
  g.night({ 0: 6, 1: 6, 2: 4, 3: 1 });
  assert.deepEqual(g.see(3).check, { seat: 1, mafia: true }); assert.deepEqual(g.s.stats.caught, [[3, 1]]);
});

// All roles, 9 players: 0-1 Mafia (1 = the Sheikh), 2 Doctor, 3 Detective, 4 Sniper, 5 Jester, 6-8 Citizens
const ALL: Role[] = [M, M, D, T, S, J, C, C, C];

test('the Sniper: one bullet, nothing stops it (not the Doctor); two dead in seat order, the second in `also`', () => {
  const g = deal(ALL, 1, 'all');
  assert.equal(nightOptions(g.s, 4).key, 'sniper'); assert.ok(nightOptions(g.s, 4).skip, 'he may keep the bullet');
  assert.ok(nightOptions(g.s, 4).opts.find(o => o.seat === 4)!.disabled, 'never himself');
  g.night({ 0: 8, 1: 8, 2: 6, 4: 6 });               // the Doctor protects P7, the Sniper shoots P7: P7 dies
  assert.deepEqual(g.s.morning, { dead: 6, saved: null, dead2: 8 });
  assert.deepEqual(viewFor(g.s, 'table', 0).result, { k: 'killed', seat: 6, role: C, also: { seat: 8, role: C } });
  assert.deepEqual(g.s.stats.shots, [[4, 6]]); assert.deepEqual(g.s.stats.saves, []);
  assert.equal((g.s.log.at(-1) as any).shot, 6);
  g.day('none'); g.go({ t: 'nextNight' });
  assert.equal(nightOptions(g.s, 4).key, 'citizen', 'the bullet is spent');
});

test('the Sniper and the Mafia pick the same player: one death; a saved Mafia target still dies to the bullet', () => {
  const g = deal(ALL, 1, 'all');
  g.night({ 0: 7, 1: 7, 2: 7, 4: 7 });
  assert.deepEqual(g.s.morning, { dead: 7, saved: null, dead2: null });
  assert.deepEqual(viewFor(g.s, 'table', 0).result, { k: 'killed', seat: 7, role: C });
});

test('the Sniper keeps the bullet ("skip"), then a shot at the last Mafia ends the game at once', () => {
  const g = deal(ALL, 1, 'all');
  g.night({ 0: 6, 1: 6, 4: 'skip' });
  assert.equal(g.s.shotUsed, false);
  g.day(0); g.go({ t: 'nextNight' });                // a Mafia is voted out
  g.night({ 1: 7, 4: 1 });                           // the Sniper shoots the Sheikh, the last Mafia
  assert.equal(g.s.phase, 'end'); assert.equal(g.s.winner, 'citizens');
});

test('the Jester wins alone when voted out by day; killed at night or removed, he is just out', () => {
  const won = deal(ALL, 1, 'all');
  assert.equal(nightOptions(won.s, 5).key, 'citizen', 'he picks like a Citizen');
  won.night({ 0: 6, 1: 6 });
  won.day(5);
  assert.equal(won.s.phase, 'end'); assert.equal(won.s.winner, 'jester');
  assert.deepEqual(won.s.log.at(-1), { t: 'win', winner: 'jester', lead: { k: 'votedOut', seat: 5 } });
  assert.deepEqual(mvp({ ...won.s, winner: won.s.winner! }), { seat: 5, why: 'jester' });
  const shot = deal(ALL, 1, 'all');
  shot.night({ 0: 5, 1: 5 });
  assert.equal(shot.s.alive[5], false); assert.equal(shot.s.phase, 'morning');
  const removed = deal(ALL, 1, 'all');
  removed.go({ t: 'remove', seat: 5 });
  assert.equal(removed.s.winner, null);
});

test('modes: the deck is fixed by player count; each mode has its minimum', () => {
  const none = { mafia: 1, doctor: 1, detective: 0 };
  assert.deepEqual(modeCounts('sniper', 6, none), { mafia: 2, doctor: 1, detective: 1, sniper: 1, jester: 0 });
  assert.deepEqual(modeCounts('jester', 8, none), { mafia: 2, doctor: 1, detective: 1, sniper: 0, jester: 1 });
  assert.deepEqual(modeCounts('all', 12, none), { mafia: 3, doctor: 1, detective: 1, sniper: 1, jester: 1, bodyguard: 1 });  // 1.1.0: + the Bodyguard
  assert.deepEqual(modeCounts('classic', 8, { mafia: 3, doctor: 1, detective: 1 }), { mafia: 3, doctor: 1, detective: 1 });
  const names = (n: number) => Array.from({ length: n }, (_, i) => 'N' + i);
  assert.equal(validateSetup(names(5), none, 'sniper').error, 'modeFew');
  assert.equal(validateSetup(names(8), none, 'all').error, 'modeFew');
  assert.equal(validateSetup(names(9), none, 'all').error, null);
  for (const n of [9, 14, 20]) {
    const c = createGame({ names: names(n), counts: none, rules: DEFAULT_RULES, mode: 'all' }, seeded(n));
    assert.ok(c.ok);
    const k = (r: Role) => c.state.roles.filter(x => x === r).length;
    assert.deepEqual([k(S), k(J), k(T), k(D)], [1, 1, 1, 1]);
    assert.equal(c.state.roles[c.state.sheikh!], M);
  }
  // every game has a Sheikh: one Mafia, he is the Sheikh
  const one = createGame({ names: names(4), counts: none, rules: DEFAULT_RULES }, seeded(5));
  assert.ok(one.ok); assert.equal(one.state.roles[one.state.sheikh!], M);
  assert.equal(createGame({ names: names(9), counts: none, rules: DEFAULT_RULES, mode: 'nope' as Mode }, seeded(1)).ok, false);
});

test('[Quin Q2] a Mafia removed mid-night has no say: a removed Sheikh\'s pick doesn\'t settle the tie, nor does a removed Sniper shoot', () => {
  const g = deal([M, M, M, D, T, C, C, C, C, C], 0);
  g.go({ t: 'night', seat: 0, choice: 5 }); g.go({ t: 'night', seat: 1, choice: 6 });
  g.go({ t: 'remove', seat: 0 });
  for (const i of [3, 4, 5, 6, 7, 8, 9]) g.go({ t: 'night', seat: i, choice: nightOptions(g.s, i).opts.find(o => !o.disabled)!.seat });
  g.go({ t: 'skipPending' });                         // seat 2 never voted
  assert.equal(g.s.morning!.dead, 6);                 // seat 1, the lowest living Mafia who voted, decides
  const a = deal(ALL, 1, 'all');
  a.go({ t: 'night', seat: 4, choice: 7 }); a.go({ t: 'remove', seat: 4 });
  a.night({ 0: 6, 1: 6 });
  assert.equal(a.s.alive[7], true); assert.equal(a.s.shotUsed, false);
});

test('[Quin Q3] the Sniper shoots the last Mafia while the Mafia kill a Citizen: the Mafia\'s death leads the win', () => {
  const g = deal(ALL, 1, 'all');
  g.night({ 0: 6, 1: 6, 4: 'skip' });
  g.day(0); g.go({ t: 'nextNight' });
  g.night({ 1: 7, 4: 1 });
  assert.equal(g.s.winner, 'citizens');
  assert.deepEqual(g.s.log.at(-1), { t: 'win', winner: 'citizens', lead: { k: 'killed', seat: 1 } });
});

test('his ruling: with "Roles revealed" on, the Godfather is named when he dies or is voted out; off, nothing is said', () => {
  const g = deal([M, M, M, D, T, C, C, C, C, C], 2);
  g.night({ 0: 6, 1: 6, 2: 6, 3: 9 });
  g.day(2);
  assert.deepEqual(viewFor(g.s, 'table', 0).result, { k: 'out', seat: 2, role: M, sheikh: true, tally: null });
  const off = deal([M, M, M, D, T, C, C, C, C, C], 2, 'classic', { reveal: false });
  off.night({ 0: 6, 1: 6, 2: 6, 3: 9 });
  off.day(2);
  assert.deepEqual(viewFor(off.s, 'table', 0).result, { k: 'out', seat: 2, role: null, tally: null });
});

test('the scripted games replay in both engines (fixtures/records-roles.json; regenerate: UPDATE_FIXTURES=1)', () => {
  if (process.env.UPDATE_FIXTURES) writeFileSync(FILE, JSON.stringify(games) + '\n');
  const saved: GameRecord[] = JSON.parse(readFileSync(FILE, 'utf8'));
  assert.deepEqual(JSON.parse(JSON.stringify(games)), saved, 'the scripted games play differently now');
  saved.forEach((r, i) => { const x = replay(r); assert.ok(x.ok, `game ${i + 1}: ${!x.ok && x.error}`); });
  assert.ok(saved.some(r => r.winner === 'jester'));
});
