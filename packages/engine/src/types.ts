// Shapes of the game. Everything here is plain JSON so a game can be saved (phone, Postgres) and sent as is.

export type Role = 'mafia' | 'doctor' | 'detective' | 'citizen';
export type Winner = 'mafia' | 'citizens';
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

export interface Counts { mafia: number; doctor: number; detective: number }

export interface Setup { names: string[]; counts: Counts; rules: Rules }

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
}

export interface GameState {
  v: 1;
  deal: number;                  // which deal this is (a rematch deals again with deal + 1)
  names: string[];
  roles: Role[];
  alive: boolean[];
  rules: Rules;
  phase: Phase;
  day: number;
  night: {
    mafia: Record<number, NightChoice>;
    doctor: Record<number, number | null>;
    detective: Record<number, number | null>;
    done: Record<number, true>;
    endsAt: number;              // night timer end (ms), 0 = none
  };
  skipUsed: boolean;
  lastTarget: number | null;     // the Mafia's target last night (norep)
  lastProt: Record<number, number | null>;  // each Doctor's pick last night (rep)
  morning: { dead: number | null; saved: number | null } | null;
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
      prot: number[]; checked: number[] }
  | { t: 'day'; day: number; out: number | null; kind: 'out' | 'skipped' | 'tie'; tally: TallyLine[] | null }
  | { t: 'removed'; seat: number }
  | { t: 'win'; winner: Winner; lead: { k: 'killed' | 'votedOut'; seat: number } | null };

/** Everything apply() reports: the history events plus phase changes (for narration). */
export type GameEvent = LogEvent | { t: 'phase'; phase: Phase; day: number };

export type Action =
  | { t: 'begin' }
  | { t: 'night'; seat: number; choice: NightChoice; day?: number }
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
}
export interface NightOptions {
  key: 'mafia' | 'doctor' | 'detective' | 'citizen' | 'none';  // 'none' = nothing to pick (Citizen without decoy)
  opts: NightOption[];
  skip: { mateVotes: number } | null;  // the Mafia's one-time skip, if still allowed
}
