// 1.1.1 hotfix: an out player (the host too) follows the vote live, open or secret; the living see a secret vote's
// count only. The Dart engine does the same (engine_dart/test/hotfix111_test.dart).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { viewFor, type GameState, type SeatView } from '../src/index.ts';
import { game } from './util.ts';

test('1.1.1: an out seat sees every vote as it comes in; a living seat only the count in a secret vote', () => {
  const s0 = game(['mafia', 'doctor', 'citizen', 'citizen', 'citizen', 'mafia']);
  const s: GameState = { ...s0, phase: 'vote', alive: [true, true, false, true, true, true], vote: { id: 7, open: false, votes: { 0: 3, 4: 'none' } } };
  const out = viewFor(s, 2, 0) as SeatView, alive = viewFor(s, 3, 0) as SeatView;
  assert.equal(out.ph, 'dead');
  assert.deepEqual(out.board, [{ seat: 0, v: 3 }, { seat: 1, v: null }, { seat: 3, v: null }, { seat: 4, v: 'none' }, { seat: 5, v: null }]);
  assert.equal(alive.board, null, 'a secret vote stays secret for the living');
  assert.equal(viewFor(s, 'table', 0).board, null);
  assert.equal((viewFor({ ...s, phase: 'day', vote: null }, 2, 0) as SeatView).board, null, 'only during the vote');
});
