// Shapes of the game. Everything here is plain JSON so a game can be saved (phone, Postgres) and sent as is.

export type Role = 'mafia' | 'doctor' | 'detective' | 'citizen' | 'sniper' | 'jester' | 'bodyguard' | 'hunter' | 'mayor' | 'watcher';
/** 'jester': the Jester was voted out by day (1.0.0), everyone else loses. */
export type Winner = 'mafia' | 'citizens' | 'jester';
/** A fixed set of roles, one tap (1.0.0). Classic = the counts the table picks; the others are fixed by player count. */
export type Mode = 'classic' | 'sniper' | 'jester' | 'all' | 'bodyguard' | 'avenger' | 'shadows';  // avenger, shadows: 1.3.0
export type Phase = 'deal' | 'night' | 'morning' | 'day' | 'vote' | 'verdict' | 'end';

/** The table rules, frozen into the game when it is dealt. */
export interface Rules {
  skip: boolean;      // the Mafia may skip a kill once per game
  norep: boolean;     // the Mafia can't target the same player two nights in a row
  saverev: boolean;   // the morning names who the Doctor saved
  decoy: boolean;     // Citizens pick someone at night too (ignored), so nobody can tell roles by who taps
  self: boolean;      // the Doctor may protect themselves
  rep: boolean;       // the Doctor can't protect the same player two nights in a row
  reveal: boolean;    // an eliminated player's role is shown
  timer: number;      // discussion timer, seconds
  nightT: number;     // night timer, seconds (0 = none): unfinished turns are skipped after it
  ghost: boolean;     // dead players see every role
  skipVote: boolean;  // false: "no one" votes don't count, the most-voted player is out
  tieSkip: boolean;   // a tied Mafia vote kills nobody (Sprint 7). Records from before it lack the key: random pick
}

export interface Counts { mafia: number; doctor: number; detective: number; sniper?: number; jester?: number; bodyguard?: number; hunter?: number; mayor?: number; watcher?: number }

/** bodyguard: the Sniper and Jester modes' optional Bodyguard (1.1.0, his ruling) */
export interface Setup { names: string[]; counts: Counts; rules: Rules; mode?: Mode; bodyguard?: boolean }

/** Random number in [0, 1). Passed in so a game can be replayed in tests. */
export type Rng = () => number;
/** What an action needs from the outside world. now = milliseconds (Date.now()). */
export interface Ctx { rng: Rng; now: number }

export type NightChoice = number | 'skip' | null;
export type VoteChoice = number | 'none' | 'abstain';

/** Discussion timer: left = seconds at the last change; while running it counts down from `at` (ms). */
export interface Timer { running: boolean; left: number; at: number }

/** One line of the vote count, most votes first: a seat or 'none' (no one). */
export interface TallyLine { k: number | 'none'; n: number }

/** What happened, for the recap, the stats and the MVP. Seats are indexes into names. */
export interface Stats {
  first: number | null;          // first player killed at night
  kills: number[];               // night victims, in order
  outs: number[];                // voted out, in order
  saves: number[];               // a Doctor seat for every save they made
  caught: [number, number][];    // [detective, mafia] pairs the Detective found (each pair once)
  shots?: [number, number][];    // [sniper, target] (1.0.0)
  guards?: [number, number][];   // [bodyguard, guarded]: each time he took a kill or a shot (1.1.0)
  hunts?: [number, number][];    // [hunter, target] (1.3.0)
}

export interface GameState {
  v: 1;
  deal: number;                  // which deal this is (a rematch deals again with deal + 1)
  names: string[];
  roles: Role[];
  alive: boolean[];
  rules: Rules;
  mode?: Mode;                   // 1.0.0; older games are Classic
  /** شيخ المافيا (1.0.0): one Mafia seat, for the whole game (never passed on). His pick wins a tied Mafia vote and the
   *  Detective reads him "not Mafia". Absent in older games: their ties follow tieSkip. */
  sheikh?: number;
  /** الملفّق (1.3.0, Shadows): one Mafia seat other than the Sheikh, for the whole game. Each night he may frame one
   *  player: the Detective reads them Mafia that night. */
  framer?: number;
  /** 1.3.0: the Mayors who revealed themselves (public; their vote counts twice; the Doctor can't pick them) */
  mayors?: number[];
  /** 1.3.0: a dead Hunter taking aim, before the game goes on (from the night or the verdict). endsAt: the night
   *  timer's length again, 0 = none */
  hunt?: { seat: number; from: 'night' | 'day'; endsAt: number } | null;
  /** 2 = the 1.1.0 rules: the Detective never checks a player twice, no Sniper shot on night 1, the Bodyguard.
   *  Absent in older games (they replay by their own rules). */
  rv?: 2;
  phase: Phase;
  day: number;
  night: {
    mafia: Record<number, NightChoice>;
    doctor: Record<number, number | null>;
    detective: Record<number, number | null>;
    sniper?: Record<number, number | 'skip'>;  // 1.0.0: the Sniper's shot, or 'skip' (keeps the bullet)
    bodyguard?: Record<number, number | null>;  // 1.1.0: who each Bodyguard guards
    frame?: Record<number, number | null>;      // 1.3.0: the Framer's frame
    watch?: Record<number, number | null>;      // 1.3.0: who each Watcher watches
    reveal?: Record<number, true>;              // 1.3.0, pass-and-play: a Mayor reveals himself in the morning
    done: Record<number, true>;
    endsAt: number;              // night timer end (ms), 0 = none
  };
  skipUsed: boolean;
  shotUsed?: boolean;            // the Sniper's one bullet is spent
  lastTarget: number | null;     // the Mafia's target last night (norep)
  lastProt: Record<number, number | null>;  // each Doctor's pick last night (rep)
  lastGuard?: Record<number, number | null>;  // 1.1.0: each Bodyguard's pick last night (never the same twice running)
  morning: { dead: number | null; saved: number | null; dead2?: number | null } | null;  // dead2: a second death (the Sniper), seats in order
  timer: Timer;
  vote: { id: number; open: boolean; votes: Record<number, VoteChoice> } | null;
  verdict: { out: number | null; kind: 'out' | 'skipped' | 'tie'; tally: TallyLine[] | null } | null;
  winner: Winner | null;
  log: LogEvent[];               // the game's history, as data (the app writes the text)
  stats: Stats;
}

/** History events (kept in state.log). */
export type LogEvent =
  | { t: 'night'; day: number;
      mafia: { k: 'kill'; seat: number } | { k: 'saved'; seat: number } | { k: 'skip' } | { k: 'none' };
      prot: number[]; checked: number[]; shot?: number; guard?: number[];  // guard: who the Bodyguard guarded (1.1.0)
      // 1.3.0, only in games with the role: read = what each check read (with a Framer, it can't be worked out from the
      // roles afterwards); frame = the Framer's pick and whether a Detective checked it; watch = [watcher, target, visitors]
      read?: boolean[]; frame?: { seat: number; hit: boolean }; watch?: [number, number, number[]][] }
  | { t: 'hunt'; day: number; seat: number; target: number | null; from: 'night' | 'day' }  // 1.3.0: the Hunter's shot (null: held fire)
  | { t: 'reveal'; day: number; seat: number }                        // 1.3.0: a Mayor revealed himself
  | { t: 'day'; day: number; out: number | null; kind: 'out' | 'skipped' | 'tie'; tally: TallyLine[] | null }
  | { t: 'removed'; seat: number }
  | { t: 'win'; winner: Winner; lead: { k: 'killed' | 'votedOut'; seat: number } | null };

/** Everything apply() reports: the history events plus phase changes (for narration). */
export type GameEvent = LogEvent | { t: 'phase'; phase: Phase; day: number };

export type Action =
  | { t: 'begin' }
  | { t: 'night'; seat: number; choice: NightChoice; day?: number; frame?: number | null; reveal?: boolean }  // frame: the Framer (1.3.0); reveal: a Mayor, pass-and-play
  | { t: 'hunt'; seat: number; choice: number | null }  // 1.3.0: the dead Hunter's shot, or null (hold fire)
  | { t: 'reveal'; seat: number }                      // 1.3.0: a Mayor reveals himself (morning or day)
  | { t: 'skipPending'; seats?: number[] }
  | { t: 'startDay' }
  | { t: 'timer'; op: 'start' | 'pause' | 'reset' }
  | { t: 'timer'; op: 'add'; sec: number }
  | { t: 'startVote'; open: boolean }
  | { t: 'vote'; seat: number; choice: number | 'none'; id?: number }
  | { t: 'decide'; choice: number | 'none' }
  | { t: 'nextNight' }
  | { t: 'remove'; seat: number };

export type ActionError = 'phase' | 'seat' | 'dead' | 'done' | 'choice' | 'stale' | 'unknown';

export type Result<T> = ({ ok: true } & T) | { ok: false; error: string };

/** One target button at night, as the player's screen needs it. */
export interface NightOption {
  seat: number;
  disabled: boolean;
  self: boolean;        // "you"
  teammate: boolean;    // another Mafia (shown red, can't be picked)
  lastTarget: boolean;  // norep: the Mafia's target last night
  lastNight: boolean;   // rep: this Doctor's pick last night
  mateVotes: number;    // how many teammates picked this seat
  sheikh: boolean;      // the Sheikh (another Mafia) picked this seat: it wins a tie
  check?: boolean;      // 1.1.0, Detective: checked on an earlier night (true = read Mafia); can't be picked again
  mayor?: boolean;      // 1.3.0, Doctor: a revealed Mayor (can't be protected)
}
export interface NightOptions {
  key: 'mafia' | 'doctor' | 'detective' | 'citizen' | 'sniper' | 'bodyguard' | 'watcher' | 'none';  // 'none' = nothing to pick (Citizen without decoy)
  opts: NightOption[];
  skip: { mateVotes: number; sheikh: boolean } | null;  // the Mafia's one-time skip, if still allowed; the Sniper's "keep the bullet"
  frame?: number[];     // 1.3.0, the Framer: who he may frame (besides his kill vote); null in the action = no frame
  reveal?: boolean;     // 1.3.0, an unrevealed Mayor: he may reveal himself in the morning with this turn
}
