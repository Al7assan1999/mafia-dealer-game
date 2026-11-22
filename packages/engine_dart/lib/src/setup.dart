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

/// 'tooFew' | 'tooManyPlayers' | 'tooManyRoles' | 'mafiaGap' | 'badName' | 'dupNames'
typedef SetupCheck = ({Counts counts, String? error});

SetupCheck validateSetup(List<String> names, Counts counts) {
  final n = names.length, c = normalizeCounts(n, counts);
  SetupCheck err(String e) => (counts: c, error: e);
  if (n < minPlayers) return err('tooFew');
  if (n > maxPlayers) return err('tooManyPlayers');
  if (n - c.mafia - c.doctor - c.detective < 0) return err('tooManyRoles');
  if (n - 2 * c.mafia < 2) return err('mafiaGap');
  if (names.any((x) => x.trim().isEmpty || x.trim().length > maxName)) return err('badName');
  if (names.map(nameKey).toSet().length < n) return err('dupNames');
  return (counts: c, error: null);
}

const defaultRules = Rules(
    skip: true, norep: false, saverev: false, decoy: true, self: true, rep: false, reveal: true,
    timer: 180, nightT: 0, ghost: false, skipVote: true);

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
  final v = validateSetup(setup.names, setup.counts);
  if (v.error != null) return (state: null, error: v.error);
  final names = setup.names.map((x) => x.trim()).toList(), rules = setup.rules, deck = <Role>[];
  for (final r in [Role.mafia, Role.doctor, Role.detective]) {
    final k = r == Role.mafia ? v.counts.mafia : r == Role.doctor ? v.counts.doctor : v.counts.detective;
    for (var i = 0; i < k; i++) {
      deck.add(r);
    }
  }
  while (deck.length < names.length) {
    deck.add(Role.citizen);
  }
  return (
    state: GameState(
      deal: deal, names: names, roles: shuffle(deck, rng), alive: names.map((_) => true).toList(), rules: rules,
      phase: Phase.deal, day: 1, night: Night(), skipUsed: false, lastTarget: null, lastProt: SplayTreeMap(),
      morning: null, timer: DayTimer(false, rules.timer, 0), vote: null, verdict: null, winner: null, log: [],
      stats: Stats(),
    ),
    error: null,
  );
}
