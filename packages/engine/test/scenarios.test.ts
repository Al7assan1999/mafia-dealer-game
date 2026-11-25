// Full games ported from the app's Playwright tests: test7.js (7 one-phone games) and test9.js (norep + saverev).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, DEFAULT_RULES, nightOptions, seeded, type GameState } from '../src/index.ts';
import { must, N6 } from './util.ts';

const deal = (seed: number, rules = {}, counts = { mafia: 2, doctor: 1, detective: 1 }) => {
  const r = createGame({ names: N6, counts, rules: { ...DEFAULT_RULES, ...rules } }, seeded(seed));
  assert.ok(r.ok); return must(r.state, { t: 'begin' }).state;
};
const alive = (s: GameState) => s.alive.map((a, i) => (a ? i : -1)).filter(i => i >= 0);

test('test7: seven full games end with a winner and a consistent history', () => {
  const winners: string[] = [];
  for (let i = 0; i < 7; i++) {
    let s = deal(i + 1), nights = 0;
    for (let n = 0; n < 8 && s.phase !== 'end'; n++) {
      const order = alive(s);
      for (const [k, p] of order.entries()) {
        if (s.phase !== 'night') break;
        const no = nightOptions(s, p), opts = no.opts.filter(o => !o.disabled).map(o => o.seat);
        const det = s.roles[p] === 'detective' && i % 2 === 0 ? s.roles.indexOf('mafia') : -1;
        const choice = no.key === 'none' ? null : det >= 0 && opts.includes(det) ? det : opts[(i + n + k) % opts.length];
        s = must(s, { t: 'night', seat: p, choice }).state;
      }
      nights++;
      if (s.phase === 'end') break;
      s = must(s, { t: 'startDay' }).state;
      const tgt = i % 2 ? s.roles.findIndex((r, x) => r !== 'mafia' && s.alive[x]) : s.roles.findIndex((r, x) => r === 'mafia' && s.alive[x]);
      s = must(s, { t: 'decide', choice: tgt }).state;
      if (s.phase === 'end') break;
      s = must(s, { t: 'nextNight' }).state;
    }
    assert.equal(s.phase, 'end', 'game ' + i + ' ended');
    assert.equal(s.log.filter(e => e.t === 'night').length, nights);
    assert.equal(s.log.at(-1)!.t, 'win');
    winners.push(s.winner!);
  }
  assert.equal(winners.length, 7);
});

test('test9: norep + saverev — a saved target is named, and the Mafia can\'t pick them the next night', () => {
  let s = deal(3, { norep: true, saverev: true });
  const tgt = s.roles.indexOf('citizen');
  for (const p of alive(s)) {
    const r = s.roles[p], no = nightOptions(s, p);
    const choice = no.key === 'none' ? null : r === 'mafia' || r === 'doctor' ? tgt : no.opts.find(o => !o.disabled)!.seat;
    s = must(s, { t: 'night', seat: p, choice }).state;
  }
  assert.deepEqual(s.morning, { dead: null, saved: tgt, dead2: null });
  s = must(must(must(s, { t: 'startDay' }).state, { t: 'decide', choice: 'none' }).state, { t: 'nextNight' }).state;
  for (const m of alive(s).filter(i => s.roles[i] === 'mafia')) {
    const o = nightOptions(s, m).opts.find(x => x.seat === tgt)!;
    assert.ok(o.disabled && o.lastTarget, 'night 2 target disabled for Mafia ' + m);
  }
});
