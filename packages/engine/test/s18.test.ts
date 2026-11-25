// 1.1.0 (Sprint 18): the Detective never checks a player twice, no Sniper shot on night 1, the Bodyguard (his rules
// B1-B15, docs/sprint-18-prd.md). Each scripted game is saved to fixtures/records-s18.json, which the Dart engine must
// replay to the same result (engine_test.dart).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  apply, createGame, DEFAULT_RULES, modeCounts, mvp, nightOptions, replay, seeded, startRecord, step, viewFor,
  type Action, type GameRecord, type GameState, type Mode, type Role, type Rules, type SeatView,
} from '../src/index.ts';

const FILE = new URL('../fixtures/records-s18.json', import.meta.url), games: GameRecord[] = [];
const M = 'mafia', D = 'doctor', T = 'detective', C = 'citizen', S = 'sniper', B = 'bodyguard';

/** A recorded 1.1.0 game with exactly these roles (the deck the mode deals) and this Sheikh, in night 1. */
function deal(roles: Role[], sheikh: number, mode: Mode, rules: Partial<Rules> = {}) {
  const names = roles.map((_, i) => 'P' + (i + 1));
  const c = createGame({ names, counts: { mafia: 1, doctor: 1, detective: 0 }, rules: { ...DEFAULT_RULES, ...rules }, mode, bodyguard: roles.includes(B) }, seeded(1));
  assert.ok(c.ok, !c.ok ? c.error : '');
  const deck = (x: Role[]) => [...x].sort().join();
  assert.equal(deck(c.state.roles), deck(roles), 'the scripted roles are the deck this mode deals');
  let s: GameState = { ...c.state, roles: [...roles], sheikh }, now = 1_000_000;
  assert.equal(s.rv, 2);
  const rec = startRecord(s);
  games.push(rec);
  const go = (a: Action) => { const r = step(rec, s, a, { rng: seeded(1), now: now += 1000 }); assert.ok(r.ok, `${a.t}: ${!r.ok && r.error}`); s = r.state; };
  const night = (picks: Record<number, number | 'skip'>) => {
    for (const [i, a] of s.alive.entries()) {
      if (!a || s.phase !== 'night' || s.night.done[i]) continue;
      const o = nightOptions(s, i);
      go({ t: 'night', seat: i, choice: picks[i] ?? (o.key === 'none' ? null : o.opts.find(x => !x.disabled)!.seat) });
    }
  };
  const day = (out: number | 'none') => { go({ t: 'startDay' }); go({ t: 'decide', choice: out }); go({ t: 'nextNight' }); };
  go({ t: 'begin' });
  return { get s() { return s; }, go, night, day, see: (i: number) => viewFor(s, i, now) as SeatView };
}

// 8 players, Bodyguard mode: seats 0-1 Mafia (1 = the Sheikh), 2 Doctor, 3 Detective, 4 Bodyguard, 5-7 Citizens
const BG: Role[] = [M, M, D, T, B, C, C, C];
// 8 players, Sniper mode with the Bodyguard: 0-1 Mafia, 2 Doctor, 3 Detective, 4 Sniper, 5 Bodyguard, 6-7 Citizens
const SB: Role[] = [M, M, D, T, S, B, C, C];

test('S18-1: the Detective never checks a player twice; earlier results stay marked (the Sheikh reads Not Mafia)', () => {
  const g = deal(BG, 1, 'bodyguard');
  g.night({ 0: 5, 1: 5, 2: 6, 3: 0, 4: 7 });           // checks P1 (Mafia)
  assert.deepEqual(g.see(3).checks, [{ seat: 0, mafia: true }]);
  g.day('none');
  g.night({ 0: 6, 1: 6, 2: 7, 3: 1, 4: 2 });           // checks P2, the Sheikh: "not Mafia"
  g.day('none');
  const o = nightOptions(g.s, 3), at = (j: number) => o.opts.find(x => x.seat === j)!;
  assert.equal(o.key, 'detective');
  assert.deepEqual([at(0).disabled, at(0).check], [true, true]);
  assert.deepEqual([at(1).disabled, at(1).check], [true, false], 'the Sheikh reads not Mafia, for the whole game');
  assert.equal(at(2).check, undefined); assert.equal(at(2).disabled, false);
  assert.equal(apply(g.s, { t: 'night', seat: 3, choice: 0 }, { rng: seeded(1), now: 9e9 }).ok, false, 'a second check is refused');
  assert.deepEqual(g.see(3).checks, [{ seat: 0, mafia: true }, { seat: 1, mafia: false }]);
  assert.equal(g.see(2).checks, null, 'only the Detective sees them');
});

test('S18-1 AC4: everyone else checked: nothing to pick tonight', () => {
  const g = deal([M, M, D, T, B, C], 1, 'bodyguard');  // 6 players: 2 Mafia; every night the Doctor saves the target
  [0, 1, 2, 4, 5].forEach((q, k) => { g.night({ 0: 5, 1: 5, 2: 5, 3: q, 4: k % 2 ? 0 : 2 }); g.day('none'); });
  assert.ok(g.s.alive.every(Boolean));
  const o = nightOptions(g.s, 3);
  assert.equal(o.key, 'none'); assert.deepEqual(o.opts, []);
  // [Quin Q1] nothing to pick takes no pick: not a seat (a dead one would tell him a role), not 'skip', not a seat out of range
  for (const choice of [0, 'skip', 19] as const) assert.equal(apply(g.s, { t: 'night', seat: 3, choice }, { rng: seeded(1), now: 9e9 }).ok, false, String(choice));
  assert.ok(apply(g.s, { t: 'night', seat: 3, choice: null }, { rng: seeded(1), now: 9e9 }).ok);
});

test('[Quin Q3] the guarded player is removed mid-night: the Bodyguard covers nobody (one removal, one player)', () => {
  const g = deal(BG, 0, 'bodyguard');                     // seat 0 is the Godfather: his pick on P6 settles the tie
  g.go({ t: 'night', seat: 4, choice: 5 }); g.go({ t: 'night', seat: 0, choice: 5 });
  g.go({ t: 'remove', seat: 5 });
  g.night({ 1: 6, 2: 7, 3: 0 });
  assert.equal(g.s.alive[4], true); assert.equal(g.s.stats.guards, undefined);
  assert.deepEqual(g.s.alive.filter(x => !x).length, 1);
});

test('S18-2: no Sniper shot on night 1 (he picks like a Citizen); from night 2 his bullet works', () => {
  const g = deal(SB, 1, 'sniper');
  assert.equal(nightOptions(g.s, 4).key, 'citizen');
  assert.equal(apply(g.s, { t: 'night', seat: 4, choice: 'skip' }, { rng: seeded(1), now: 9e9 }).ok, false);
  g.night({ 0: 6, 1: 6, 2: 7, 3: 0, 4: 0, 5: 7 });       // his pick on P1 is only a decoy
  assert.equal(g.s.alive[0], true); assert.equal(g.s.shotUsed, false);
  g.day('none');
  assert.equal(nightOptions(g.s, 4).key, 'sniper');
  g.night({ 0: 7, 1: 7, 2: 3, 3: 1, 4: 0, 5: 3 });
  assert.equal(g.s.alive[0], false, 'the night-2 shot kills');
});

test('B2: the Mafia target the guarded player: the Bodyguard dies instead', () => {
  const g = deal(BG, 1, 'bodyguard');
  g.night({ 0: 5, 1: 5, 2: 6, 4: 5 });
  assert.deepEqual([g.s.alive[5], g.s.alive[4]], [true, false]);
  assert.deepEqual(g.s.stats.guards, [[4, 5]]);
  assert.deepEqual(g.s.morning, { dead: 4, saved: null, dead2: null });
});

test('B3: the Doctor saved the Bodyguard, who guarded the Mafia target: nobody dies', () => {
  const g = deal(BG, 1, 'bodyguard', { saverev: true });
  g.night({ 0: 5, 1: 5, 2: 4, 4: 5 });
  assert.ok(g.s.alive.every(Boolean));
  assert.deepEqual(g.s.stats.saves, [2]); assert.deepEqual(g.s.stats.guards, [[4, 5]]);
  assert.equal(g.s.morning!.saved, 5, '[Quin Q2, B15] "Reveal saves" names the Mafia target, never the Bodyguard');
});

test('B8 (his ruling): the Doctor saves the guarded player, not the Bodyguard: the Bodyguard dies', () => {
  const g = deal(BG, 1, 'bodyguard');
  g.night({ 0: 5, 1: 5, 2: 5, 4: 5 });
  assert.deepEqual([g.s.alive[5], g.s.alive[4]], [true, false]);
});

test('B9: the Mafia target the Bodyguard himself: a normal kill the Doctor can stop', () => {
  const g = deal(BG, 1, 'bodyguard');
  g.night({ 0: 4, 1: 4, 2: 4, 4: 6 });
  assert.ok(g.s.alive.every(Boolean));
  const h = deal(BG, 1, 'bodyguard');
  h.night({ 0: 4, 1: 4, 2: 7, 4: 6 });
  assert.equal(h.s.alive[4], false); assert.equal(h.s.stats.guards, undefined);
});

test('B10 (his ruling) and B5: the Sniper shoots the guarded player (even a Mafia): the Bodyguard dies, the Doctor can\'t stop it', () => {
  const g = deal(SB, 1, 'sniper');
  g.night({ 0: 6, 1: 6, 2: 7, 5: 7 }); g.day('none');   // night 1: no shot; P7 killed
  g.night({ 0: 7, 1: 7, 2: 5, 4: 0, 5: 0 });             // the Bodyguard guards P1 (Mafia), the Doctor saves him; the Sniper shoots P1
  assert.deepEqual([g.s.alive[0], g.s.alive[5]], [true, false]);
  assert.deepEqual(g.s.stats.shots, [[4, 5]]);
  assert.deepEqual(g.s.stats.guards, [[5, 0]]);
});

test('B11: the Mafia and the Sniper both aim at the guarded player: the Bodyguard dies once, the player lives', () => {
  const g = deal(SB, 1, 'sniper');
  g.night({ 0: 6, 1: 6, 2: 6, 5: 3 }); g.day('none');   // night 1: the Doctor saves P7
  g.night({ 0: 7, 1: 7, 2: 3, 4: 7, 5: 7 });
  assert.deepEqual([g.s.alive[7], g.s.alive[5]], [true, false]);
  assert.deepEqual(g.s.morning, { dead: 5, saved: null, dead2: null });
  assert.deepEqual(g.s.stats.guards, [[5, 7]]);
});

test('B12: the Sniper shoots the Bodyguard himself: he dies', () => {
  const g = deal(SB, 1, 'sniper');
  g.night({ 0: 6, 1: 6, 2: 7, 5: 7 }); g.day('none');
  g.night({ 0: 7, 1: 7, 2: 5, 4: 5, 5: 3 });
  assert.equal(g.s.alive[5], false);
});

test('B6, B7: the Bodyguard can\'t guard himself, nor the same player two nights in a row', () => {
  const g = deal(BG, 1, 'bodyguard');
  let o = nightOptions(g.s, 4);
  assert.equal(o.key, 'bodyguard'); assert.equal(o.opts.find(x => x.seat === 4)!.disabled, true);
  g.night({ 0: 7, 1: 7, 2: 6, 4: 5 }); g.day('none');
  o = nightOptions(g.s, 4);
  assert.deepEqual([o.opts.find(x => x.seat === 5)!.disabled, o.opts.find(x => x.seat === 5)!.lastNight], [true, true]);
  assert.equal(apply(g.s, { t: 'night', seat: 4, choice: 5 }, { rng: seeded(1), now: 9e9 }).ok, false);
  g.night({ 0: 6, 1: 6, 2: 6, 4: 3 }); g.day('none');
  assert.equal(nightOptions(g.s, 4).opts.find(x => x.seat === 5)!.disabled, false, 'free again a night later');
});

test('B4, B13, P2: the Detective reads a guarded player as usual; the log keeps whom he guarded; the morning names only the dead', () => {
  const g = deal(BG, 1, 'bodyguard');
  g.night({ 0: 5, 1: 5, 2: 6, 3: 0, 4: 0 });
  assert.deepEqual(g.see(3).check, { seat: 0, mafia: true });
  const n = g.s.log.find(e => e.t === 'night')!;
  assert.ok(n.t === 'night' && n.guard?.[0] === 0);
  assert.deepEqual(viewFor(g.s, 'table', 0).result, { k: 'killed', seat: 5, role: C });
});

test('S18-4: the Bodyguard mode, the Sniper and Jester modes\' optional Bodyguard, All roles; Classic never deals him', () => {
  const none = { mafia: 1, doctor: 1, detective: 0 };
  assert.deepEqual(modeCounts('bodyguard', 8, none), { mafia: 2, doctor: 1, detective: 1, sniper: 0, jester: 0, bodyguard: 1 });
  assert.deepEqual(modeCounts('sniper', 8, none, true), { mafia: 2, doctor: 1, detective: 1, sniper: 1, jester: 0, bodyguard: 1 });
  assert.deepEqual(modeCounts('jester', 6, none, true), { mafia: 2, doctor: 1, detective: 1, sniper: 0, jester: 1, bodyguard: 1 });
  assert.deepEqual(modeCounts('sniper', 8, none), { mafia: 2, doctor: 1, detective: 1, sniper: 1, jester: 0 });
  assert.deepEqual(modeCounts('classic', 8, none, true), { mafia: 1, doctor: 1, detective: 0 });
  const names = (n: number) => Array.from({ length: n }, (_, i) => 'N' + i);
  const k = (m: Mode, n: number) => { const c = createGame({ names: names(n), counts: none, rules: DEFAULT_RULES, mode: m, bodyguard: true }, seeded(n)); assert.ok(c.ok); return c.state.roles.filter(x => x === B).length; };
  assert.deepEqual([k('bodyguard', 6), k('all', 9), k('sniper', 6), k('jester', 7), k('classic', 6)], [1, 1, 1, 1, 0]);
  assert.equal(createGame({ names: names(5), counts: none, rules: DEFAULT_RULES, mode: 'bodyguard' }, seeded(1)).ok, false);
});

test('the Player of the game can be a Bodyguard who took the hit', () => {
  assert.deepEqual(mvp({ winner: 'citizens', roles: [M, B, C, C], alive: [false, true, true, true],
    stats: { first: null, kills: [], outs: [0], saves: [], caught: [], guards: [[1, 2], [1, 3]] } }), { seat: 1, why: 'guard', n: 2 });
});

test('records: a 1.1.0 game replays; a Bodyguard without the 1.1.0 rules, or rv in a game before 1.0.0, is refused', () => {
  const g = deal(BG, 1, 'bodyguard');
  g.night({ 0: 5, 1: 5, 2: 6, 3: 0, 4: 5 });
  const rec = JSON.parse(JSON.stringify(games.at(-1))) as GameRecord;
  assert.ok(replay(rec).ok);
  const { rv, ...no } = rec;
  assert.equal(rv, 2);
  assert.equal((replay(no) as { error: string }).error, 'roles');
  const { sheikh, mode, ...old } = rec;
  assert.ok(sheikh != null && mode);
  assert.equal((replay(old) as { error: string }).error, 'format');
});

test('the scripted games replay in both engines (fixtures/records-s18.json; regenerate: UPDATE_FIXTURES=1)', () => {
  if (process.env.UPDATE_FIXTURES) writeFileSync(FILE, JSON.stringify(games) + '\n');
  const saved: GameRecord[] = JSON.parse(readFileSync(FILE, 'utf8'));
  assert.equal(saved.length, games.length);
  saved.forEach((r, i) => {
    assert.deepEqual(r, JSON.parse(JSON.stringify(games[i])), `game ${i + 1} changed`);
    const x = replay(r); assert.ok(x.ok, `game ${i + 1}: ${!x.ok && x.error}`);
  });
});
