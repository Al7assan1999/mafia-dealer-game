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
const modes = <Mode>['classic', 'sniper', 'jester', 'bodyguard', 'all', 'avenger', 'shadows', 'lovers', 'lonewolves'];
const modeMin = <Mode, int>{'classic': 4, 'sniper': 6, 'jester': 6, 'bodyguard': 6, 'all': 9, 'avenger': 6, 'shadows': 8, 'lovers': 8, 'lonewolves': 9};

/// 1.4.0: the Framer and the Silencer, by mode and player count (a Mafia with a power each, like the Sheikh).
bool hasFramer(Mode mode, int n) => mode == 'shadows' || (mode == 'lonewolves' && n >= 13);
bool hasSilencer(Mode mode, int n) => mode == 'lonewolves' && n >= 11;

/// 1.3.0, his rule: how far the table rules lean, against the way the group usually plays (reveal off, the Doctor may
/// protect himself, decoy on, Reveal saves off). Mafia points minus town points (docs/sprint-20-roles.md §8 C).
/// Null rules = none given (0), as the TypeScript `{}`.
int lean(Rules? r) => r == null
    ? 0
    : (r.self ? 0 : 1) + (r.rep ? 1 : 0) + (r.decoy ? 0 : 1) - (r.reveal ? 2 : 0) - (r.saverev ? 1 : 0) - (r.norep ? 1 : 0);

/// 1.3.0: the Mafia counts a mode lets the table pick for n players, and the default (§8 B). A lean of 2 or more takes
/// the higher count away, -2 or less the lower one. Classic and All: null. 1.4.0: Lovers, Lone Wolves, and the Sniper,
/// Jester and Bodyguard modes (their default is the count they always dealt); legacy: a record from before 1.4.0.
({int min, int max, int def})? mafiaRange(Mode mode, int n, [Rules? rules, bool legacy = false]) {
  final old = mode == 'sniper' || mode == 'jester' || mode == 'bodyguard';
  if (mode == 'classic' || mode == 'all' || (old && legacy)) return null;
  var (min, max) = mode == 'avenger' || old
      ? (n <= 5 ? (1, 1) : n == 6 ? (1, 2) : n <= 9 ? (2, 2) : n <= 13 ? (2, 3) : n <= 17 ? (3, 4) : (4, 5))
      : mode == 'shadows' ? (n <= 8 ? (2, 2) : n <= 13 ? (2, 3) : n <= 17 ? (3, 4) : (4, 5))
      : mode == 'lovers' ? (n <= 8 ? (2, 2) : n <= 10 ? (2, 3) : n <= 12 ? (3, 3) : n <= 16 ? (3, 4) : (4, 5))
      : (n <= 10 ? (2, 2) : n <= 12 ? (3, 3) : n <= 16 ? (3, 4) : (4, 5));
  final l = lean(rules);
  if (l >= 2) {
    max = min;
  } else if (l <= -2) {
    min = max;
  }
  return (min: min, max: max, def: max);
}

/// The deck a mode deals for n players. Classic: the table's counts; the others: fixed by n (Mafia about one in four,
/// the Detective with 2+ Mafia, plus the mode's own roles). bg: the Sniper and Jester modes' optional Bodyguard (1.1.0).
Counts modeCounts(Mode mode, int n, Counts counts, [bool bg = false, Rules? rules, bool legacy = false]) {
  if (mode == 'classic') return normalizeCounts(n, counts);
  final range = mafiaRange(mode, n, rules, legacy);
  final m = range == null ? recMafia(n) : counts.mafia >= range.min && counts.mafia <= range.max ? counts.mafia : range.def;
  // 1.3.0: Avenger (the Hunter, never the Sniper) and Shadows (the Sniper, never the Hunter); 1.4.0: Lovers, Lone Wolves
  if (mode == 'avenger') return Counts(m, 1, m >= 2 ? 1 : 0, hunter: 1, mayor: n >= 7 ? 1 : 0, jester: n >= 9 ? 1 : 0, bodyguard: n >= 13 ? 1 : 0);
  if (mode == 'shadows') {
    return Counts(m, 1, m >= 2 ? 1 : 0, watcher: 1, sniper: 1, jester: n >= 10 || (m == 2 && n == 9) ? 1 : 0, mayor: n >= 11 ? 1 : 0,
        bodyguard: n >= 13 ? 1 : 0);
  }
  if (mode == 'lovers') {
    return Counts(m, 1, m >= 2 ? 1 : 0, cupid: 1, hunter: n >= 9 && n < 17 ? 1 : 0, sniper: n >= 17 ? 1 : 0, jester: n >= 9 ? 1 : 0,
        mayor: n >= 11 ? 1 : 0, bodyguard: n >= 11 ? 1 : 0, watcher: n >= 13 ? 1 : 0);
  }
  if (mode == 'lonewolves') {
    return Counts(m, 1, m >= 2 ? 1 : 0, bodyguard: 1, killer: 1, watcher: n >= 11 ? 1 : 0, jester: n >= 11 ? 1 : 0, mayor: n >= 13 ? 1 : 0,
        hunter: n >= 17 ? 1 : 0);
  }
  // the Sniper, Jester, Bodyguard and All modes; 1.4.0: the first three with the table's count inside their range
  final mafia = m, withBg = mode == 'bodyguard' || mode == 'all' || (bg && (mode == 'sniper' || mode == 'jester'));
  return Counts(mafia, 1, mafia >= 2 ? 1 : 0,
      sniper: mode == 'sniper' || mode == 'all' ? 1 : 0, jester: mode == 'jester' || mode == 'all' ? 1 : 0, bodyguard: withBg ? 1 : 0);
}

/// 'tooFew' | 'tooManyPlayers' | 'tooManyRoles' | 'mafiaGap' | 'badName' | 'dupNames' | 'modeFew' | 'sniperHunter'
typedef SetupCheck = ({Counts counts, String? error});

SetupCheck validateSetup(List<String> names, Counts counts, [Mode mode = 'classic', bool bg = false, Rules? rules, bool legacy = false]) {
  final n = names.length, c = modeCounts(mode, n, counts, bg, rules, legacy);
  SetupCheck err(String e) => (counts: c, error: e);
  if (n < minPlayers) return err('tooFew');
  if (n > maxPlayers) return err('tooManyPlayers');
  if (n < modeMin[mode]!) return err('modeFew');
  if (n - c.mafia - c.doctor - c.detective - c.sniper - c.jester - c.bodyguard - c.hunter - c.mayor - c.watcher - c.killer - c.cupid < 0) return err('tooManyRoles');
  if (c.sniper > 0 && c.hunter > 0) return err('sniperHunter'); // his rule (2026-11-26): never both in one game
  if (n - 2 * c.mafia < 2) return err('mafiaGap');
  if (names.any((x) => x.trim().isEmpty || x.trim().length > maxName)) return err('badName');
  if (names.map(nameKey).toSet().length < n) return err('dupNames');
  return (counts: c, error: null);
}

const defaultRules = Rules(
    skip: true, norep: false, saverev: false, decoy: true, self: true, rep: false, reveal: false, // 1.3.0 (his ruling): off by default, as the group plays
    timer: 180, nightT: 0, ghost: false, skipVote: true);

/// A record's rules: records made before the tie rule (Sprint 7) have no `tieSkip`, and their ties were random picks.
Rules recordRules(Map<String, Object?> j) => defaultRules.merge({'tieSkip': false, ...j});

const presets = <String, Map<String, Object>>{
  'classic': {'skip': true, 'norep': false, 'saverev': false, 'decoy': true, 'self': true, 'rep': false, 'reveal': false, 'timer': 180},
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

/// 1.4.0 [Quin Q1]: an old-mode deal that 1.3.x would have dealt the same way stays rv 2, so 1.3.x phones can replay it.
bool _sameAsLegacy(Setup setup, Counts counts) {
  if (setup.mode == 'lovers' || setup.mode == 'lonewolves') return false;
  final old = validateSetup(setup.names, setup.counts, setup.mode, setup.bodyguard, setup.rules, true);
  return old.error == null && old.counts.mafia == counts.mafia;
}

/// Deals a new game (phase deal), or returns the setup error.
({GameState? state, String? error}) createGame(Setup setup, Rng rng, [int deal = 1]) {
  if (!modes.contains(setup.mode)) return (state: null, error: 'mode');
  final v = validateSetup(setup.names, setup.counts, setup.mode, setup.bodyguard, setup.rules, setup.legacy);
  if (v.error != null) return (state: null, error: v.error);
  final names = setup.names.map((x) => x.trim()).toList(), rules = setup.rules, deck = <Role>[], c = v.counts;
  // new roles go at the end: the decks (and so the shuffles) of the older modes stay as they were
  for (final (r, k) in [(Role.mafia, c.mafia), (Role.doctor, c.doctor), (Role.detective, c.detective), (Role.sniper, c.sniper), (Role.jester, c.jester),
    (Role.bodyguard, c.bodyguard), (Role.hunter, c.hunter), (Role.mayor, c.mayor), (Role.watcher, c.watcher), (Role.killer, c.killer), (Role.cupid, c.cupid)]) {
    for (var i = 0; i < k; i++) {
      deck.add(r);
    }
  }
  while (deck.length < names.length) {
    deck.add(Role.citizen);
  }
  final roles = shuffle(deck, rng), mafia = [for (var i = 0; i < roles.length; i++) if (roles[i] == Role.mafia) i];
  final sheikh = mafia[(rng() * mafia.length).floor()]; // one of the Mafia, at random
  int? framer, silencer;
  if (hasFramer(setup.mode, names.length)) { // 1.3.0: the Framer, another Mafia than the Sheikh, at random
    final others = mafia.where((i) => i != sheikh).toList();
    framer = others[(rng() * others.length).floor()];
  }
  if (hasSilencer(setup.mode, names.length)) { // 1.4.0: the Silencer, another Mafia than the Sheikh and the Framer
    final others = mafia.where((i) => i != sheikh && i != framer).toList();
    silencer = others[(rng() * others.length).floor()];
  }
  return (
    state: GameState(
      deal: deal, names: names, roles: roles, alive: names.map((_) => true).toList(), rules: rules,
      mode: setup.mode, sheikh: sheikh, framer: framer, silencer: silencer,
      rv: setup.legacy || _sameAsLegacy(setup, v.counts) ? 2 : 3, // [Quin Q1] rv 3 only when a 1.3.x phone couldn't replay it
      phase: Phase.deal, day: 1, night: Night(), skipUsed: false, lastTarget: null, lastProt: SplayTreeMap(),
      morning: null, timer: DayTimer(false, rules.timer, 0), vote: null, verdict: null, winner: null, log: [],
      stats: Stats(),
    ),
    error: null,
  );
}
