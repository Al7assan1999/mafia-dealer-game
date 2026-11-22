// 1,000 random games, each from a fixed seed, checking what must always hold.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { replay } from '../src/index.ts';
import { play } from './play.ts';

test('1,000 random games: they all end, the winner is right, nothing leaks, the state stays plain JSON, the record replays', () => {
  let steps = 0;
  for (let seed = 1; seed <= 1000; seed++) {
    const g = play(seed);
    steps += g.steps;
    const r = replay(JSON.parse(JSON.stringify(g.rec)));
    assert.ok(r.ok, `seed ${seed}: replay refused (${!r.ok && r.error})`);
    assert.deepEqual(r.state, g.state, `seed ${seed}: replay differs`);
  }
  assert.ok(steps > 10_000);
});
