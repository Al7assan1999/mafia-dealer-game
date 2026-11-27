// Game records: the shared test games (fixtures/records.json, also for the Dart engine) and refusing edited records.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { replay, type GameRecord } from '../src/index.ts';
import { play } from './play.ts';

const FILE = new URL('../fixtures/records.json', import.meta.url), SEEDS = 60;
const copy = (r: GameRecord): GameRecord => JSON.parse(JSON.stringify(r));
const refused = (r: GameRecord, error: string | RegExp) => {
  const x = replay(r);
  assert.equal(x.ok, false, 'should be refused');
  if (!x.ok) assert.match(x.error, typeof error === 'string' ? new RegExp('^' + error + '$') : error);
};

test('the shared test games still replay to the same result (regenerate on purpose: UPDATE_FIXTURES=1 npm test)', () => {
  const now = Array.from({ length: SEEDS }, (_, i) => play(i + 1).rec);
  if (process.env.UPDATE_FIXTURES) writeFileSync(FILE, JSON.stringify(now) + '\n');
  const saved: GameRecord[] = JSON.parse(readFileSync(FILE, 'utf8'));
  assert.equal(saved.length, SEEDS);
  saved.forEach((r, i) => { const x = replay(r); assert.ok(x.ok, `game ${i + 1}: ${!x.ok && x.error}`); });
  assert.deepEqual(now, saved, 'the engine plays these games differently now: a rule changed (update the fixtures and the Dart engine)');
});

test('records from before the tie rule (no tieSkip: random tie-breaks) still replay to their result', () => {
  const old: GameRecord[] = JSON.parse(readFileSync(new URL('../fixtures/records-before-tie.json', import.meta.url), 'utf8'));
  assert.equal(old.length, SEEDS);
  assert.ok(old.every(r => !('tieSkip' in r.rules)));
  old.forEach((r, i) => { const x = replay(r); assert.ok(x.ok, `game ${i + 1}: ${!x.ok && x.error}`); });
  assert.ok(old.some(r => r.actions.some(a => a.a.t === 'night' && a.r?.length)), 'some old games broke a Mafia tie at random');
});

test('records from before 1.0.0 (no Sheikh, no modes: ties kill nobody) still replay to their result', () => {
  const old: GameRecord[] = JSON.parse(readFileSync(new URL('../fixtures/records-before-sheikh.json', import.meta.url), 'utf8'));
  assert.equal(old.length, SEEDS);
  assert.ok(old.every(r => r.rules.tieSkip && !('sheikh' in r) && !('mode' in r)));
  old.forEach((r, i) => { const x = replay(r); assert.ok(x.ok, `game ${i + 1}: ${!x.ok && x.error}`); });
});

test('records from 1.0.0 (no rv: the Detective may re-check, the Sniper shoots on night 1, no Bodyguard) still replay', () => {
  const old: GameRecord[] = JSON.parse(readFileSync(new URL('../fixtures/records-1.0.json', import.meta.url), 'utf8'));
  assert.equal(old.length, SEEDS);
  assert.ok(old.every(r => 'sheikh' in r && !('rv' in r) && !r.roles.includes('bodyguard')));
  old.forEach((r, i) => { const x = replay(r); assert.ok(x.ok, `game ${i + 1}: ${!x.ok && x.error}`); });
});

test('records from 1.2 (before the Hunter, the Mayor, the Framer and the Watcher) still replay to their result', () => {
  const old: GameRecord[] = JSON.parse(readFileSync(new URL('../fixtures/records-1.2.json', import.meta.url), 'utf8'));
  assert.equal(old.length, SEEDS);
  assert.ok(old.every(r => r.rv === 2 && !('framer' in r) && !r.roles.some(x => x === 'hunter' || x === 'mayor' || x === 'watcher')));
  old.forEach((r, i) => { const x = replay(r); assert.ok(x.ok, `game ${i + 1}: ${!x.ok && x.error}`); });
});

test('records from 1.3 (rv 2: before the Serial Killer, Cupid, the Silencer and the Mafia ranges of the old modes) still replay', () => {
  const old: GameRecord[] = JSON.parse(readFileSync(new URL('../fixtures/records-1.3.json', import.meta.url), 'utf8'));
  assert.equal(old.length, SEEDS);
  assert.ok(old.every(r => r.rv === 2 && !('silencer' in r)));
  old.forEach((r, i) => { const x = replay(r); assert.ok(x.ok, `game ${i + 1}: ${!x.ok && x.error}`); });
});

test('the shared games cover every mode and every 1.0.0 ending', () => {
  const saved: GameRecord[] = JSON.parse(readFileSync(FILE, 'utf8'));
  for (const m of ['classic', 'sniper', 'jester', 'bodyguard', 'all', 'avenger', 'shadows', 'lovers', 'lonewolves']) assert.ok(saved.some(r => r.mode === m), 'mode ' + m);
  // [Quin Q1] a deal 1.3.x could have made stays rv 2; the new modes and the new counts are rv 3
  assert.ok(saved.every(r => r.rv === 2 || r.rv === 3) && saved.some(r => r.rv === 2) && saved.some(r => r.rv === 3), 'both rule versions');
  assert.ok(saved.every(r => r.rv === 3 || (r.mode !== 'lovers' && r.mode !== 'lonewolves')), 'the new modes are always rv 3');
  assert.ok(saved.some(r => r.log.some(e => e.t === 'night' && e.guard?.length)), 'a Bodyguard on guard');
  for (const w of ['mafia', 'citizens']) assert.ok(saved.some(r => r.winner === w), 'winner ' + w);  // the Jester's win: roles.test.ts
  assert.ok(saved.some(r => r.log.some(e => e.t === 'night' && e.shot != null)), 'a Sniper shot');
});

test('an edited record is refused', () => {
  const g = play(7).rec;
  assert.ok(replay(copy(g)).ok);

  const winner = copy(g); winner.winner = winner.winner === 'mafia' ? 'citizens' : 'mafia'; refused(winner, 'result');
  const log = copy(g); log.log = log.log.slice(1); refused(log, 'result');
  const cut = copy(g); cut.actions.pop(); refused(cut, 'result');
  // a Mafia made a Citizen (and the other way): the night picks no longer fit their roles
  const roles = copy(g), m = roles.roles.indexOf('mafia'), c = roles.roles.indexOf('citizen');
  [roles.roles[m], roles.roles[c]] = [roles.roles[c], roles.roles[m]];
  refused(roles, /^(action \d+: \w+|result|roles)$/);  // roles: the swapped Mafia was the Sheikh
  const extra = copy(g); extra.roles[extra.roles.indexOf('citizen')] = 'doctor'; refused(extra, 'roles');
  const illegal = copy(g); illegal.actions.splice(1, 0, { a: { t: 'nextNight' }, at: illegal.actions[0].at }); refused(illegal, 'action 1: phase');
  const time = copy(g); time.actions[2].at = time.actions[1].at - 1; refused(time, 'action 2: time');
  const draws = copy(g); draws.actions[1].r = [0.5]; refused(draws, 'action 1: random');  // 1.0.0 games draw nothing after the deal
  refused({ ...copy(g), format: 2 } as unknown as GameRecord, 'format');
  refused({ format: 1, actions: [{}] } as unknown as GameRecord, 'shape');
  refused({ ...copy(g), actions: [{ a: null, at: 1 }] } as unknown as GameRecord, 'shape');
  // the Sheikh must be one of the Mafia; a mode without a Sheikh is not a record any version writes
  const sh = copy(g); sh.sheikh = sh.roles.indexOf('citizen'); refused(sh, 'roles');
  const nm = copy(g); delete nm.sheikh; refused(nm, 'roles');
});
