// 1.3.0 (Sprint 20): the Hunter, the Mayor, the Framer, the Watcher, the Avenger and Shadows modes, the Mafia ranges
// and the lean (his rulings, docs/sprint-20-roles.md: every E-… case Ben listed). Each scripted game is saved to
// fixtures/records-s20.json, which the Dart engine must replay to the same result (engine_test.dart).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  apply, createGame, DEFAULT_RULES, lean, mafiaRange, modeCounts, mvp, nightOptions, replay, seeded, startRecord, step, validateSetup, viewFor,
  type Action, type GameRecord, type GameState, type Mode, type PublicView, type Role, type Rules, type SeatView,
} from '../src/index.ts';

const FILE = new URL('../fixtures/records-s20.json', import.meta.url), games: GameRecord[] = [];
const M = 'mafia', D = 'doctor', T = 'detective', C = 'citizen', S = 'sniper', B = 'bodyguard', J = 'jester', H = 'hunter', Y = 'mayor', W = 'watcher';
const OFF = { reveal: false };  // the way the group plays (59 of 60 games)

/** A recorded 1.3.0 game with exactly these roles (the deck the mode deals), this Sheikh (and Framer), in night 1. */
function deal(roles: Role[], sheikh: number, mode: Mode, rules: Partial<Rules> = OFF, framer?: number) {
  const names = roles.map((_, i) => 'P' + (i + 1)), mafia = roles.filter(r => r === M).length;
  const c = createGame({ names, counts: { mafia, doctor: 1, detective: 0 }, rules: { ...DEFAULT_RULES, ...rules }, mode, legacy: true }, seeded(1));  // 1.3.0 rules (rv 2), as written
  assert.ok(c.ok, !c.ok ? c.error : '');
  const deck = (x: Role[]) => [...x].sort().join();
  assert.equal(deck(c.state.roles), deck(roles), 'the scripted roles are the deck this mode deals');
  let s: GameState = { ...c.state, roles: [...roles], sheikh, ...(framer !== undefined ? { framer } : {}) }, now = 1_000_000;
  const rec = startRecord(s);
  games.push(rec);
  const go = (a: Action) => { const r = step(rec, s, a, { rng: seeded(1), now: now += 1000 }); assert.ok(r.ok, `${a.t}: ${!r.ok && r.error}`); s = r.state; };
  const no = (a: Action, error: string) => { const r = apply(s, a, { rng: seeded(1), now }); assert.equal(r.ok ? 'ok' : r.error, error); };
  /** picks[seat] = a seat (or 'skip'); frame = the Framer's frame; everyone else picks their first option */
  const night = (picks: Record<number, number | 'skip'>, frame?: number | null) => {
    for (const [i, a] of s.alive.entries()) {
      if (!a || s.phase !== 'night' || s.night.done[i]) continue;
      const o = nightOptions(s, i);
      go({ t: 'night', seat: i, choice: picks[i] ?? (o.key === 'none' ? null : o.opts.find(x => !x.disabled)!.seat), ...(o.frame && frame !== undefined ? { frame } : {}) });
    }
  };
  const vote = (votes: Record<number, number | 'none'>) => {
    go({ t: 'startVote', open: false });
    for (const [i, a] of s.alive.entries()) if (a && s.phase === 'vote') go({ t: 'vote', seat: i, choice: votes[i] ?? 'none', id: s.vote!.id });
  };
  go({ t: 'begin' });
  return { get s() { return s; }, go, no, night, vote, see: (i: number) => viewFor(s, i, now) as SeatView, table: () => viewFor(s, 'table', now) as PublicView };
}

// Avenger, 6: 0-1 Mafia (0 = the Sheikh), 2 Doctor, 3 Detective, 4 Hunter, 5 Citizen
const AV6: Role[] = [M, M, D, T, H, C];
// Avenger, 7: + the Mayor (5)
const AV7: Role[] = [M, M, D, T, H, Y, C];
// Shadows, 8: 0 Sheikh, 1 Framer, 2 Doctor, 3 Detective, 4 Watcher, 5 Sniper, 6-7 Citizens
const SH8: Role[] = [M, M, D, T, W, S, C, C];

test('§8: the Mafia ranges, the lean, and the decks (Avenger: the Hunter; Shadows: the Sniper; never both)', () => {
  const r = (m: Mode, n: number, x: Partial<Rules> = OFF) => { const g = mafiaRange(m, n, x)!; return [g.min, g.max, g.def]; };
  assert.deepEqual(r('avenger', 6), [1, 2, 2]); assert.deepEqual(r('avenger', 9), [2, 2, 2]); assert.deepEqual(r('avenger', 12), [2, 3, 3]);
  assert.deepEqual(r('avenger', 15), [3, 4, 4]); assert.deepEqual(r('avenger', 20), [4, 5, 5]);
  assert.deepEqual(r('shadows', 8), [2, 2, 2]); assert.deepEqual(r('shadows', 9), [2, 3, 3]); assert.deepEqual(r('shadows', 18), [4, 5, 5]);
  assert.equal(mafiaRange('classic', 9), null); assert.equal(mafiaRange('sniper', 9, OFF, true), null, 'a 1.3 game: Sniper had no range (1.4.0 gives it one)');
  // the lean: Mafia points minus town points
  assert.equal(lean(OFF), 0); assert.equal(lean({ reveal: true }), -2); assert.equal(lean(DEFAULT_RULES), 0, 'the default: reveal off (his ruling)'); assert.equal(lean({ rep: true, decoy: false }), 2);
  assert.equal(lean({ self: false, rep: true, decoy: false, saverev: true }), 2);
  // §8 C's example: Shadows, 9, "not twice" on and decoy off: only 2 Mafia (+ the Jester)
  assert.deepEqual(r('shadows', 9, { reveal: false, rep: true, decoy: false }), [2, 2, 2]);
  assert.deepEqual(modeCounts('shadows', 9, { mafia: 3, doctor: 1, detective: 1 }, false, { reveal: false, rep: true, decoy: false }),
    { mafia: 2, doctor: 1, detective: 1, watcher: 1, sniper: 1, jester: 1, mayor: 0, bodyguard: 0 });
  assert.deepEqual(r('avenger', 12, { reveal: true }), [3, 3, 3], 'leaning town: the lower count is gone');
  // the table's pick inside the range is kept; outside it, the default
  assert.equal(modeCounts('shadows', 9, { mafia: 2, doctor: 1, detective: 1 }, false, OFF).mafia, 2);
  assert.equal(modeCounts('shadows', 9, { mafia: 1, doctor: 1, detective: 1 }, false, OFF).mafia, 3);
  assert.deepEqual(modeCounts('shadows', 9, { mafia: 3, doctor: 1, detective: 1 }, false, OFF),
    { mafia: 3, doctor: 1, detective: 1, watcher: 1, sniper: 1, jester: 0, mayor: 0, bodyguard: 0 }, '3 Mafia at 9: no Jester');
  assert.deepEqual(modeCounts('avenger', 6, { mafia: 1, doctor: 1, detective: 1 }, false, OFF),
    { mafia: 1, doctor: 1, detective: 0, hunter: 1, mayor: 0, jester: 0, bodyguard: 0 }, '1 Mafia: no Detective, as in Classic');
  assert.equal(modeCounts('avenger', 7, { mafia: 2, doctor: 1, detective: 1 }).mayor, 1, 'the Mayor from 7');
  assert.equal(modeCounts('shadows', 10, { mafia: 2, doctor: 1, detective: 1 }).mayor, 0);
  assert.equal(modeCounts('shadows', 11, { mafia: 2, doctor: 1, detective: 1 }).mayor, 1, 'Shadows: the Mayor from 11');
  // every mode, every size, every count the setup can offer: a valid deck, never the Sniper with the Hunter
  for (const m of ['classic', 'sniper', 'jester', 'bodyguard', 'all', 'avenger', 'shadows'] as Mode[]) for (let n = 4; n <= 20; n++) for (let k = 1; k <= 9; k++) {
    const c = modeCounts(m, n, { mafia: k, doctor: 1, detective: 1 }, true, OFF);
    assert.ok(!(c.sniper && c.hunter), `${m} ${n}`);
  }
  assert.equal(validateSetup(Array.from({ length: 7 }, (_, i) => 'P' + i), { mafia: 2, doctor: 1, detective: 1 }, 'shadows').error, 'modeFew');
});

test('E-H1: the Mafia kill the Hunter and reach parity: he shoots first, and a Mafia shot saves the game', () => {
  const g = deal(AV6, 0, 'avenger');
  g.night({ 0: 5, 1: 5, 2: 2 });             // the Citizen dies
  g.go({ t: 'startDay' }); g.go({ t: 'decide', choice: 'none' }); g.go({ t: 'nextNight' });
  g.night({ 0: 4, 1: 4, 2: 2 });             // the Hunter dies: 2 Mafia vs 2
  assert.equal(g.s.phase, 'morning'); assert.equal(g.s.winner, null);
  assert.deepEqual(g.table().hunt, { seat: 4 });
  assert.equal(g.see(4).ph, 'hunt'); assert.deepEqual(g.see(4).huntOpts, [0, 1, 2, 3]);
  g.no({ t: 'startDay' }, 'hunt');
  g.no({ t: 'hunt', seat: 3, choice: 0 }, 'seat');
  g.no({ t: 'hunt', seat: 4, choice: 5 }, 'choice');       // already dead
  g.no({ t: 'hunt', seat: 4, choice: 4 }, 'choice');       // himself
  g.go({ t: 'hunt', seat: 4, choice: 1 });
  assert.equal(g.s.alive[1], false); assert.equal(g.s.winner, null);
  assert.deepEqual(g.table().hunted, { by: 4, seat: 1, role: null }, 'reveal off: no role');
  assert.deepEqual(g.s.stats.hunts, [[4, 1]]);
  g.go({ t: 'startDay' });
  assert.equal(g.table().hunted, null, 'shown with its morning only');
});

test('E-H1: holding fire at parity: the Mafia win, the Hunter\'s death leads', () => {
  const g = deal(AV6, 0, 'avenger');
  g.night({ 0: 5, 1: 5, 2: 2 });
  g.go({ t: 'startDay' }); g.go({ t: 'decide', choice: 'none' }); g.go({ t: 'nextNight' });
  g.night({ 0: 4, 1: 4, 2: 2 });
  g.go({ t: 'hunt', seat: 4, choice: null });
  assert.equal(g.s.winner, 'mafia');
  assert.deepEqual(g.s.log.at(-1), { t: 'win', winner: 'mafia', lead: { k: 'killed', seat: 4 } });
});

test('E-H3, E-H5: voted out, he shoots after the verdict; shooting the last Mafia wins it for the town, and his shot leads', () => {
  const g = deal(AV6, 0, 'avenger');
  g.night({ 0: 'skip', 1: 'skip', 2: 2 });   // the Mafia skip (so no save or catch beats the Hunter to the MVP)
  g.go({ t: 'startDay' }); g.go({ t: 'decide', choice: 1 });  // a Mafia out: 1 left
  g.go({ t: 'nextNight' });
  g.night({ 0: 5, 2: 2 });                   // the Citizen dies: 1 Mafia vs D, T, H
  g.go({ t: 'startDay' }); g.go({ t: 'decide', choice: 4 });  // the town votes out its Hunter
  assert.equal(g.s.phase, 'verdict'); assert.deepEqual(g.s.hunt, { seat: 4, from: 'day', endsAt: 0 });
  g.no({ t: 'nextNight' }, 'hunt');
  g.go({ t: 'hunt', seat: 4, choice: 0 });
  assert.equal(g.s.winner, 'citizens');
  assert.deepEqual(g.s.log.at(-1), { t: 'win', winner: 'citizens', lead: { k: 'killed', seat: 0 } });
  assert.deepEqual(mvp({ winner: 'citizens', roles: g.s.roles, alive: g.s.alive, stats: g.s.stats }), { seat: 4, why: 'hunter' }, 'E-H11');
});

test('E-H4: the Hunter shoots the Jester: he dies and does not win', () => {
  const g = deal([M, M, D, T, H, Y, J, C, C], 0, 'avenger');
  g.night({ 0: 4, 1: 4, 2: 2 });
  g.go({ t: 'hunt', seat: 4, choice: 6 });
  assert.equal(g.s.alive[6], false); assert.equal(g.s.winner, null);
  g.go({ t: 'startDay' });
});

test('E-H5: voted out at parity and holding fire: the Mafia win, his vote-out leads', () => {
  const g = deal(AV6, 0, 'avenger');
  g.night({ 0: 5, 1: 5, 2: 2 });             // 2 vs 3
  g.go({ t: 'startDay' }); g.go({ t: 'decide', choice: 4 });  // 2 vs 2
  assert.equal(g.s.winner, null);
  g.go({ t: 'skipPending' });                // the timer / "Continue anyway": holds fire
  assert.equal(g.s.winner, 'mafia');
  assert.deepEqual(g.s.log.at(-2), { t: 'hunt', day: 1, seat: 4, target: null, from: 'day' });
  assert.deepEqual(g.s.log.at(-1), { t: 'win', winner: 'mafia', lead: { k: 'votedOut', seat: 4 } });
});

test('E-H6, E-H7, E-X5: the timer, "Continue anyway" for others, the host\'s Remove', () => {
  const t = deal(AV6, 0, 'avenger', { reveal: false, nightT: 30 });
  t.night({ 0: 4, 1: 4, 2: 2 });
  assert.ok(t.s.hunt!.endsAt > 0, 'his aim gets the night timer'); assert.ok('end' in t.table().timer!);
  t.no({ t: 'skipPending', seats: [0] }, 'seat');
  t.go({ t: 'remove', seat: 4 });            // removed while aiming: holds fire
  assert.equal(t.s.hunt, null); assert.equal(t.s.log.at(-1)!.t, 'hunt');
  t.go({ t: 'startDay' });
  const r = deal(AV6, 0, 'avenger');
  r.go({ t: 'remove', seat: 4 });            // a living Hunter removed: no shot
  assert.equal(r.s.hunt ?? null, null); assert.equal(r.s.log.at(-1)!.t, 'removed');
});

test('E-H8: ghost rule: the aiming Hunter sees no roles until he has shot', () => {
  const g = deal(AV6, 0, 'avenger', { reveal: false, ghost: true });
  g.night({ 0: 4, 1: 4, 2: 2 });
  assert.equal(g.see(4).roles, null);
  g.go({ t: 'hunt', seat: 4, choice: null });
  assert.equal(g.see(4).ph, 'dead'); assert.ok(g.see(4).roles);
});

test('E-M1-M8: the Mayor reveals by day, his vote counts twice, the Doctor can\'t pick him, the Bodyguard can', () => {
  const g = deal(AV7, 0, 'avenger');
  g.night({ 0: 6, 1: 6, 2: 2 });             // the Citizen dies
  g.no({ t: 'reveal', seat: 4 }, 'choice');  // not the Mayor
  g.go({ t: 'startDay' });
  g.go({ t: 'reveal', seat: 5 });
  g.no({ t: 'reveal', seat: 5 }, 'choice');  // once
  assert.deepEqual(g.table().mayors, [5]);
  // 6 alive: the Mayor and the Hunter on P1 (3 votes), the other three on P3 (3): a tie, nobody out
  g.go({ t: 'startVote', open: true });
  g.no({ t: 'reveal', seat: 5 }, 'phase');   // E-M7: not during the vote
  for (const [i, v] of [[5, 0], [4, 0], [0, 2], [1, 2], [3, 2], [2, 3]] as [number, number][]) g.go({ t: 'vote', seat: i, choice: v, id: g.s.vote!.id });
  assert.deepEqual(g.s.verdict, { out: null, kind: 'tie', tally: [{ k: 0, n: 3 }, { k: 2, n: 3 }, { k: 3, n: 1 }] }, 'the Mayor ×2 + the Hunter = 3 on P1, a tie with P3');
});

test('E-M2: the doubled vote decides; E-M4: the Doctor\'s options', () => {
  const g = deal(AV7, 0, 'avenger');
  g.night({ 0: 6, 1: 6, 2: 2 });
  g.go({ t: 'startDay' }); g.go({ t: 'reveal', seat: 5 });
  g.vote({ 5: 1, 4: 1, 0: 2, 1: 2, 2: 1, 3: 2 });  // P2: Mayor ×2 + 2 = 4; P3: 3
  assert.deepEqual(g.s.verdict!.tally, [{ k: 1, n: 4 }, { k: 2, n: 3 }]);
  assert.equal(g.s.verdict!.out, 1);
  g.go({ t: 'nextNight' });
  const o = nightOptions(g.s, 2).opts.find(x => x.seat === 5)!;
  assert.deepEqual([o.disabled, o.mayor], [true, true]);
  g.no({ t: 'night', seat: 2, choice: 5 }, 'choice');
});

test('E-M6: pass-and-play: the Mayor reveals from his night turn, in the morning, if he lives', () => {
  const g = deal(AV7, 0, 'avenger');
  assert.equal(nightOptions(g.s, 5).reveal, true);
  g.no({ t: 'night', seat: 4, choice: 0, reveal: true }, 'choice');  // not the Mayor
  g.go({ t: 'night', seat: 5, choice: 0, reveal: true });
  assert.equal(g.table().mayors!.length, 0, 'not before the morning');
  g.night({ 0: 6, 1: 6, 2: 2 });
  assert.deepEqual(g.s.mayors, [5]); assert.equal(g.s.log.at(-1)!.t, 'reveal');
  assert.equal(nightOptions(g.s, 5).reveal, undefined);
  const k = deal(AV7, 0, 'avenger');         // he dies that night: no reveal
  k.go({ t: 'night', seat: 5, choice: 0, reveal: true });
  k.night({ 0: 5, 1: 5, 2: 2 });
  assert.equal(k.s.mayors, undefined);
});

test('E-F1-F7: the Framer frames; the Detective reads Mafia that night only, in the morning; the read stays; no catch', () => {
  const g = deal(SH8, 0, 'shadows', OFF, 1);
  assert.deepEqual(nightOptions(g.s, 1).frame, [2, 3, 4, 5, 6, 7], 'never a teammate');
  assert.equal(nightOptions(g.s, 0).frame, undefined, 'only the Framer');
  g.no({ t: 'night', seat: 1, choice: 6, frame: 0 }, 'choice');
  g.no({ t: 'night', seat: 0, choice: 6, frame: 7 }, 'choice');
  g.go({ t: 'night', seat: 3, choice: 7 });  // the Detective checks P8 before the frame is in
  assert.equal(g.see(3).check, null, 'E-F2: the result waits for the morning');
  g.night({ 0: 6, 1: 6, 2: 2, 4: 7 }, 7);    // the Framer frames P8
  assert.deepEqual(g.see(3).check, { seat: 7, mafia: true });
  assert.deepEqual(g.see(1).framed, { seat: 7, hit: true }, 'R4: the Framer learns it hit');
  assert.equal(g.see(0).framed, undefined, 'only the Framer');
  assert.equal(g.see(0).framer, 1, 'his teammates know him');
  assert.deepEqual(g.s.stats.caught, [], 'E-F7: not a catch');
  g.go({ t: 'startDay' }); g.go({ t: 'decide', choice: 'none' }); g.go({ t: 'nextNight' });
  assert.deepEqual(g.see(3).checks, [{ seat: 7, mafia: true }], 'E-F3: the read stays');
  assert.equal(nightOptions(g.s, 3).opts.find(o => o.seat === 7)!.check, true);
  assert.deepEqual(g.see(1).framed, { seat: 7, hit: true }, 'still on his next night turn (pass-and-play shows it there)');
  g.night({ 0: 2, 1: 2, 2: 2, 4: 5 });  // the Doctor saves himself; no frame tonight
  assert.equal(g.see(1).framed, null, 'a night without a frame: nothing');
});

test('E-F4, E-F5: the Framer removed mid-night frames nobody; killed the same night, his frame still counts', () => {
  const r = deal(SH8, 0, 'shadows', OFF, 1);
  r.go({ t: 'night', seat: 1, choice: 6, frame: 7 });
  r.go({ t: 'remove', seat: 1 });
  r.night({ 0: 6, 2: 2, 3: 7 });
  assert.deepEqual(r.see(3).check, { seat: 7, mafia: false });
  const k = deal(SH8, 0, 'shadows', OFF, 1);  // night 2: the Sniper shoots the Framer, who framed P8
  k.night({ 0: 6, 1: 6, 2: 2, 3: 2 }); k.go({ t: 'startDay' }); k.go({ t: 'decide', choice: 'none' }); k.go({ t: 'nextNight' });
  k.night({ 0: 7, 1: 7, 2: 7, 3: 7, 5: 1 }, 7);  // the Doctor saves P8
  assert.equal(k.s.alive[1], false);
  assert.deepEqual(k.see(3).check, { seat: 7, mafia: true });
  const f = deal(SH8, 0, 'shadows', OFF, 1);   // E-F5: no frame sent
  f.night({ 0: 6, 1: 6, 2: 2, 3: 7 });
  assert.deepEqual(f.see(3).check, { seat: 7, mafia: false });
});

test('E-W1-W7: the Watcher sees the real visitors: one Mafia, no decoys, not himself; the pick counts, not the cover', () => {
  const g = deal(SH8, 0, 'shadows', OFF, 1);
  // the Mafia (both) on P7, the Doctor and the Detective on P7 too; P8 (a Citizen) decoy-taps P7
  g.night({ 0: 6, 1: 6, 2: 6, 3: 6, 4: 6, 7: 6 }, 3);
  assert.deepEqual(g.see(4).watch, [{ seat: 6, visitors: [0, 2, 3] }], 'the Sheikh voted for him: he is the one who went');
  assert.equal(g.see(3).watch, undefined, 'only the Watcher');
  assert.deepEqual(nightOptions(g.s, 4).opts.find(o => o.seat === 4)!.disabled, true, 'not himself');
  // the Framer's frame on P4 (the Detective): the Watcher on P4 sees the Framer
  g.go({ t: 'startDay' }); g.go({ t: 'decide', choice: 'none' }); g.go({ t: 'nextNight' });
  g.night({ 0: 'skip', 1: 'skip', 2: 2, 3: 2, 4: 3, 5: 7 }, 3);  // the Mafia skip: no Mafia visit
  assert.deepEqual(g.see(4).watch!.at(-1), { seat: 3, visitors: [1] });
  const t = deal(SH8, 0, 'shadows', OFF, 1);   // a tie (P6 / P7) goes to the Sheikh's pick, and he is the one who went
  t.night({ 0: 5, 1: 6, 2: 2, 3: 2, 4: 5 });
  assert.equal(t.s.alive[5], false);
  assert.deepEqual(t.see(4).watch, [{ seat: 5, visitors: [0] }]);
});

test('E-W1: the lowest Mafia who voted goes when the Sheikh voted elsewhere; E-W5, E-W6', () => {
  // 11 players, 3 Mafia (the Sheikh is P3, the Framer P2), 3 Doctor, 4 Detective, 5 Watcher, 6 Sniper, 7 Mayor, 10 Jester
  const g = deal([M, M, M, D, T, W, S, Y, C, C, J], 2, 'shadows', OFF, 1);
  // P1 and P2 on P9, the Sheikh on P10: P9 dies; the Watcher on P9 sees P1 (the lowest who voted for him)
  g.night({ 0: 8, 1: 8, 2: 9, 3: 3, 4: 3, 5: 8 }, 9);
  assert.equal(g.s.alive[8], false);
  assert.deepEqual(g.see(5).watch, [{ seat: 8, visitors: [0] }], 'his target died: he still gets the list (E-W5)');
  // E-W6: the Watcher dies that night and still sees his result (the Framer visited P10)
  g.go({ t: 'startDay' }); g.go({ t: 'decide', choice: 'none' }); g.go({ t: 'nextNight' });
  g.night({ 0: 5, 1: 5, 2: 5, 3: 3, 5: 9, 6: 'skip' }, 9);
  assert.equal(g.s.alive[5], false);
  assert.deepEqual(g.see(5).watch!.at(-1), { seat: 9, visitors: [1] });
});

test('[combination test] a Doctor left with no one to protect (self off, not twice, a revealed Mayor) skips his turn', () => {
  const c = createGame({ names: ['A', 'B', 'C', 'D', 'E', 'F', 'G'], counts: { mafia: 2, doctor: 1, detective: 1 }, rules: { ...DEFAULT_RULES, reveal: false, self: false, rep: true }, mode: 'avenger' }, seeded(3));
  assert.ok(c.ok);
  const s: GameState = { ...c.state, phase: 'night', roles: [M, M, D, T, H, Y, C], alive: [false, true, true, false, false, true, false], mayors: [5], lastProt: { 2: 1 } };
  assert.deepEqual(nightOptions(s, 2), { key: 'none', opts: [], skip: null });
  assert.equal(apply(s, { t: 'night', seat: 2, choice: null }, { rng: seeded(1), now: 1 }).ok, true);
});

test('the scripted games replay in both engines (fixtures/records-s20.json; regenerate: UPDATE_FIXTURES=1)', () => {
  if (process.env.UPDATE_FIXTURES) writeFileSync(FILE, JSON.stringify(games) + '\n');
  const saved: GameRecord[] = JSON.parse(readFileSync(FILE, 'utf8'));
  assert.deepEqual(saved, games);
  saved.forEach((r, i) => { const x = replay(r); assert.ok(x.ok, `game ${i + 1}: ${!x.ok && x.error}`); });
  // a Framer who is the Sheikh, or a Framer outside Shadows, is not a record any version writes
  const sh = games.find(r => r.mode === 'shadows')!, av = games.find(r => r.mode === 'avenger')!;
  const bad = (r: GameRecord) => { const x = replay(r); assert.equal(x.ok ? 'ok' : x.error, 'roles'); };
  bad({ ...JSON.parse(JSON.stringify(sh)), framer: sh.sheikh });
  bad({ ...JSON.parse(JSON.stringify(av)), framer: 1 });
  const nf = JSON.parse(JSON.stringify(sh)); delete nf.framer; bad(nf);
  const old = JSON.parse(JSON.stringify(av)); delete old.rv; bad(old);
});
