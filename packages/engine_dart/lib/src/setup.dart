// Role counts, limits and presets, and dealing a new game (packages/engine/src/setup.ts).
import 'dart:collection';
import 'dart:math' as math;

import 'types.dart';

const minPlayers = 4, maxPlayers = 20, maxName = 18;

/// Two names count as the same when they differ only in case or spacing.
String nameKey(String n) => n.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// At most this many Mafia for n players: Mafia must be at least 2 fewer than everyone else.
int maxMafia(int n) => math.max(1, ((n - 2) / 2).floor());

/// Would this many Mafia / Detectives still make a game for n players?
bool deckOk(int n, int m, int d) => n >= minPlayers && m <= maxMafia(n) && n - m - 1 - d >= 0 && n - 2 * m >= 2;

/// Recommended Mafia for n players: about one in four, inside the limit (JS Math.round: halves go up).
int recMafia(int n) => math.max(1, math.min((n / 4 + 0.5).floor(), maxMafia(n)));

/// Exactly 1 Doctor; 1-10 Mafia; at most 1 Detective and only with 2+ Mafia.
Counts _fix(Counts c) {
  final mafia = math.max(1, math.min(10, c.mafia));
  return Counts(mafia, 1, mafia >= 2 ? math.min(1, math.max(0, c.detective)) : 0);
}

/// The counts pulled back inside the limits for n players.
Counts normalizeCounts(int n, Counts counts) {
  var c = _fix(counts);
  if (n >= minPlayers) c = _fix(Counts(math.min(c.mafia, maxMafia(n)), c.doctor, c.detective));
  return c;
}

/// The modes (1.0.0), in the order the setup shows them, and the fewest players each needs.
const modes = <Mode>['classic', 'sniper', 'jester', 'bodyguard', 'all'];
const modeMin = <Mode, int>{'classic': 4, 'sniper': 6, 'jester': 6, 'bodyguard': 6, 'all': 9};

/// The deck a mode deals for n players. Classic: the table's counts; the others: fixed by n (Mafia about one in four,
/// the Detective with 2+ Mafia, plus the mode's own roles). bg: the Sniper and Jester modes' optional Bodyguard (1.1.0).
Counts modeCounts(Mode mode, int n, Counts counts, [bool bg = false]) {
  if (mode == 'classic') return normalizeCounts(n, counts);
  final mafia = recMafia(n), withBg = mode == 'bodyguard' || mode == 'all' || (bg && (mode == 'sniper' || mode == 'jester'));
  return Counts(mafia, 1, mafia >= 2 ? 1 : 0,
      sniper: mode == 'sniper' || mode == 'all' ? 1 : 0, jester: mode == 'jester' || mode == 'all' ? 1 : 0, bodyguard: withBg ? 1 : 0);
}

/// 'tooFew' | 'tooManyPlayers' | 'tooManyRoles' | 'mafiaGap' | 'badName' | 'dupNames' | 'modeFew'
typedef SetupCheck = ({Counts counts, String? error});

SetupCheck validateSetup(List<String> names, Counts counts, [Mode mode = 'classic', bool bg = false]) {
  final n = names.length, c = modeCounts(mode, n, counts, bg);
  SetupCheck err(String e) => (counts: c, error: e);
  if (n < minPlayers) return err('tooFew');
  if (n > maxPlayers) return err('tooManyPlayers');
  if (n < modeMin[mode]!) return err('modeFew');
  if (n - c.mafia - c.doctor - c.detective - c.sniper - c.jester - c.bodyguard < 0) return err('tooManyRoles');
  if (n - 2 * c.mafia < 2) return err('mafiaGap');
  if (names.any((x) => x.trim().isEmpty || x.trim().length > maxName)) return err('badName');
  if (names.map(nameKey).toSet().length < n) return err('dupNames');
  return (counts: c, error: null);
}

const defaultRules = Rules(
    skip: true, norep: false, saverev: false, decoy: true, self: true, rep: false, reveal: true,
    timer: 180, nightT: 0, ghost: false, skipVote: true);

/// A record's rules: records made before the tie rule (Sprint 7) have no `tieSkip`, and their ties were random picks.
Rules recordRules(Map<String, Object?> j) => defaultRules.merge({'tieSkip': false, ...j});

const presets = <String, Map<String, Object>>{
  'classic': {'skip': true, 'norep': false, 'saverev': false, 'decoy': true, 'self': true, 'rep': false, 'reveal': true, 'timer': 180},
  'beginner': {'skip': false, 'norep': false, 'saverev': true, 'decoy': true, 'self': true, 'rep': false, 'reveal': true, 'timer': 240},
};

String presetOf(Rules r) {
  final j = r.toJson();
  for (final p in presets.entries) {
    if (p.value.entries.every((e) => j[e.key] == e.value)) return p.key;
  }
  return 'custom';
}

/// Night timer choices, seconds (0 = off).
const nightTimes = [0, 30, 45, 60, 90, 120, 180];

/// Fisher-Yates with the given random source.
List<T> shuffle<T>(List<T> a, Rng rng) {
  for (var i = a.length - 1; i > 0; i--) {
    final r = (rng() * (i + 1)).floor();
    final x = a[i];
    a[i] = a[r];
    a[r] = x;
  }
  return a;
}

/// Deals a new game (phase deal), or returns the setup error.
({GameState? state, String? error}) createGame(Setup setup, Rng rng, [int deal = 1]) {
  if (!modes.contains(setup.mode)) return (state: null, error: 'mode');
  final v = validateSetup(setup.names, setup.counts, setup.mode, setup.bodyguard);
  if (v.error != null) return (state: null, error: v.error);
  final names = setup.names.map((x) => x.trim()).toList(), rules = setup.rules, deck = <Role>[], c = v.counts;
  for (final (r, k) in [(Role.mafia, c.mafia), (Role.doctor, c.doctor), (Role.detective, c.detective), (Role.sniper, c.sniper), (Role.jester, c.jester), (Role.bodyguard, c.bodyguard)]) {
    for (var i = 0; i < k; i++) {
      deck.add(r);
    }
  }
  while (deck.length < names.length) {
    deck.add(Role.citizen);
  }
  final roles = shuffle(deck, rng), mafia = [for (var i = 0; i < roles.length; i++) if (roles[i] == Role.mafia) i];
  return (
    state: GameState(
      deal: deal, names: names, roles: roles, alive: names.map((_) => true).toList(), rules: rules,
      mode: setup.mode, sheikh: mafia[(rng() * mafia.length).floor()], // one of the Mafia, at random
      rv: 2,
      phase: Phase.deal, day: 1, night: Night(), skipUsed: false, lastTarget: null, lastProt: SplayTreeMap(),
      morning: null, timer: DayTimer(false, rules.timer, 0), vote: null, verdict: null, winner: null, log: [],
      stats: Stats(),
    ),
    error: null,
  );
}
