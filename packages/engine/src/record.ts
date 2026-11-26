// A game record: the dealt game plus every action in order, so anyone with this engine can replay it and check it
// (the server checks Wi-Fi games this way, and the Dart engine must replay the same records to the same result).
import { apply } from './game.ts';
import { createGame } from './setup.ts';
import type { Action, Ctx, GameEvent, GameState, LogEvent, Mode, Result, Role, Rules, Winner } from './types.ts';

/** One action as it was applied: when (ms) and the random draws it used (tie-breaks), so a replay is exact. */
export interface RecordedAction { a: Action; at: number; r?: number[] }
export interface GameRecord {
  format: 1;
  deal: number; names: string[]; rules: Rules; roles: Role[];
  mode?: Mode; sheikh?: number;  // 1.0.0; older records are Classic with no Sheikh (their own tie rule)
  framer?: number;               // 1.3.0, Shadows
  rv?: 2;                        // 1.1.0 rules (GameState.rv); older records replay by their own
  actions: RecordedAction[];
  winner: Winner | null; log: LogEvent[];  // the result the recorder saw; a replay must reach the same
}

/** A new record for a game just dealt (phase 'deal'). */
export const startRecord = (s: GameState): GameRecord =>
  ({ format: 1, deal: s.deal, names: [...s.names], rules: { ...s.rules }, roles: [...s.roles],
    ...(s.sheikh !== undefined ? { mode: s.mode ?? 'classic', sheikh: s.sheikh } : {}), ...(s.framer !== undefined ? { framer: s.framer } : {}),
    ...(s.rv !== undefined ? { rv: s.rv } : {}),
    actions: [], winner: null, log: [] });

/** apply(), and on success the action joins the record (with its draws) and the record's result follows the game. */
export function step(rec: GameRecord, s: GameState, a: Action, ctx: Ctx): Result<{ state: GameState; events: GameEvent[] }> {
  const r: number[] = [], res = apply(s, a, { now: ctx.now, rng: () => { const x = ctx.rng(); r.push(x); return x; } });
  if (res.ok) {
    rec.actions.push(r.length ? { a, at: ctx.now, r } : { a, at: ctx.now });
    rec.winner = res.state.winner; rec.log = res.state.log;
  }
  return res;
}

/** A record's rules. Records made before the tie rule (Sprint 7) have no `tieSkip`: their ties were random picks. */
export const recordRules = (r: Partial<Rules>): Rules => ({ tieSkip: false, ...r } as Rules);

/** Replays a record. Refuses one that doesn't hold together: `{ ok: false, error: '<where>: <why>' }`. */
export function replay(rec: GameRecord): Result<{ state: GameState }> {
  try { return check(rec); } catch { return { ok: false, error: 'shape' }; }  // a malformed record from outside
}
function check(rec: GameRecord): Result<{ state: GameState }> {
  const no = (error: string) => ({ ok: false as const, error });
  if (rec?.format !== 1) return no('format');
  if (!Array.isArray(rec.roles) || !Array.isArray(rec.names) || rec.roles.length !== rec.names.length || !Array.isArray(rec.actions)) return no('shape');
  const count = (x: Role) => rec.roles.filter(y => y === x).length, all: Role[] = ['mafia', 'doctor', 'detective', 'citizen', 'sniper', 'jester', 'bodyguard', 'hunter', 'mayor', 'watcher'];
  if (all.reduce((n, x) => n + count(x), 0) !== rec.roles.length) return no('roles');
  const old = rec.sheikh === undefined;  // before 1.0.0: Classic, no Sheikh
  if (old ? rec.mode !== undefined : !(Number.isInteger(rec.sheikh) && rec.roles[rec.sheikh!] === 'mafia' && typeof rec.mode === 'string')) return no('roles');
  // 1.1.0: rv only with a Sheikh; the Bodyguard only in a 1.1.0 game
  if (rec.rv !== undefined && (rec.rv !== 2 || old)) return no('format');
  if (rec.rv === undefined && (count('bodyguard') || rec.mode === 'bodyguard')) return no('roles');
  // 1.3.0: the new roles and modes only in a 1.1.0+ game; the Framer only in Shadows, a Mafia other than the Sheikh
  const fresh = count('hunter') + count('mayor') + count('watcher') > 0 || rec.mode === 'avenger' || rec.mode === 'shadows';
  if (fresh && rec.rv === undefined) return no('roles');
  if (rec.mode === 'shadows' ? !(Number.isInteger(rec.framer) && rec.roles[rec.framer!] === 'mafia' && rec.framer !== rec.sheikh) : rec.framer !== undefined) return no('roles');
  const counts = { mafia: count('mafia'), doctor: count('doctor'), detective: count('detective'), sniper: count('sniper'), jester: count('jester'), bodyguard: count('bodyguard') };
  const c = createGame({ names: rec.names, counts, rules: recordRules(rec.rules), mode: rec.mode, bodyguard: count('bodyguard') > 0 }, () => 0, rec.deal);
  if (!c.ok) return no('setup: ' + c.error);
  // the dealt roles must be a deck this setup could deal (same counts after the setup's own limits)
  // (a 1.0.0 "All roles" deck had a Citizen where 1.1.0 deals the Bodyguard)
  const pre = rec.rv === undefined, dealt = (x: Role) => c.state.roles.filter(y => y === x || (pre && x === 'citizen' && y === 'bodyguard')).length;
  if (all.some(x => (pre && x === 'bodyguard' ? 0 : dealt(x)) !== count(x))) return no('roles');
  let s: GameState = { ...c.state, roles: [...rec.roles], sheikh: rec.sheikh, ...(rec.framer !== undefined ? { framer: rec.framer } : {}) }, last = -Infinity;
  if (old) { delete s.sheikh; delete s.mode; delete s.shotUsed; delete s.night.sniper; delete s.stats.shots; }
  if (rec.rv === undefined) delete s.rv;
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
