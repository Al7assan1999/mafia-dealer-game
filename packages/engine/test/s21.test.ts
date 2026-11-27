// 1.4.0 (Sprint 21): the Serial Killer, Cupid and the Lovers, the Silencer, the Lovers and Lone Wolves modes, the old
// modes' Mafia ranges, and the new endings (his rulings R1-R12, docs/sprint-21-prd.md; the E-K/E-C/E-S cases). Each
// scripted game is saved to fixtures/records-s21.json, which the Dart engine must replay to the same result.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import {
  apply, createGame, DEFAULT_RULES, hasFramer, hasSilencer, mafiaRange, modeCounts, mvp, nightOptions, replay, seeded, startRecord, step, viewFor, winnerOf,
  type Action, type GameRecord, type GameState, type Mode, type PublicView, type Role, type Rules, type SeatView,
} from '../src/index.ts';

const FILE = new URL('../fixtures/records-s21.json', import.meta.url), games: GameRecord[] = [];
const M = 'mafia', D = 'doctor', T = 'detective', C = 'citizen', B = 'bodyguard', J = 'jester', H = 'hunter', W = 'watcher', K = 'killer', U = 'cupid';
const OFF = { reveal: false };

/** A recorded 1.4.0 game with exactly these roles (the mode's deck), this Sheikh (and Framer, Silencer), in night 1. */
function deal(roles: Role[], mode: Mode, seats: { sheikh?: number; framer?: number; silencer?: number } = {}, rules: Partial<Rules> = OFF) {
  const names = roles.map((_, i) => 'P' + (i + 1)), mafia = roles.filter(r => r === M).length;
  const c = createGame({ names, counts: { mafia, doctor: 1, detective: 0 }, rules: { ...DEFAULT_RULES, ...rules }, mode }, seeded(1));
  assert.ok(c.ok, !c.ok ? c.error : '');
  const deck = (x: Role[]) => [...x].sort().join();
  assert.equal(deck(c.state.roles), deck(roles), 'the scripted roles are the deck this mode deals');
  let s: GameState = { ...c.state, roles: [...roles], sheikh: seats.sheikh ?? 0,
    ...(seats.framer !== undefined ? { framer: seats.framer } : {}), ...(seats.silencer !== undefined ? { silencer: seats.silencer } : {}) }, now = 1_000_000;
  assert.equal(s.rv, 3);
  const rec = startRecord(s);
  games.push(rec);
  const go = (a: Action) => { const r = step(rec, s, a, { rng: seeded(1), now: now += 1000 }); assert.ok(r.ok, `${a.t} ${'seat' in a ? a.seat : ''}: ${!r.ok && r.error}`); s = r.state; };
  const no = (a: Action, error: string) => { const r = apply(s, a, { rng: seeded(1), now }); assert.equal(r.ok ? 'ok' : r.error, error); };
  /** picks[seat] = a seat or 'skip'; extra[seat] = more fields (Cupid's pair, the Silencer's pick); others: first option */
  const night = (picks: Record<number, number | 'skip'>, extra: Record<number, object> = {}) => {
    for (const [i, a] of s.alive.entries()) {
      if (!a || s.phase !== 'night' || s.night.done[i]) continue;
      const o = nightOptions(s, i);
      go({ t: 'night', seat: i, choice: picks[i] ?? (o.key === 'none' ? null : o.opts.find(x => !x.disabled)!.seat), ...(extra[i] ?? {}) });
    }
  };
  const day = (out: number | 'none') => { go({ t: 'startDay' }); go({ t: 'decide', choice: out }); if (s.phase === 'verdict' && !s.hunt) go({ t: 'nextNight' }); };
  go({ t: 'begin' });
  return { get s() { return s; }, go, no, night, day, see: (i: number) => viewFor(s, i, now) as SeatView, table: () => viewFor(s, 'table', now) as PublicView };
}

// Lone Wolves, 9: 0-1 Mafia (0 the Godfather), 2 Doctor, 3 Detective, 4 Bodyguard, 5 Serial Killer, 6-8 Citizens
const LW9: Role[] = [M, M, D, T, B, K, C, C, C];
// Lone Wolves, 11: 0 Godfather, 1 Silencer, 2 Mafia, 3 Doctor, 4 Detective, 5 Bodyguard, 6 Serial Killer, 7 Watcher, 8 Jester, 9-10 Citizens
const LW11: Role[] = [M, M, M, D, T, B, K, W, J, C, C];
// Lovers, 8: 0-1 Mafia, 2 Doctor, 3 Detective, 4 Cupid, 5-7 Citizens
const LV8: Role[] = [M, M, D, T, U, C, C, C];
// Lovers, 9 (3 Mafia): 0-2 Mafia, 3 Doctor, 4 Detective, 5 Cupid, 6 Hunter, 7 Jester, 8 Citizen
const LV9: Role[] = [M, M, M, D, T, U, H, J, C];

test('the decks: Lovers and Lone Wolves by size; the Silencer and the Framer; the old modes\' ranges (legacy: none)', () => {
  const c = (m: Mode, n: number, k = 9) => modeCounts(m, n, { mafia: k, doctor: 1, detective: 1 }, false, OFF);
  assert.deepEqual(c('lovers', 8), { mafia: 2, doctor: 1, detective: 1, cupid: 1, hunter: 0, sniper: 0, jester: 0, mayor: 0, bodyguard: 0, watcher: 0 });
  assert.equal(c('lovers', 17).sniper, 1); assert.equal(c('lovers', 17).hunter, 0, 'never the Sniper with the Hunter');
  assert.deepEqual(c('lonewolves', 9), { mafia: 2, doctor: 1, detective: 1, bodyguard: 1, killer: 1, watcher: 0, jester: 0, mayor: 0, hunter: 0 });
  assert.equal(c('lonewolves', 20).killer, 1, 'R9: one Serial Killer');
  assert.deepEqual([hasSilencer('lonewolves', 10), hasSilencer('lonewolves', 11), hasFramer('lonewolves', 12), hasFramer('lonewolves', 13)], [false, true, false, true]);
  const r = (m: Mode, n: number, legacy = false) => mafiaRange(m, n, OFF, legacy);
  assert.deepEqual(r('lovers', 9), { min: 2, max: 3, def: 3 }); assert.deepEqual(r('lonewolves', 11), { min: 3, max: 3, def: 3 });
  assert.deepEqual(r('sniper', 10), { min: 2, max: 3, def: 3 }, 'R10'); assert.deepEqual(r('jester', 6), { min: 1, max: 2, def: 2 });
  assert.equal(r('sniper', 10, true), null, 'a 1.3 record: no range'); assert.equal(r('all', 12), null); assert.equal(r('classic', 9), null);
  assert.equal(modeCounts('sniper', 10, { mafia: 2, doctor: 1, detective: 1 }, false, OFF).mafia, 2, 'the table\'s pick');
  assert.equal(modeCounts('sniper', 10, { mafia: 2, doctor: 1, detective: 1 }, false, OFF, true).mafia, 3, 'legacy: the old fixed count');
});

test('R3: the endings with a Serial Killer or a couple', () => {
  const g = deal(LW9, 'lonewolves'), at = (alive: number[], lovers: [number, number] | null = null) => winnerOf({ ...g.s, alive: g.s.alive.map((_, i) => alive.includes(i)), lovers });
  assert.equal(at([5]), 'killer', 'alone');
  assert.equal(at([5, 6]), 'killer', 'with one non-Mafia');
  assert.equal(at([5, 0]), 'draw', 'with one Mafia');
  assert.equal(at([]), 'draw', 'nobody');
  assert.equal(at([5, 0, 1]), null, 'E-K6: play on');
  assert.equal(at([5, 0, 6]), null);
  assert.equal(at([0, 1, 6]), 'mafia', 'no Serial Killer: the old rule');
  assert.equal(at([0, 6], [0, 6]), 'lovers', 'a mixed couple, the last two, ahead of the Mafia count');
  assert.equal(at([6, 7], [6, 7]), 'citizens', 'a town couple wins with the town');
});

test('E-K, R2: the Serial Killer kills alone; the Doctor saves, the Bodyguard covers; the Detective reads him not Mafia; he can kill a Mafia', () => {
  const g = deal(LW9, 'lonewolves');
  assert.equal(nightOptions(g.s, 5).key, 'killer');
  assert.equal(nightOptions(g.s, 5).opts.find(o => o.seat === 5)!.disabled, true, 'not himself');
  g.night({ 0: 6, 1: 6, 2: 2, 3: 5, 4: 8, 5: 7 });
  assert.deepEqual([g.s.alive[6], g.s.alive[7]], [false, false], 'two deaths');
  assert.deepEqual(g.table().result, { k: 'killed', seat: 6, role: null, also: { seat: 7, role: null } });
  assert.deepEqual(g.see(3).check, { seat: 5, mafia: false });
  g.day('none');
  g.night({ 0: 8, 1: 8, 2: 3, 3: 0, 4: 2, 5: 3 });                // the Doctor saves the Detective from him
  assert.equal(g.s.alive[3], true); assert.deepEqual(g.s.stats.saves, [2]);
  g.day('none');
  g.night({ 0: 'skip', 1: 'skip', 2: 2, 3: 1, 4: 3, 5: 3 });       // the Bodyguard covers the Detective: he dies instead
  assert.equal(g.s.alive[4], false); assert.equal(g.s.alive[3], true);
  g.day('none');
  g.night({ 0: 5, 1: 5, 2: 2, 3: 2, 5: 1 });                       // he kills a Mafia; the Mafia kill him
  assert.deepEqual([g.s.alive[1], g.s.alive[5]], [false, false]);
});

test('R3 in play: the Serial Killer and one non-Mafia left: he wins; the MVP is his', () => {
  const g = deal(LW9, 'lonewolves');
  g.night({ 0: 6, 1: 6, 2: 2, 3: 0, 4: 2, 5: 7 }); g.day(0);       // 6, 7 dead; the Godfather voted out
  g.night({ 1: 8, 2: 2, 3: 1, 4: 5, 5: 1 }); g.day(2);             // 8 and the last Mafia dead; the Doctor voted out
  assert.equal(g.s.winner, null, 'the town can\'t win while he lives');
  g.night({ 3: 4, 4: 3, 5: 3 });                                   // the Bodyguard covers the Detective and dies
  assert.equal(g.s.winner, 'killer', 'he and the Detective');
  assert.deepEqual(mvp({ winner: 'killer', roles: g.s.roles, alive: g.s.alive, stats: g.s.stats }), { seat: 5, why: 'killer' });
});

test('E-C, R4-R6: Cupid links two (himself allowed); the lovers learn name and side; a broken heart, announced, by night and by vote', () => {
  const g = deal(LV8, 'lovers');
  assert.equal(nightOptions(g.s, 4).key, 'cupid');
  g.no({ t: 'night', seat: 4, choice: 6, pair: 6 }, 'choice');      // two different players
  g.no({ t: 'night', seat: 4, choice: 6 }, 'choice');               // a pair
  g.no({ t: 'night', seat: 2, choice: 2, pair: 3 }, 'choice');      // only Cupid
  g.night({ 0: 7, 1: 7, 2: 2, 3: 0 }, { 4: { pair: 1 } });           // Cupid's first option is P1: a Mafia couple, P1 and P2
  assert.deepEqual(g.s.lovers, [0, 1]);
  assert.deepEqual(g.see(0).lover, { seat: 1, side: 'mafia' });
  const x = deal(LV8, 'lovers');
  x.go({ t: 'night', seat: 4, choice: 5, pair: 1 });                 // a mixed couple: P6 (town) and P2 (Mafia)
  x.night({ 0: 5, 1: 5, 2: 2, 3: 0 });                               // the Mafia kill P6: P2 dies of a broken heart
  assert.deepEqual([x.s.alive[5], x.s.alive[1]], [false, false]);
  assert.deepEqual((x.table().result as any).hearts, [{ seat: 1, role: null }]);
  assert.deepEqual(x.s.stats.hearts, [1]);
  const v = deal(LV8, 'lovers');                                     // by vote
  v.go({ t: 'night', seat: 4, choice: 6, pair: 7 });
  v.night({ 0: 5, 1: 5, 2: 2, 3: 0 });
  assert.deepEqual(v.see(6).lover, { seat: 7, side: 'town' });
  v.go({ t: 'startDay' }); v.go({ t: 'decide', choice: 6 });
  assert.equal(v.s.alive[7], false);
  assert.deepEqual((v.table().result as any).hearts, [{ seat: 7, role: null }]);
  const self = deal(LV8, 'lovers');                                  // R5: Cupid links himself
  self.go({ t: 'night', seat: 4, choice: 4, pair: 6 });
  self.night({ 0: 5, 1: 5, 2: 2, 3: 0 });
  assert.deepEqual(self.s.lovers, [4, 6]);
});

test('E-C2, E-C3: the Hunter as a lover dies of a broken heart and aims; his shot at a lover takes the other too', () => {
  const g = deal(LV9, 'lovers');
  g.go({ t: 'night', seat: 5, choice: 6, pair: 8 });                 // the Hunter and the Citizen
  g.night({ 0: 8, 1: 8, 2: 8, 3: 3, 4: 0 });                         // the Citizen dies; the Hunter of a broken heart
  assert.deepEqual([g.s.alive[8], g.s.alive[6]], [false, false]);
  assert.equal(g.s.hunt?.seat, 6);
  const k = deal(LV9, 'lovers');
  k.go({ t: 'night', seat: 5, choice: 7, pair: 8 });                 // the Jester and the Citizen
  k.night({ 0: 6, 1: 6, 2: 6, 3: 3, 4: 0 });                         // the Hunter dies and aims
  k.go({ t: 'hunt', seat: 6, choice: 8 });                           // shoots the Citizen: the Jester dies too
  assert.deepEqual([k.s.alive[8], k.s.alive[7]], [false, false]);
  const hl = k.s.log.find(e => e.t === 'hunt');
  assert.deepEqual(hl?.t === 'hunt' ? hl.hearts : null, [7], 'his shot took the Jester too (and that gave the Mafia parity: the game is over)');
});

test('E-C1, E-C4, E-C6, E-C5: the Jester lover voted out wins; a removed lover\'s partner lives; Cupid removed mid-night links nobody', () => {
  const j = deal(LV9, 'lovers');
  j.go({ t: 'night', seat: 5, choice: 7, pair: 8 });
  j.night({ 0: 'skip', 1: 'skip', 2: 'skip', 3: 3, 4: 0 });
  j.go({ t: 'startDay' }); j.go({ t: 'decide', choice: 7 });
  assert.equal(j.s.winner, 'jester');
  const r = deal(LV8, 'lovers');
  r.go({ t: 'night', seat: 4, choice: 6, pair: 7 });
  r.night({ 0: 'skip', 1: 'skip', 2: 2, 3: 0 });
  r.go({ t: 'remove', seat: 6 });
  assert.equal(r.s.alive[7], true, 'R7: the partner lives');
  const c = deal(LV8, 'lovers');
  c.go({ t: 'night', seat: 4, choice: 6, pair: 7 });
  c.go({ t: 'remove', seat: 4 });
  c.night({ 0: 'skip', 1: 'skip', 2: 2, 3: 0 });
  assert.equal(c.s.lovers ?? null, null);
  const t = deal(LV8, 'lovers');                                     // E-C5: he times out ("Continue anyway")
  t.go({ t: 'skipPending', seats: [4] });
  t.night({ 0: 'skip', 1: 'skip', 2: 2, 3: 0 });
  assert.equal(t.s.lovers ?? null, null, 'no link this game');
});

test('the Lovers win: a mixed couple, the last two; the MVP is the first of the couple', () => {
  const g = deal(LV8, 'lovers');
  g.go({ t: 'night', seat: 4, choice: 1, pair: 7 });                 // P2 (Mafia) and P8 (town)
  g.night({ 0: 5, 1: 5, 2: 2, 3: 0 }); g.day(0);                     // P6 dies; the Godfather voted out
  g.night({ 1: 6, 2: 2, 3: 2 }); g.day(2);                           // P7 dies; the Doctor voted out
  g.night({ 1: 3, 3: 1 }); g.day(4);                                 // the Detective dies; Cupid voted out
  assert.equal(g.s.winner, 'lovers');
  assert.deepEqual(mvp({ winner: 'lovers', roles: g.s.roles, alive: g.s.alive, stats: g.s.stats }), { seat: 1, why: 'lovers' });
});

test('E-S, R8: the Silencer: not himself, teammates allowed, not twice running; announced; the silenced player abstains; a removed Silencer silences nobody', () => {
  const g = deal(LW11, 'lonewolves', { sheikh: 0, silencer: 1 });
  const o = nightOptions(g.s, 1).silence!;
  assert.ok(!o.includes(1) && o.includes(0) && o.includes(2));
  assert.equal(nightOptions(g.s, 0).silence, undefined, 'only the Silencer');
  g.night({ 0: 9, 1: 9, 2: 9, 3: 3, 4: 0, 5: 4, 6: 10, 7: 9 }, { 1: { silence: 8 } });
  assert.equal(g.table().silenced, 8);
  assert.equal(g.see(0).silencer, 1, 'his teammates know him');
  g.go({ t: 'startDay' }); g.go({ t: 'startVote', open: false });
  assert.equal(g.s.vote!.votes[8], 'abstain');
  g.no({ t: 'vote', seat: 8, choice: 0 }, 'done');
  for (const i of [0, 1, 2, 3, 4, 5, 6, 7]) if (g.s.phase === 'vote' && g.s.alive[i]) g.go({ t: 'vote', seat: i, choice: 'none' });
  g.go({ t: 'nextNight' });
  assert.equal(g.table().silenced, null, 'one day only');
  assert.ok(!nightOptions(g.s, 1).silence!.includes(8), 'not the same player two nights running');
  const r = deal(LW11, 'lonewolves', { sheikh: 0, silencer: 1 });
  r.go({ t: 'night', seat: 1, choice: 9, silence: 8 });
  r.go({ t: 'remove', seat: 1 });
  r.night({ 0: 9, 2: 9, 3: 3, 4: 0, 5: 4, 6: 10, 7: 9 });
  assert.equal(r.table().silenced, null, 'E-S2: removed, he silences nobody');
});

// [Quin Q4] the edge cases that had no test
const Y = 'mayor', S = 'sniper';
// Lone Wolves, 13 (3 Mafia): 0 Godfather, 1 Framer, 2 Silencer, 3 Doctor, 4 Detective, 5 Bodyguard, 6 Serial Killer, 7 Watcher, 8 Jester, 9 Mayor, 10-12 Citizens
const LW13: Role[] = [M, M, M, D, T, B, K, W, J, Y, C, C, C];
// Lone Wolves, 17 (4 Mafia): 0 Godfather, 1 Framer, 2 Silencer, 3 Mafia, 4 Doctor, 5 Detective, 6 Bodyguard, 7 Serial Killer, 8 Watcher, 9 Jester, 10 Mayor, 11 Hunter, 12-16 Citizens
const LW17: Role[] = [M, M, M, M, D, T, B, K, W, J, Y, H, C, C, C, C, C];
// Lovers, 17 (4 Mafia): 0-3 Mafia, 4 Doctor, 5 Detective, 6 Cupid, 7 Sniper, 8 Jester, 9 Mayor, 10 Bodyguard, 11 Watcher, 12-16 Citizens
const LV17: Role[] = [M, M, M, M, D, T, U, S, J, Y, B, W, C, C, C, C, C];
const SEATS = { sheikh: 0, framer: 1, silencer: 2 };

test('E-K1: the Serial Killer kills the Hunter: the Hunter aims and can shoot him', () => {
  const g = deal(LW17, 'lonewolves', SEATS);
  g.night({ 0: 12, 1: 12, 2: 12, 3: 12, 4: 13, 5: 0, 6: 14, 7: 11, 8: 15 });
  assert.deepEqual([g.s.alive[11], g.s.alive[12]], [false, false]);
  assert.equal(g.s.hunt?.seat, 11, 'he aims');
  g.go({ t: 'hunt', seat: 11, choice: 7 });
  assert.equal(g.s.alive[7], false); assert.equal(g.s.winner, null);
});

test('D9: the Hunter\'s shot comes before a Serial Killer win: a shot at him gives the town the win; holding fire gives it to him', () => {
  for (const [shot, winner] of [[7, 'citizens'], [null, 'killer']] as const) {
    const g = deal(LW17, 'lonewolves', SEATS);
    for (const i of [0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 13, 14, 15, 16]) g.go({ t: 'remove', seat: i });
    assert.equal(g.s.winner, null, 'he, the Hunter and a Citizen');
    g.night({ 7: 11 });
    assert.equal(g.s.winner, null, 'he and one Citizen left, but the Hunter shoots first');
    assert.equal(g.s.hunt?.seat, 11);
    g.go({ t: 'hunt', seat: 11, choice: shot });
    assert.equal(g.s.winner, winner);
  }
});

test('E-K4, E-K5: the Serial Killer voted out or removed: the game goes on, and the win check runs', () => {
  const g = deal(LW9, 'lonewolves');
  g.night({ 0: 6, 1: 6, 2: 2, 3: 5, 4: 8, 5: 7 }); g.day(5);
  assert.equal(g.s.alive[5], false); assert.equal(g.s.winner, null); assert.equal(g.s.phase, 'night');
  const r = deal(LW9, 'lonewolves');
  r.go({ t: 'remove', seat: 0 }); r.go({ t: 'remove', seat: 1 });
  assert.equal(r.s.winner, null, 'the Mafia gone, but he lives');
  r.go({ t: 'remove', seat: 5 });
  assert.equal(r.s.winner, 'citizens');
});

test('the Serial Killer and the Mafia on the same target: one death, counted once', () => {
  const g = deal(LW9, 'lonewolves');
  g.night({ 0: 6, 1: 6, 2: 2, 3: 0, 4: 8, 5: 6 });
  assert.deepEqual(g.s.alive.map((a, i) => a ? -1 : i).filter(i => i >= 0), [6]);
  assert.deepEqual(g.s.stats.kills, [6]);
  assert.deepEqual(g.s.morning?.deaths, [6]);
  assert.deepEqual(g.table().result, { k: 'killed', seat: 6, role: null });
});

test('a draw in play: the Serial Killer and one Mafia are the last two; no MVP', () => {
  const g = deal(LW9, 'lonewolves');
  for (const i of [1, 2, 3, 4, 6, 7]) g.go({ t: 'remove', seat: i });
  assert.equal(g.s.winner, null);
  g.night({ 0: 8, 5: 8 });
  assert.equal(g.s.winner, 'draw');
  assert.equal(mvp({ winner: 'draw', roles: g.s.roles, alive: g.s.alive, stats: g.s.stats }), null);
});

test('E-C7, E-C9: Cupid\'s visit to both lovers is seen by the Watcher; both lovers killed the same night: each named once, no broken heart', () => {
  const g = deal(LV17, 'lovers');
  g.night({ 0: 14, 1: 14, 2: 14, 3: 14, 4: 4, 6: 12, 10: 16, 11: 12 }, { 6: { pair: 13 } });
  assert.deepEqual(g.s.lovers, [12, 13]);
  const w = g.s.log.findLast(e => e.t === 'night');
  assert.ok(w?.t === 'night' && w.watch!.some(([x, t, seen]) => x === 11 && t === 12 && seen.includes(6)), 'the Watcher sees Cupid');
  g.day('none');
  g.night({ 0: 12, 1: 12, 2: 12, 3: 12, 4: 4, 7: 13, 10: 15 });
  assert.deepEqual([g.s.alive[12], g.s.alive[13]], [false, false]);
  assert.deepEqual(g.s.morning?.deaths, [12, 13]); assert.deepEqual(g.s.morning?.hearts, []);
  assert.equal(g.s.stats.hearts, undefined, 'no broken heart');
});

test('E-S1: the silenced player is the revealed Mayor: no vote at all that day', () => {
  const g = deal(LW13, 'lonewolves', SEATS);
  g.night({ 0: 10, 1: 10, 2: 10, 3: 3, 4: 0, 5: 11, 6: 12, 7: 11 });
  g.go({ t: 'startDay' }); g.go({ t: 'reveal', seat: 9 }); g.go({ t: 'decide', choice: 'none' }); g.go({ t: 'nextNight' });
  assert.deepEqual(g.s.mayors, [9]);
  g.night({ 0: 11, 1: 11, 2: 11, 3: 3, 4: 1, 5: 4, 6: 8, 7: 4 }, { 2: { silence: 9 } });
  assert.equal(g.table().silenced, 9);
  g.go({ t: 'startDay' }); g.go({ t: 'startVote', open: false });
  assert.equal(g.s.vote!.votes[9], 'abstain');
  g.no({ t: 'vote', seat: 9, choice: 0 }, 'done');
});

test('E-S2, E-S3, E-S5: the Silencer killed that night still silences; a silenced player who dies is not announced; a Silencer who times out silences nobody', () => {
  const k = deal(LW13, 'lonewolves', SEATS);
  k.night({ 0: 10, 1: 10, 2: 10, 3: 3, 4: 0, 5: 11, 6: 2, 7: 11 }, { 2: { silence: 12 } });
  assert.equal(k.s.alive[2], false); assert.equal(k.table().silenced, 12, 'E-S2: killed, his pick counts');
  const d = deal(LW13, 'lonewolves', SEATS);
  d.night({ 0: 10, 1: 10, 2: 10, 3: 3, 4: 0, 5: 11, 6: 12, 7: 11 }, { 2: { silence: 10 } });
  assert.equal(d.s.alive[10], false); assert.equal(d.table().silenced, null, 'E-S3: nothing to announce');
  const t = deal(LW13, 'lonewolves', SEATS);
  for (const [i, c] of [[0, 10], [1, 10], [3, 3], [4, 0], [5, 11], [6, 12], [7, 11]] as const) t.go({ t: 'night', seat: i, choice: c });
  for (const i of [8, 9, 10, 11, 12]) t.go({ t: 'night', seat: i, choice: nightOptions(t.s, i).key === 'none' ? null : nightOptions(t.s, i).opts.find(o => !o.disabled)!.seat });
  assert.equal(t.s.phase, 'night', 'the Silencer is still pending');
  t.go({ t: 'skipPending' });
  assert.equal(t.table().silenced, null, 'E-S5: no silence');
  const n = t.s.log.findLast(e => e.t === 'night');
  assert.ok(n?.t === 'night' && n.silence === null);
});

test('the Mafia with no target left (only the Serial Killer they hit last, "not twice" on): they pick nothing and nobody dies of it (found by the every-combination test)', () => {
  const g = deal(LW9, 'lonewolves', {}, { reveal: false, norep: true, skip: false });
  g.night({ 0: 5, 1: 5, 2: 5, 3: 0, 4: 8, 5: 7 });                 // the Doctor saves him from the Mafia
  g.day('none');
  for (const i of [2, 3, 4, 6, 8]) g.go({ t: 'remove', seat: i });
  assert.equal(nightOptions(g.s, 0).key, 'none', 'their teammates and their last target: nothing to pick');
  g.night({ 5: 0 });
  assert.deepEqual(g.s.alive, [false, true, false, false, false, true, false, false, false]);
  assert.equal(g.s.winner, 'draw');
  assert.deepEqual(JSON.parse(JSON.stringify(g.s)), g.s, 'plain JSON');
});

test('the scripted games replay in both engines (fixtures/records-s21.json; regenerate: UPDATE_FIXTURES=1)', () => {
  if (process.env.UPDATE_FIXTURES) writeFileSync(FILE, JSON.stringify(games) + '\n');
  const saved: GameRecord[] = JSON.parse(readFileSync(FILE, 'utf8'));
  assert.deepEqual(saved, games);
  saved.forEach((r, i) => { const x = replay(r); assert.ok(x.ok, `game ${i + 1}: ${!x.ok && x.error}`); });
  const lw = games.find(r => r.mode === 'lonewolves' && r.roles.length === 11)!;
  const bad = (r: GameRecord, e = 'roles') => { const x = replay(r); assert.equal(x.ok ? 'ok' : x.error, e); };
  bad({ ...JSON.parse(JSON.stringify(lw)), silencer: lw.sheikh });
  const ns = JSON.parse(JSON.stringify(lw)); delete ns.silencer; bad(ns);
  bad({ ...JSON.parse(JSON.stringify(lw)), rv: 2 }, 'roles');
});
