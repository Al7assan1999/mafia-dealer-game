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

test('an edited record is refused', () => {
  const g = play(7).rec;
  assert.ok(replay(copy(g)).ok);

  const winner = copy(g); winner.winner = winner.winner === 'mafia' ? 'citizens' : 'mafia'; refused(winner, 'result');
  const log = copy(g); log.log = log.log.slice(1); refused(log, 'result');
  const cut = copy(g); cut.actions.pop(); refused(cut, 'result');
  // a Mafia made a Citizen (and the other way): the night picks no longer fit their roles
  const roles = copy(g), m = roles.roles.indexOf('mafia'), c = roles.roles.indexOf('citizen');
  [roles.roles[m], roles.roles[c]] = [roles.roles[c], roles.roles[m]];
  refused(roles, /^(action \d+: \w+|result)$/);
  const extra = copy(g); extra.roles[extra.roles.indexOf('citizen')] = 'doctor'; refused(extra, 'roles');
  const illegal = copy(g); illegal.actions.splice(1, 0, { a: { t: 'nextNight' }, at: illegal.actions[0].at }); refused(illegal, 'action 1: phase');
  const time = copy(g); time.actions[2].at = time.actions[1].at - 1; refused(time, 'action 2: time');
  const draws = copy(g), k = draws.actions.findIndex(x => x.r);
  draws.actions[k].r!.push(0.5); refused(draws, `action ${k}: random`);
  refused({ ...copy(g), format: 2 } as unknown as GameRecord, 'format');
  refused({ format: 1, actions: [{}] } as unknown as GameRecord, 'shape');
  refused({ ...copy(g), actions: [{ a: null, at: 1 }] } as unknown as GameRecord, 'shape');
});
