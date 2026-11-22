// A game record: the dealt game plus every action in order, so anyone with this engine can replay it and check it
// (the server checks Wi-Fi games this way, and the Dart engine must replay the same records to the same result).
import { apply } from './game.ts';
import { createGame } from './setup.ts';
import type { Action, Ctx, GameEvent, GameState, LogEvent, Result, Role, Rules, Winner } from './types.ts';

/** One action as it was applied: when (ms) and the random draws it used (tie-breaks), so a replay is exact. */
export interface RecordedAction { a: Action; at: number; r?: number[] }
export interface GameRecord {
  format: 1;
  deal: number; names: string[]; rules: Rules; roles: Role[];
  actions: RecordedAction[];
  winner: Winner | null; log: LogEvent[];  // the result the recorder saw; a replay must reach the same
}

/** A new record for a game just dealt (phase 'deal'). */
export const startRecord = (s: GameState): GameRecord =>
  ({ format: 1, deal: s.deal, names: [...s.names], rules: { ...s.rules }, roles: [...s.roles], actions: [], winner: null, log: [] });

/** apply(), and on success the action joins the record (with its draws) and the record's result follows the game. */
export function step(rec: GameRecord, s: GameState, a: Action, ctx: Ctx): Result<{ state: GameState; events: GameEvent[] }> {
  const r: number[] = [], res = apply(s, a, { now: ctx.now, rng: () => { const x = ctx.rng(); r.push(x); return x; } });
  if (res.ok) {
    rec.actions.push(r.length ? { a, at: ctx.now, r } : { a, at: ctx.now });
    rec.winner = res.state.winner; rec.log = res.state.log;
  }
  return res;
}

/** Replays a record. Refuses one that doesn't hold together: `{ ok: false, error: '<where>: <why>' }`. */
export function replay(rec: GameRecord): Result<{ state: GameState }> {
  try { return check(rec); } catch { return { ok: false, error: 'shape' }; }  // a malformed record from outside
}
function check(rec: GameRecord): Result<{ state: GameState }> {
  const no = (error: string) => ({ ok: false as const, error });
  if (rec?.format !== 1) return no('format');
  if (!Array.isArray(rec.roles) || !Array.isArray(rec.names) || rec.roles.length !== rec.names.length || !Array.isArray(rec.actions)) return no('shape');
  const count = (x: Role) => rec.roles.filter(y => y === x).length;
  if (count('mafia') + count('doctor') + count('detective') + count('citizen') !== rec.roles.length) return no('roles');
  const counts = { mafia: count('mafia'), doctor: count('doctor'), detective: count('detective') };
  const c = createGame({ names: rec.names, counts, rules: rec.rules }, () => 0, rec.deal);
  if (!c.ok) return no('setup: ' + c.error);
  // the dealt roles must be a deck this setup could deal (same counts after the setup's own limits)
  if (c.state.roles.filter(x => x === 'mafia').length !== counts.mafia || c.state.roles.filter(x => x === 'detective').length !== counts.detective
    || counts.doctor !== 1) return no('roles');
  let s: GameState = { ...c.state, roles: [...rec.roles] }, last = -Infinity;
  for (const [i, x] of rec.actions.entries()) {
    if (!Number.isFinite(x?.at) || x.at < last) return no(`action ${i}: time`);
    last = x.at;
    const draws = [...(x.r ?? [])];
    if (draws.some(d => typeof d !== 'number' || !(d >= 0 && d < 1))) return no(`action ${i}: random`);
    let short = false;
    const res = apply(s, x.a, { now: x.at, rng: () => (draws.length ? draws.shift()! : (short = true, 0)) });
    if (!res.ok) return no(`action ${i}: ${res.error}`);
    if (short || draws.length) return no(`action ${i}: random`);
    s = res.state;
  }
  if (s.winner !== rec.winner || JSON.stringify(s.log) !== JSON.stringify(rec.log)) return no('result');
  return { ok: true, state: s };
}
