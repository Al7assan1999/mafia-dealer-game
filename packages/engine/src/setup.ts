// Role counts, limits and presets, and dealing a new game.
import type { Counts, GameState, Mode, Result, Rng, Role, Rules, Setup } from './types.ts';

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

/** The modes (1.0.0), in the order the setup shows them, and the fewest players each needs. */
export const MODES: Mode[] = ['classic', 'sniper', 'jester', 'bodyguard', 'all', 'avenger', 'shadows', 'lovers', 'lonewolves'];
export const MODE_MIN: Record<Mode, number> = { classic: 4, sniper: 6, jester: 6, bodyguard: 6, all: 9, avenger: 6, shadows: 8, lovers: 8, lonewolves: 9 };
/** 1.4.0: the Framer and the Silencer, by mode and player count (a Mafia with a power each, like the Sheikh) */
export const hasFramer = (mode: Mode, n: number) => mode === 'shadows' || (mode === 'lonewolves' && n >= 13);
export const hasSilencer = (mode: Mode, n: number) => mode === 'lonewolves' && n >= 11;
export const isMode = (m: unknown): m is Mode => MODES.includes(m as Mode);

/** The deck a mode deals for n players. Classic: the table's counts; the others: fixed by n (Mafia about one in four,
 *  the Detective with 2+ Mafia, plus the mode's own roles). bg: the Sniper and Jester modes' optional Bodyguard (1.1.0). */
export function modeCounts(mode: Mode, n: number, counts: Counts, bg = false, rules: Partial<Rules> = {}, legacy = false): Counts {
  if (mode === 'classic') return normalizeCounts(n, counts);
  const range = mafiaRange(mode, n, rules, legacy);
  const m = !range ? recMafia(n) : Number.isInteger(counts.mafia) && counts.mafia >= range.min && counts.mafia <= range.max ? counts.mafia : range.def;
  if (mode === 'avenger' || mode === 'shadows' || mode === 'lovers' || mode === 'lonewolves') {
    // 1.3.0: Avenger (the Hunter, never the Sniper) and Shadows (the Sniper, never the Hunter), docs/sprint-20-roles.md §5–8;
    // 1.4.0: Lovers (Cupid) and Lone Wolves (the Serial Killer), docs/sprint-21-prd.md
    const c: Counts = { mafia: m, doctor: 1, detective: m >= 2 ? 1 : 0 };
    if (mode === 'avenger') Object.assign(c, { hunter: 1, mayor: n >= 7 ? 1 : 0, jester: n >= 9 ? 1 : 0, bodyguard: n >= 13 ? 1 : 0 });
    else if (mode === 'shadows') Object.assign(c, { watcher: 1, sniper: 1, jester: n >= 10 || m === 2 && n === 9 ? 1 : 0, mayor: n >= 11 ? 1 : 0, bodyguard: n >= 13 ? 1 : 0 });
    else if (mode === 'lovers') Object.assign(c, { cupid: 1, hunter: n >= 9 && n < 17 ? 1 : 0, sniper: n >= 17 ? 1 : 0, jester: n >= 9 ? 1 : 0,
      mayor: n >= 11 ? 1 : 0, bodyguard: n >= 11 ? 1 : 0, watcher: n >= 13 ? 1 : 0 });
    else Object.assign(c, { bodyguard: 1, killer: 1, watcher: n >= 11 ? 1 : 0, jester: n >= 11 ? 1 : 0, mayor: n >= 13 ? 1 : 0, hunter: n >= 17 ? 1 : 0 });
    return c;
  }
  // the Sniper, Jester, Bodyguard and All modes; 1.4.0: the first three with the table's count inside their range
  const mafia = m, withBg = mode === 'bodyguard' || mode === 'all' || (bg && (mode === 'sniper' || mode === 'jester'));
  return { mafia, doctor: 1, detective: mafia >= 2 ? 1 : 0, sniper: mode === 'sniper' || mode === 'all' ? 1 : 0, jester: mode === 'jester' || mode === 'all' ? 1 : 0,
    ...(withBg ? { bodyguard: 1 } : {}) };
}

/** 1.3.0, his rule: how far the table rules lean, against the way the group usually plays (reveal off, the Doctor may
 *  protect himself, decoy on, Reveal saves off). Mafia points minus town points (docs/sprint-20-roles.md §8 C). */
export function lean(r: Partial<Rules>): number {
  return (r.self === false ? 1 : 0) + (r.rep ? 1 : 0) + (r.decoy === false ? 1 : 0) - (r.reveal ? 2 : 0) - (r.saverev ? 1 : 0) - (r.norep ? 1 : 0);
}
/** 1.3.0: the Mafia counts a mode lets the table pick for n players, and the default (§8 B). A lean of 2 or more takes
 *  the higher count away, -2 or less the lower one. Classic and All: null. 1.4.0: Lovers, Lone Wolves, and the Sniper,
 *  Jester and Bodyguard modes (their default is the count they always dealt); legacy: a record from before 1.4.0. */
export function mafiaRange(mode: Mode, n: number, rules: Partial<Rules> = {}, legacy = false): { min: number; max: number; def: number } | null {
  const old = mode === 'sniper' || mode === 'jester' || mode === 'bodyguard';
  if (mode === 'classic' || mode === 'all' || (old && legacy)) return null;
  let [min, max] = mode === 'avenger' || old
    ? (n <= 5 ? [1, 1] : n === 6 ? [1, 2] : n <= 9 ? [2, 2] : n <= 13 ? [2, 3] : n <= 17 ? [3, 4] : [4, 5])
    : mode === 'shadows' ? (n <= 8 ? [2, 2] : n <= 13 ? [2, 3] : n <= 17 ? [3, 4] : [4, 5])
    : mode === 'lovers' ? (n <= 8 ? [2, 2] : n <= 10 ? [2, 3] : n <= 12 ? [3, 3] : n <= 16 ? [3, 4] : [4, 5])
    : (n <= 10 ? [2, 2] : n <= 12 ? [3, 3] : n <= 16 ? [3, 4] : [4, 5]);
  const l = lean(rules);
  if (l >= 2) max = min; else if (l <= -2) min = max;
  return { min, max, def: max };
}

export type SetupError = 'tooFew' | 'tooManyPlayers' | 'tooManyRoles' | 'mafiaGap' | 'badName' | 'dupNames' | 'modeFew' | 'sniperHunter';

/** Checks a setup. Returns the counts it would really use and the first problem, if any. */
export function validateSetup(names: string[], counts: Counts, mode: Mode = 'classic', bg = false, rules: Partial<Rules> = {}, legacy = false): { counts: Counts; error: SetupError | null } {
  const n = names.length, c = modeCounts(mode, n, counts, bg, rules, legacy);
  const err = (error: SetupError) => ({ counts: c, error });
  if (n < MIN_PLAYERS) return err('tooFew');
  if (n > MAX_PLAYERS) return err('tooManyPlayers');
  if (n < MODE_MIN[mode]) return err('modeFew');
  if (n - c.mafia - c.doctor - c.detective - (c.sniper ?? 0) - (c.jester ?? 0) - (c.bodyguard ?? 0) - (c.hunter ?? 0) - (c.mayor ?? 0) - (c.watcher ?? 0) - (c.killer ?? 0) - (c.cupid ?? 0) < 0) return err('tooManyRoles');
  if (c.sniper && c.hunter) return err('sniperHunter');  // his rule (2026-11-26): never both in one game
  if (n - 2 * c.mafia < 2) return err('mafiaGap');
  if (names.some(x => typeof x !== 'string' || !x.trim() || x.trim().length > MAX_NAME)) return err('badName');
  if (new Set(names.map(nameKey)).size < n) return err('dupNames');
  return { counts: c, error: null };
}

export const DEFAULT_RULES: Rules = {
  skip: true, norep: false, saverev: false, decoy: true, self: true, rep: false, reveal: false,  // 1.3.0 (his ruling): off by default, as the group plays
  timer: 180, nightT: 0, ghost: false, skipVote: true, tieSkip: true,
};
export const PRESETS: Record<'classic' | 'beginner', Partial<Rules>> = {
  classic: { skip: true, norep: false, saverev: false, decoy: true, self: true, rep: false, reveal: false, timer: 180 },
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

/** 1.4.0 [Quin Q1]: an old-mode deal that 1.3.x would have dealt the same way stays rv 2, so 1.3.x phones can replay it. */
function sameAsLegacy(setup: Setup, mode: Mode, counts: Counts): boolean {
  if (mode === 'lovers' || mode === 'lonewolves') return false;
  const old = validateSetup(setup.names, setup.counts, mode, !!setup.bodyguard, { ...DEFAULT_RULES, ...setup.rules }, true);
  return !old.error && old.counts.mafia === counts.mafia;
}

/** Deals a new game (phase 'deal'). `deal` numbers the deals of one table, so stale messages can be told apart. */
export function createGame(setup: Setup, rng: Rng, deal = 1): Result<{ state: GameState }> {
  const mode = setup.mode ?? 'classic';
  if (!isMode(mode)) return { ok: false, error: 'mode' };
  const rules0: Rules = { ...DEFAULT_RULES, ...setup.rules }, v = validateSetup(setup.names, setup.counts, mode, !!setup.bodyguard, rules0, !!setup.legacy);
  if (v.error) return { ok: false, error: v.error };
  const names = setup.names.map(x => x.trim()), rules = rules0, deck: Role[] = [];
  // new roles go at the end: the decks (and so the shuffles) of the older modes stay as they were
  for (const r of ['mafia', 'doctor', 'detective', 'sniper', 'jester', 'bodyguard', 'hunter', 'mayor', 'watcher', 'killer', 'cupid'] as const) for (let k = 0; k < (v.counts[r] ?? 0); k++) deck.push(r);
  while (deck.length < names.length) deck.push('citizen');
  const roles = shuffle(deck, rng), mafia = roles.map((r, i) => (r === 'mafia' ? i : -1)).filter(i => i >= 0);
  const state: GameState = {
    v: 1, deal, names, roles, alive: names.map(() => true), rules, mode,
    sheikh: mafia[Math.floor(rng() * mafia.length)],  // one of the Mafia, at random
    rv: setup.legacy || sameAsLegacy(setup, mode, v.counts) ? 2 : 3,  // [Quin Q1] rv 3 only when a 1.3.x phone couldn't replay it
    phase: 'deal', day: 1, night: { mafia: {}, doctor: {}, detective: {}, sniper: {}, done: {}, endsAt: 0 },
    skipUsed: false, shotUsed: false, lastTarget: null, lastProt: {}, morning: null,
    timer: { running: false, left: rules.timer, at: 0 }, vote: null, verdict: null, winner: null,
    log: [], stats: { first: null, kills: [], outs: [], saves: [], caught: [], shots: [] },
  };
  if (hasFramer(mode, names.length)) {  // 1.3.0: the Framer, another Mafia than the Sheikh, at random
    const others = mafia.filter(i => i !== state.sheikh);
    state.framer = others[Math.floor(rng() * others.length)];
  }
  if (hasSilencer(mode, names.length)) {  // 1.4.0: the Silencer, another Mafia than the Sheikh and the Framer
    const others = mafia.filter(i => i !== state.sheikh && i !== state.framer);
    state.silencer = others[Math.floor(rng() * others.length)];
  }
  return { ok: true, state };
}
