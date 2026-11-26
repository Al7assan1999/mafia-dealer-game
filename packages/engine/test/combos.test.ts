// §8 E (his sign-off, 2026-11-26): every mode × every player count × every Mafia count the setup offers × all 64 on/off
// combinations of the six rules that count in the lean. Each must deal a valid deck (inside the range, never the Sniper
// with the Hunter), and its random games must all end with one winner and replay (play.ts checks every step).
// GAMES=50 plays 50 games per combination (about two hours; run before a release); CI plays 1.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mafiaRange, maxMafia, MODE_MIN, MODES, replay, validateSetup, type Rules } from '../src/index.ts';
import { play } from './play.ts';

const GAMES = Number(process.env.GAMES ?? 1), KEYS = ['self', 'rep', 'decoy', 'reveal', 'saverev', 'norep'] as const;

test(`every mode, size, Mafia count and counted-rule combination deals and plays (${GAMES} games each)`, () => {
  let combos = 0, games = 0, seed = 1;
  for (let bits = 0; bits < 64; bits++) {
    const rules = Object.fromEntries(KEYS.map((k, i) => [k, !!(bits & (1 << i))])) as Partial<Rules>;
    for (const mode of MODES) for (let n = MODE_MIN[mode]; n <= 20; n++) {
      const range = mafiaRange(mode, n, rules);
      const counts = mode === 'classic' ? Array.from({ length: maxMafia(n) }, (_, i) => i + 1) : range ? Array.from({ length: range.max - range.min + 1 }, (_, i) => range.min + i) : [0];
      for (const mafia of counts) {
        const names = Array.from({ length: n }, (_, i) => 'P' + i), v = validateSetup(names, { mafia, doctor: 1, detective: 1 }, mode, false, rules);
        assert.equal(v.error, null, `${mode} ${n} ${mafia} ${bits}`);
        assert.ok(!(v.counts.sniper && v.counts.hunter), 'never the Sniper and the Hunter');
        if (range) assert.equal(v.counts.mafia, mafia, 'the offered count is the dealt count');
        combos++;
        for (let k = 0; k < GAMES; k++, games++) {
          const g = play(seed++, { n, mode, mafia, rules });
          assert.ok(g.state.winner, 'it ended');
          const r = replay(JSON.parse(JSON.stringify(g.rec)));
          assert.ok(r.ok, `${mode} ${n} ${mafia} ${bits}: ${!r.ok && r.error}`);
        }
      }
    }
  }
  console.log(`${combos} combinations, ${games} games`);
  assert.ok(combos > 10_000);
});
