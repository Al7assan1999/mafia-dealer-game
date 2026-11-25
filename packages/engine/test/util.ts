import assert from 'node:assert/strict';
import { apply, createGame, DEFAULT_RULES, seeded, type Action, type GameEvent, type GameState, type Role, type Rules } from '../src/index.ts';

export const N6 = ['Dareer', 'Halawy', 'Farouq', 'Sami', 'Hokan', 'Khaddour'];
export const ctx = (seed = 1, now = 1_000_000) => ({ rng: seeded(seed), now });

/** A game in the night of day 1 with these exact roles (seat i gets roles[i]). */
export function game(roles: Role[], rules: Partial<Rules> = {}, now = 1_000_000): GameState {
  const names = roles.map((_, i) => 'P' + (i + 1));
  const m = roles.filter(r => r === 'mafia').length, d = roles.filter(r => r === 'detective').length;
  const r = createGame({ names, counts: { mafia: m, doctor: 1, detective: d }, rules: { ...DEFAULT_RULES, ...rules } }, seeded(1));
  assert.ok(r.ok, 'setup: ' + (!r.ok && r.error));
  const s = { ...r.state, roles: roles.slice() };
  return must(s, { t: 'begin' }, now).state;
}

/** The same game as dealt before 1.0.0: no Sheikh, so ties follow the game's own tie rule. */
export function legacy(s: GameState): GameState {
  const t: GameState = JSON.parse(JSON.stringify(s));
  delete t.sheikh; delete t.mode; delete t.shotUsed; delete t.night.sniper; delete t.stats.shots;
  return t;
}

/** apply() that must succeed. */
export function must(s: GameState, a: Action, now = 1_000_000, seed = 1): { state: GameState; events: GameEvent[] } {
  const r = apply(s, a, { rng: seeded(seed), now });
  assert.ok(r.ok, `${a.t} failed: ${!r.ok && r.error}`);
  return r;
}
/** apply() that must fail with this error. */
export function refuse(s: GameState, a: Action, error: string, now = 1_000_000) {
  const r = apply(s, a, { rng: seeded(1), now });
  assert.equal(r.ok ? 'ok' : r.error, error);
}

/** Plays the night: picks[seat] = choice; seats not listed pick the first allowed option (or nothing). */
export function night(s: GameState, picks: Record<number, number | 'skip'> = {}, seed = 1): GameState {
  for (const i of s.alive.map((a, i) => (a ? i : -1)).filter(i => i >= 0)) {
    if (s.phase !== 'night') break;
    if (s.night.done[i]) continue;
    let c: number | 'skip' | null = picks[i] ?? null;
    if (c == null) { const o = apply(s, { t: 'night', seat: i, choice: null }, ctx()); if (o.ok) { s = o.state; continue; } }
    if (c == null) c = firstOpt(s, i);
    s = must(s, { t: 'night', seat: i, choice: c }, 1_000_000, seed).state;
  }
  return s;
}
export function firstOpt(s: GameState, i: number): number {
  for (let j = 0; j < s.names.length; j++) { const r = apply(s, { t: 'night', seat: i, choice: j }, ctx()); if (r.ok) return j; }
  throw new Error('no option for seat ' + i);
}
