// Role counts and limits (ported from the app's tests/multiplayer/test_rules.js) and dealing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, DEFAULT_RULES, deckOk, maxMafia, PRESETS, presetOf, recMafia, seeded, validateSetup } from '../src/index.ts';
import { N6 } from './util.ts';

const names = (n: number) => Array.from({ length: n }, (_, i) => 'P' + (i + 1));
const c = (mafia: number, detective = 0, doctor = 1) => ({ mafia, doctor, detective });

test('4 players, 1 Mafia: valid, exactly 1 Doctor, no Detective', () => {
  const r = validateSetup(names(4), c(1, 1, 3));
  assert.deepEqual(r, { counts: c(1, 0, 1), error: null });
});
test('4 players allow only 1 Mafia; 5 players with 2 Mafia are pulled back to 1', () => {
  assert.equal(maxMafia(4), 1);
  assert.equal(validateSetup(names(4), c(2)).counts.mafia, 1);
  assert.deepEqual(validateSetup(names(5), c(2)), { counts: c(1), error: null });
  assert.equal(deckOk(5, 2, 0), false);
});
test('6 players, 2 Mafia: valid; the Detective comes only with 2+ Mafia and only one', () => {
  assert.deepEqual(validateSetup(names(6), c(2, 1)), { counts: c(2, 1), error: null });
  assert.equal(validateSetup(names(6), c(2, 2)).counts.detective, 1);
  assert.equal(validateSetup(names(6), c(1, 1)).counts.detective, 0);
});
test('recommended Mafia respects the limit', () => {
  assert.equal(recMafia(5), 1); assert.equal(recMafia(10), 3); assert.equal(recMafia(6), 2);
  for (let n = 4; n <= 20; n++) assert.ok(deckOk(n, recMafia(n), 0), 'n=' + n);
});
test('setup errors', () => {
  assert.equal(validateSetup(names(3), c(1)).error, 'tooFew');
  assert.equal(validateSetup(names(21), c(1)).error, 'tooManyPlayers');
  assert.equal(validateSetup(['Sami', ' sami ', 'A', 'B'], c(1)).error, 'dupNames');
  assert.equal(validateSetup(['', 'A', 'B', 'C'], c(1)).error, 'badName');
  assert.equal(validateSetup(['x'.repeat(19), 'A', 'B', 'C'], c(1)).error, 'badName');
  assert.equal(validateSetup(names(20), c(9)).error, null);
});
test('the deck: the right counts, shuffled, the same for the same seed', () => {
  const g = (seed: number) => { const r = createGame({ names: N6, counts: c(2, 1), rules: DEFAULT_RULES }, seeded(seed)); assert.ok(r.ok); return r.state; };
  const a = g(7), b = g(7);
  assert.deepEqual(a.roles, b.roles);
  assert.deepEqual([...a.roles].sort(), ['citizen', 'citizen', 'detective', 'doctor', 'mafia', 'mafia']);
  assert.ok([1, 2, 3, 4, 5].some(s => g(s).roles.join() !== a.roles.join()), 'different seeds deal differently');
  assert.equal(a.phase, 'deal'); assert.equal(a.day, 1); assert.ok(a.alive.every(Boolean));
  const bad = createGame({ names: N6.slice(0, 3), counts: c(1), rules: DEFAULT_RULES }, seeded(1));
  assert.deepEqual(bad, { ok: false, error: 'tooFew' });
});
test('presets', () => {
  assert.equal(presetOf({ ...DEFAULT_RULES, ...PRESETS.classic }), 'classic');
  assert.equal(presetOf({ ...DEFAULT_RULES, ...PRESETS.beginner }), 'beginner');
  assert.equal(presetOf({ ...DEFAULT_RULES, timer: 100 }), 'custom');
});
