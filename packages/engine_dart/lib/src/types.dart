// Shapes of the game: the Dart copy of packages/engine/src/types.ts. JSON keys and their order match the TypeScript
// objects exactly, so records written by either engine are byte-identical.
import 'dart:collection';

enum Role { mafia, doctor, detective, citizen, sniper, jester, bodyguard, hunter, mayor, watcher } // hunter, mayor, watcher: 1.3.0

/// jester: the Jester was voted out by day (1.0.0), everyone else loses.
enum Winner { mafia, citizens, jester }

/// A fixed set of roles, one tap (1.0.0): 'classic' | 'sniper' | 'jester' | 'bodyguard' (1.1.0) | 'all' | 'avenger' | 'shadows' (1.3.0).
typedef Mode = String;

enum Phase { deal, night, morning, day, vote, verdict, end }

/// Random number in [0, 1).
typedef Rng = double Function();

class Ctx {
  final Rng rng;
  final int now; // ms
  const Ctx(this.rng, this.now);
}

/// The table rules, frozen into the game when it is dealt.
class Rules {
  final bool skip, norep, saverev, decoy, self, rep, reveal;
  final int timer, nightT;
  final bool ghost, skipVote;
  /// A tied Mafia vote kills nobody (Sprint 7). Records from before it lack the key: random pick ([recordRules]).
  final bool tieSkip;
  const Rules({
    required this.skip, required this.norep, required this.saverev, required this.decoy, required this.self,
    required this.rep, required this.reveal, required this.timer, required this.nightT, required this.ghost,
    required this.skipVote, this.tieSkip = true,
  });

  Map<String, Object?> toJson() => {
        'skip': skip, 'norep': norep, 'saverev': saverev, 'decoy': decoy, 'self': self, 'rep': rep,
        'reveal': reveal, 'timer': timer, 'nightT': nightT, 'ghost': ghost, 'skipVote': skipVote, 'tieSkip': tieSkip,
      };

  /// [over] replaces some fields (like `{...rules, ...over}`); throws on a wrong type.
  Rules merge(Map<String, Object?> over) {
    final m = {...toJson(), ...over};
    bool b(String k) => m[k] as bool;
    int i(String k) => (m[k] as num).toInt();
    return Rules(skip: b('skip'), norep: b('norep'), saverev: b('saverev'), decoy: b('decoy'), self: b('self'),
        rep: b('rep'), reveal: b('reveal'), timer: i('timer'), nightT: i('nightT'), ghost: b('ghost'), skipVote: b('skipVote'), tieSkip: b('tieSkip'));
  }
}

class Counts {
  final int mafia, doctor, detective, sniper, jester, bodyguard, hunter, mayor, watcher;
  const Counts(this.mafia, this.doctor, this.detective,
      {this.sniper = 0, this.jester = 0, this.bodyguard = 0, this.hunter = 0, this.mayor = 0, this.watcher = 0});
  @override
  bool operator ==(Object o) =>
      o is Counts && o.mafia == mafia && o.doctor == doctor && o.detective == detective && o.sniper == sniper && o.jester == jester &&
      o.bodyguard == bodyguard && o.hunter == hunter && o.mayor == mayor && o.watcher == watcher;
  @override
  int get hashCode => Object.hash(mafia, doctor, detective, sniper, jester, bodyguard, hunter, mayor, watcher);
  @override
  String toString() =>
      'Counts($mafia, $doctor, $detective, sniper: $sniper, jester: $jester, bodyguard: $bodyguard, hunter: $hunter, mayor: $mayor, watcher: $watcher)';
}

class Setup {
  final List<String> names;
  final Counts counts;
  final Rules rules;
  final Mode mode;
  final bool bodyguard; // the Sniper and Jester modes' optional Bodyguard (1.1.0, his ruling)
  const Setup(this.names, this.counts, this.rules, [this.mode = 'classic', this.bodyguard = false]);
}

/// Discussion timer: left = seconds at the last change; while running it counts down from `at` (ms).
class DayTimer {
  final bool running;
  final int left, at;
  const DayTimer(this.running, this.left, this.at);
}

/// One line of the vote count, most votes first: a seat (int) or 'none'.
class TallyLine {
  final Object k;
  final int n;
  const TallyLine(this.k, this.n);
  Map<String, Object?> toJson() => {'k': k, 'n': n};
}

class Stats {
  int? first;
  final List<int> kills, outs, saves;
  final List<(int, int)> caught; // (detective, mafia)
  final List<(int, int)> shots; // (sniper, target), 1.0.0
  final List<(int, int)> guards; // (bodyguard, guarded): each time he took a kill or a shot (1.1.0)
  final List<(int, int)> hunts; // (hunter, target) (1.3.0)
  Stats({this.first, List<int>? kills, List<int>? outs, List<int>? saves, List<(int, int)>? caught, List<(int, int)>? shots, List<(int, int)>? guards,
      List<(int, int)>? hunts})
      : kills = kills ?? [], outs = outs ?? [], saves = saves ?? [], caught = caught ?? [], shots = shots ?? [], guards = guards ?? [], hunts = hunts ?? [];
  Stats copy() => Stats(first: first, kills: [...kills], outs: [...outs], saves: [...saves], caught: [...caught], shots: [...shots], guards: [...guards],
      hunts: [...hunts]);
}

class Night {
  final SplayTreeMap<int, Object> mafia; // seat -> target seat or 'skip'
  final SplayTreeMap<int, int?> doctor, detective;
  final SplayTreeMap<int, Object> sniper; // 1.0.0: the Sniper's shot (seat) or 'skip' (keeps the bullet)
  final SplayTreeMap<int, int?> bodyguard; // 1.1.0: who each Bodyguard guards
  final SplayTreeMap<int, int?> frame, watch; // 1.3.0: the Framer's frame; who each Watcher watches
  final SplayTreeSet<int> reveal; // 1.3.0, pass-and-play: a Mayor reveals himself in the morning
  final Set<int> done;
  int endsAt; // night timer end (ms), 0 = none
  Night({SplayTreeMap<int, Object>? mafia, SplayTreeMap<int, int?>? doctor, SplayTreeMap<int, int?>? detective,
      SplayTreeMap<int, Object>? sniper, SplayTreeMap<int, int?>? bodyguard, SplayTreeMap<int, int?>? frame, SplayTreeMap<int, int?>? watch,
      SplayTreeSet<int>? reveal, Set<int>? done, this.endsAt = 0})
      : mafia = mafia ?? SplayTreeMap(), doctor = doctor ?? SplayTreeMap(), detective = detective ?? SplayTreeMap(),
        sniper = sniper ?? SplayTreeMap(), bodyguard = bodyguard ?? SplayTreeMap(), frame = frame ?? SplayTreeMap(),
        watch = watch ?? SplayTreeMap(), reveal = reveal ?? SplayTreeSet(), done = done ?? {};
  Night copy() => Night(mafia: SplayTreeMap.of(mafia), doctor: SplayTreeMap.of(doctor), detective: SplayTreeMap.of(detective),
      sniper: SplayTreeMap.of(sniper), bodyguard: SplayTreeMap.of(bodyguard), frame: SplayTreeMap.of(frame), watch: SplayTreeMap.of(watch),
      reveal: SplayTreeSet.of(reveal), done: {...done}, endsAt: endsAt);
}

class Morning {
  final int? dead, saved;
  final int? dead2; // a second death (the Sniper), seats in order (1.0.0)
  const Morning(this.dead, this.saved, [this.dead2]);
}

class Vote {
  final int id;
  final bool open;
  final SplayTreeMap<int, Object> votes; // seat -> seat, 'none' or 'abstain'
  Vote(this.id, this.open, [SplayTreeMap<int, Object>? votes]) : votes = votes ?? SplayTreeMap();
  Vote copy() => Vote(id, open, SplayTreeMap.of(votes));
}

class Verdict {
  final int? out;
  final String kind; // 'out' | 'skipped' | 'tie'
  final List<TallyLine>? tally;
  const Verdict(this.out, this.kind, this.tally);
}

class GameState {
  final int v = 1;
  int deal;
  List<String> names;
  List<Role> roles;
  List<bool> alive;
  Rules rules;
  Mode mode; // 1.0.0; older games are 'classic'
  /// شيخ المافيا (1.0.0): one Mafia seat for the whole game (never passed on). His pick wins a tied Mafia vote and the
  /// Detective reads him "not Mafia". Null in older games: their ties follow tieSkip.
  int? sheikh;
  /// الملفّق (1.3.0, Shadows): one Mafia seat other than the Sheikh, for the whole game; frames one player a night.
  int? framer;
  /// 1.3.0: the Mayors who revealed themselves (their vote counts twice; the Doctor can't pick them).
  List<int> mayors;
  /// 1.3.0: a dead Hunter taking aim before the game goes on (from 'night' or 'day'); endsAt: the night timer again, 0 = none.
  ({int seat, String from, int endsAt})? hunt;
  /// 2 = the 1.1.0 rules: the Detective never checks a player twice, no Sniper shot on night 1, the Bodyguard.
  /// Null in older games (they replay by their own rules).
  int? rv;
  Phase phase;
  int day;
  Night night;
  bool skipUsed;
  bool shotUsed; // the Sniper's one bullet is spent
  int? lastTarget;
  SplayTreeMap<int, int?> lastProt;
  SplayTreeMap<int, int?> lastGuard; // 1.1.0: each Bodyguard's pick last night (never the same twice running)
  Morning? morning;
  DayTimer timer;
  Vote? vote;
  Verdict? verdict;
  Winner? winner;
  List<GameEvent> log; // history events only
  Stats stats;

  GameState({
    required this.deal, required this.names, required this.roles, required this.alive, required this.rules,
    this.mode = 'classic', this.sheikh, this.framer, List<int>? mayors, this.hunt, this.rv, this.shotUsed = false, SplayTreeMap<int, int?>? lastGuard,
    required this.phase, required this.day, required this.night, required this.skipUsed, required this.lastTarget,
    required this.lastProt, required this.morning, required this.timer, required this.vote, required this.verdict,
    required this.winner, required this.log, required this.stats,
  }) : lastGuard = lastGuard ?? SplayTreeMap(), mayors = mayors ?? [];

  GameState copy() => GameState(
        deal: deal, names: [...names], roles: [...roles], alive: [...alive], rules: rules, mode: mode, sheikh: sheikh, rv: rv,
        framer: framer, mayors: [...mayors], hunt: hunt,
        shotUsed: shotUsed, lastGuard: SplayTreeMap.of(lastGuard), phase: phase, day: day,
        night: night.copy(), skipUsed: skipUsed, lastTarget: lastTarget, lastProt: SplayTreeMap.of(lastProt),
        morning: morning, timer: timer, vote: vote?.copy(), verdict: verdict, winner: winner, log: [...log],
        stats: stats.copy(),
      );
}

/// What apply() reports: the history events (also kept in state.log) and phase changes (for narration).
sealed class GameEvent {
  const GameEvent();
  Map<String, Object?> toJson();
}

class NightLog extends GameEvent {
  final int day;
  final String k; // 'kill' | 'saved' | 'skip' | 'none'
  final int? seat;
  final List<int> prot, checked;
  final int? shot; // the Sniper's target (1.0.0)
  final List<int>? guard; // who the Bodyguard guarded (1.1.0)
  // 1.3.0, only in games with the role: what each check read; the Framer's pick and whether it was checked;
  // (watcher, target, visitors)
  final List<bool>? read;
  final ({int seat, bool hit})? frame;
  final List<(int, int, List<int>)>? watch;
  const NightLog(this.day, this.k, this.seat, this.prot, this.checked, [this.shot, this.guard, this.read, this.frame, this.watch]);
  @override
  Map<String, Object?> toJson() => {
        't': 'night', 'day': day, 'mafia': seat == null ? {'k': k} : {'k': k, 'seat': seat}, 'prot': prot, 'checked': checked,
        if (shot != null) 'shot': shot,
        if (guard != null) 'guard': guard,
        if (read != null) 'read': read,
        if (frame != null) 'frame': {'seat': frame!.seat, 'hit': frame!.hit},
        if (watch != null) 'watch': [for (final (w, t, vs) in watch!) [w, t, vs]],
      };
}

/// 1.3.0: the Hunter's shot (target null: he held fire), after a death by night or by the vote ('night' | 'day').
class HuntLog extends GameEvent {
  final int day, seat;
  final int? target;
  final String from;
  const HuntLog(this.day, this.seat, this.target, this.from);
  @override
  Map<String, Object?> toJson() => {'t': 'hunt', 'day': day, 'seat': seat, 'target': target, 'from': from};
}

/// 1.3.0: a Mayor revealed himself.
class RevealLog extends GameEvent {
  final int day, seat;
  const RevealLog(this.day, this.seat);
  @override
  Map<String, Object?> toJson() => {'t': 'reveal', 'day': day, 'seat': seat};
}

class DayLog extends GameEvent {
  final int day;
  final int? out;
  final String kind;
  final List<TallyLine>? tally;
  const DayLog(this.day, this.out, this.kind, this.tally);
  @override
  Map<String, Object?> toJson() =>
      {'t': 'day', 'day': day, 'out': out, 'kind': kind, 'tally': tally?.map((x) => x.toJson()).toList()};
}

class RemovedLog extends GameEvent {
  final int seat;
  const RemovedLog(this.seat);
  @override
  Map<String, Object?> toJson() => {'t': 'removed', 'seat': seat};
}

class Lead {
  final String k; // 'killed' | 'votedOut'
  final int seat;
  const Lead(this.k, this.seat);
}

class WinLog extends GameEvent {
  final Winner winner;
  final Lead? lead;
  const WinLog(this.winner, this.lead);
  @override
  Map<String, Object?> toJson() =>
      {'t': 'win', 'winner': winner.name, 'lead': lead == null ? null : {'k': lead!.k, 'seat': lead!.seat}};
}

class PhaseEvent extends GameEvent {
  final Phase phase;
  final int day;
  const PhaseEvent(this.phase, this.day);
  @override
  Map<String, Object?> toJson() => {'t': 'phase', 'phase': phase.name, 'day': day};
}

/// An action. `choice` is a seat (int), 'skip', 'none' or null, as the TypeScript one.
class Action {
  final String t;
  final int? seat;
  final Object? choice;
  final bool hasChoice;
  final int? day, id;
  final List<int>? seats;
  final String? op;
  final int? sec;
  final bool? open;
  final int? frame; // 1.3.0, the Framer's frame (hasFrame with null: no frame)
  final bool hasFrame;
  final bool? reveal; // 1.3.0, a Mayor in pass-and-play: reveal me in the morning
  const Action._(this.t, {this.seat, this.choice, this.hasChoice = false, this.day, this.id, this.seats, this.op, this.sec, this.open,
      this.frame, this.hasFrame = false, this.reveal});

  const Action.begin() : this._('begin');
  const Action.night(int seat, Object? choice, {int? day}) : this._('night', seat: seat, choice: choice, hasChoice: true, day: day);
  /// 1.3.0: a night pick with the Framer's frame (pass [hasFrame]) and / or a Mayor's reveal.
  const Action.nightWith(int seat, Object? choice, {int? day, int? frame, bool hasFrame = false, bool? reveal})
      : this._('night', seat: seat, choice: choice, hasChoice: true, day: day, frame: frame, hasFrame: hasFrame, reveal: reveal);
  const Action.hunt(int seat, int? choice) : this._('hunt', seat: seat, choice: choice, hasChoice: true); // 1.3.0
  const Action.reveal(int seat) : this._('reveal', seat: seat); // 1.3.0
  const Action.skipPending([List<int>? seats]) : this._('skipPending', seats: seats);
  const Action.startDay() : this._('startDay');
  const Action.timer(String op, {int? sec}) : this._('timer', op: op, sec: sec);
  const Action.startVote(bool open) : this._('startVote', open: open);
  const Action.vote(int seat, Object choice, {int? id}) : this._('vote', seat: seat, choice: choice, hasChoice: true, id: id);
  const Action.decide(Object choice) : this._('decide', choice: choice, hasChoice: true);
  const Action.nextNight() : this._('nextNight');
  const Action.remove(int seat) : this._('remove', seat: seat);

  /// Keys in the order the TypeScript objects are built in ({t, seat, choice, day} / {t, seat, choice, id} / …).
  Map<String, Object?> toJson() => {
        't': t,
        if (seat != null) 'seat': seat,
        if (hasChoice) 'choice': choice,
        if (day != null) 'day': day,
        if (hasFrame) 'frame': frame,
        if (reveal != null) 'reveal': reveal,
        if (id != null) 'id': id,
        if (seats != null) 'seats': seats,
        if (op != null) 'op': op,
        if (sec != null) 'sec': sec,
        if (open != null) 'open': open,
      };

  /// From JSON (a record). Wrong types become values the engine refuses (like the TypeScript one would).
  factory Action.fromJson(Map<String, Object?> j) {
    int? n(String k) => j[k] == null ? null : (j[k] is int ? j[k] as int : -1);
    return Action._(j['t'] as String,
        seat: n('seat'), choice: j['choice'], hasChoice: j.containsKey('choice'), day: n('day'), id: n('id'),
        seats: (j['seats'] as List?)?.map((x) => x is int ? x : -1).toList(), op: j['op'] as String?, sec: n('sec'),
        open: j['open'] as bool?, frame: n('frame'), hasFrame: j.containsKey('frame'), reveal: j['reveal'] is bool ? j['reveal'] as bool : null);
  }
}

/// The result of apply(): the new state and the events, or an error.
class Applied {
  final GameState? state;
  final List<GameEvent> events;
  final String? error;
  const Applied(this.state, this.events) : error = null;
  const Applied.fail(this.error) : state = null, events = const [];
  bool get ok => error == null;
}

/// One target button at night.
class NightOption {
  final int seat;
  bool disabled = false, teammate = false, lastTarget = false, lastNight = false;
  bool sheikh = false; // the Sheikh (another Mafia) picked this seat: it wins a tie
  bool? check; // 1.1.0, Detective: checked on an earlier night (true = read Mafia); can't be picked again
  bool mayor = false; // 1.3.0, Doctor: a revealed Mayor (can't be protected)
  final bool self;
  int mateVotes = 0;
  NightOption(this.seat, this.self);
}

class NightOptions {
  final String key; // 'mafia' | 'doctor' | 'detective' | 'citizen' | 'sniper' | 'bodyguard' | 'watcher' | 'none'
  final List<NightOption> opts = [];
  List<int>? frame; // 1.3.0, the Framer: who he may frame besides his kill vote
  bool reveal = false; // 1.3.0, an unrevealed Mayor: he may reveal himself in the morning with this turn
  int? skipMateVotes; // the Mafia's one-time skip, if still allowed (with teammates' votes for it); the Sniper's "keep the bullet"
  bool skipSheikh = false; // the Sheikh picked the skip
  NightOptions(this.key);
  bool get canSkip => skipMateVotes != null;
}
