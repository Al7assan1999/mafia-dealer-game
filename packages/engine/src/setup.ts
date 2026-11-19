// Role counts, limits and presets, and dealing a new game.
import type { Counts, GameState, Result, Rng, Role, Rules, Setup } from './types.ts';

export const MIN_PLAYERS = 4, MAX_PLAYERS = 20, MAX_NAME = 18;

/** Two names count as the same when they differ only in case or spacing. */
export const nameKey = (n: string) => String(n).trim().toLowerCase().replace(/\s+/g, ' ');

/** At most this many Mafia for n players: Mafia must be at least 2 fewer than everyone else. */
export const maxMafia = (n: number) => Math.max(1, Math.floor((n - 2) / 2));
/** Would this many Mafia / Detectives still make a game for n players? (the + buttons stop before it would not) */
export const deckOk = (n: number, m: number, d: number) => n >= MIN_PLAYERS && m <= maxMafia(n) && n - m - 1 - d >= 0 && n - 2 * m >= 2;
/** Recommended Mafia for n players: about one in four, inside the limit. */
export const recMafia = (n: number) => Math.max(1, Math.min(Math.round(n / 4), maxMafia(n)));

/** Exactly 1 Doctor; 1-10 Mafia; at most 1 Detective and only with 2+ Mafia. */
function fixCounts(c: Counts): Counts {
  const mafia = Math.max(1, Math.min(10, c.mafia | 0));
  return { mafia, doctor: 1, detective: mafia >= 2 ? Math.min(1, Math.max(0, c.detective | 0)) : 0 };
}

/** The counts pulled back inside the limits for n players (fewer players: fewer Mafia). */
export function normalizeCounts(n: number, counts: Counts): Counts {
  let c = fixCounts(counts);
  if (n >= MIN_PLAYERS) c = fixCounts({ ...c, mafia: Math.min(c.mafia, maxMafia(n)) });
  return c;
}

export type SetupError = 'tooFew' | 'tooManyPlayers' | 'tooManyRoles' | 'mafiaGap' | 'badName' | 'dupNames';

/** Checks a setup. Returns the counts it would really use and the first problem, if any. */
export function validateSetup(names: string[], counts: Counts): { counts: Counts; error: SetupError | null } {
  const n = names.length, c = normalizeCounts(n, counts);
  const err = (error: SetupError) => ({ counts: c, error });
  if (n < MIN_PLAYERS) return err('tooFew');
  if (n > MAX_PLAYERS) return err('tooManyPlayers');
  if (n - c.mafia - c.doctor - c.detective < 0) return err('tooManyRoles');
  if (n - 2 * c.mafia < 2) return err('mafiaGap');
  if (names.some(x => typeof x !== 'string' || !x.trim() || x.trim().length > MAX_NAME)) return err('badName');
  if (new Set(names.map(nameKey)).size < n) return err('dupNames');
  return { counts: c, error: null };
}

export const DEFAULT_RULES: Rules = {
  skip: true, norep: false, saverev: false, decoy: true, self: true, rep: false, reveal: true,
  timer: 180, nightT: 0, ghost: false, skipVote: true,
};
export const PRESETS: Record<'classic' | 'beginner', Partial<Rules>> = {
  classic: { skip: true, norep: false, saverev: false, decoy: true, self: true, rep: false, reveal: true, timer: 180 },
  beginner: { skip: false, norep: false, saverev: true, decoy: true, self: true, rep: false, reveal: true, timer: 240 },
};
export const presetOf = (r: Rules) =>
  (Object.keys(PRESETS) as (keyof typeof PRESETS)[]).find(p => Object.entries(PRESETS[p]).every(([k, v]) => r[k as keyof Rules] === v)) || 'custom';
/** Night timer choices, seconds (0 = off). */
export const NIGHT_TIMES = [0, 30, 45, 60, 90, 120, 180];

/** Fisher-Yates with the given random source. */
export function shuffle<T>(a: T[], rng: Rng): T[] {
  for (let i = a.length - 1; i > 0; i--) { const r = Math.floor(rng() * (i + 1)); [a[i], a[r]] = [a[r], a[i]]; }
  return a;
}

/** Deals a new game (phase 'deal'). `deal` numbers the deals of one table, so stale messages can be told apart. */
export function createGame(setup: Setup, rng: Rng, deal = 1): Result<{ state: GameState }> {
  const v = validateSetup(setup.names, setup.counts);
  if (v.error) return { ok: false, error: v.error };
  const names = setup.names.map(x => x.trim()), rules: Rules = { ...DEFAULT_RULES, ...setup.rules }, deck: Role[] = [];
  for (const r of ['mafia', 'doctor', 'detective'] as const) for (let k = 0; k < v.counts[r]; k++) deck.push(r);
  while (deck.length < names.length) deck.push('citizen');
  const state: GameState = {
    v: 1, deal, names, roles: shuffle(deck, rng), alive: names.map(() => true), rules,
    phase: 'deal', day: 1, night: { mafia: {}, doctor: {}, detective: {}, done: {}, endsAt: 0 },
    skipUsed: false, lastTarget: null, lastProt: {}, morning: null,
    timer: { running: false, left: rules.timer, at: 0 }, vote: null, verdict: null, winner: null,
    log: [], stats: { first: null, kills: [], outs: [], saves: [], caught: [] },
  };
  return { ok: true, state };
}
