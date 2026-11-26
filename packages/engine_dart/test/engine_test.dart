// The Dart engine against the TypeScript one: the shared test games, the random-game player (a line-by-line copy of
// packages/engine/test/play.ts, so the same seeds make the same records), and edited records.
import 'dart:convert';
import 'dart:io';

import 'package:mafia_engine/mafia_engine.dart';
import 'package:test/test.dart';

final fixtures = File('../engine/fixtures/records.json');

List<int> alive(GameState s) => aliveSeats(s);

({int steps, GameRecord rec, GameState state}) play(int seed) {
  final r = seeded(seed);
  T pick<T>(List<T> a) => a[(r() * a.length).floor()];
  bool chance(double p) => r() < p;
  final n = 4 + (r() * 17).floor(), mafia = 1 + (r() * maxMafia(n)).floor();
  final over = <String, Object>{};
  for (final k in ['skip', 'norep', 'saverev', 'decoy', 'self', 'rep', 'reveal', 'ghost', 'skipVote']) {
    over[k] = chance(.5);
  }
  over['nightT'] = pick([0, 30, 60]);
  final rules = defaultRules.merge(over);
  final names = [for (var i = 0; i < n; i++) 'Player ${i + 1}'], mode = pick(modes.where((m) => modeMin[m]! <= n).toList());
  final bodyguard = chance(.5); // 1.1.0: the Sniper and Jester modes' optional Bodyguard
  final range = mafiaRange(mode, n, rules); // 1.3.0: Avenger and Shadows pick inside their own range
  final m0 = range != null ? range.min + (r() * (range.max - range.min + 1)).floor() : mafia;
  final c = createGame(Setup(names, Counts(m0, 1, m0 >= 2 ? 1 : 0), rules, mode, bodyguard), r);
  expect(c.error, isNull);
  var s = c.state!, now = 1000000, steps = 0;
  final rec = startRecord(s);

  void check() {
    final al = alive(s), m = al.where((i) => s.roles[i] == Role.mafia).length;
    expect(s.roles[s.sheikh!], Role.mafia, reason: 'the Sheikh is one of the Mafia');
    final last = s.log.lastOrNull;
    if (s.phase == Phase.end && s.winner == Winner.jester) {
      expect(last is WinLog && last.lead?.k == 'votedOut' && s.roles[last.lead!.seat] == Role.jester, isTrue);
    } else if (s.phase == Phase.end) {
      expect(s.winner, m == 0 ? Winner.citizens : Winner.mafia);
    } else if (s.hunt != null) {
      expect(m > 0 && !s.alive[s.hunt!.seat] && s.roles[s.hunt!.seat] == Role.hunter, isTrue, reason: 'a dead Hunter aims');
    } else {
      expect(m > 0 && m < al.length - m, isTrue, reason: 'seed $seed: game should have ended');
    }
    // 1.3.0
    expect(s.roles.contains(Role.sniper) && s.roles.contains(Role.hunter), isFalse, reason: 'never the Sniper and the Hunter');
    if (s.framer != null) expect(s.roles[s.framer!] == Role.mafia && s.framer != s.sheikh && mode == 'shadows', isTrue);
    for (var i = 0; i < n; i++) {
      final v = viewFor(s, i, now);
      if (s.phase != Phase.end && !(rules.ghost && !s.alive[i] && s.hunt?.seat != i)) expect(v.roles, isNull, reason: 'no roles before the end');
      expect(v.ph == 'hunt', s.hunt?.seat == i);
      if (s.roles[i] != Role.mafia) expect(v.mates, isEmpty);
      if (v.check != null) {
        expect(s.roles[i], Role.detective);
        if (v.check!.seat == s.sheikh) expect(v.check!.mafia, isFalse, reason: 'the Sheikh reads not Mafia');
      }
    }
    for (final (d, q) in s.stats.caught) {
      expect(s.roles[d], Role.detective);
      expect(s.roles[q], Role.mafia);
      expect(q, isNot(s.sheikh));
    }
    for (final (x, q) in s.stats.shots) {
      expect(s.roles[x], Role.sniper);
      expect(s.alive[q], isFalse);
    }
    expect(s.stats.shots.length <= 1, isTrue, reason: 'one bullet');
    // 1.1.0
    expect(s.rv, 2);
    final nights = s.log.whereType<NightLog>().toList();
    if (nights.isNotEmpty) expect(nights.first.shot, isNull, reason: 'no shot on night 1');
    final checked = [for (final e in nights) ...e.checked];
    if (s.roles.where((x) => x == Role.detective).length == 1) expect(checked.toSet().length, checked.length, reason: 'nobody checked twice');
    for (final (b, q) in s.stats.guards) {
      expect(s.roles[b], Role.bodyguard);
      expect(b, isNot(q));
    }
  }

  void go(Action a) {
    final res = step(rec, s, a, Ctx(r, now += 1000));
    expect(res.ok, isTrue, reason: 'seed $seed: ${a.t} refused (${res.error})');
    s = res.state!;
    steps++;
    check();
  }

  go(const Action.begin());
  while (s.phase != Phase.end) {
    expect(s.day <= 100, isTrue, reason: 'seed $seed: too many days');
    if (s.hunt != null) { // 1.3.0: the dead Hunter: shoots, holds fire, times out, or the host removes him
      final h = s.hunt!.seat, v = viewFor(s, h, now);
      if (chance(.1)) {
        go(const Action.skipPending());
      } else if (chance(.05)) {
        go(Action.remove(h));
      } else {
        go(Action.hunt(h, chance(.2) ? null : pick(v.huntOpts!)));
      }
      continue;
    }
    final mayor = alive(s).where((i) => s.roles[i] == Role.mayor && !s.mayors.contains(i)).firstOrNull;
    if (mayor != null && (s.phase == Phase.morning || s.phase == Phase.day) && chance(.2)) { go(Action.reveal(mayor)); continue; }
    if (s.phase == Phase.night) {
      final dead = s.alive.indexOf(false);
      if (dead >= 0) expect(apply(s, Action.night(dead, 0), Ctx(r, now)).error, 'dead');
      if (chance(.03)) { go(Action.remove(pick(alive(s)))); continue; }
      if (chance(.05)) { go(const Action.skipPending()); continue; }
      final p = pick(alive(s).where((i) => !s.night.done.contains(i)).toList());
      final v = viewFor(s, p, now);
      expect(v.ph, 'night');
      final no = v.night!, opts = <Object>[...no.opts.where((o) => !o.disabled).map((o) => o.seat)];
      if (no.canSkip) opts.add('skip');
      expect(no.key == 'none' || opts.isNotEmpty, isTrue, reason: 'seed $seed: seat $p has nothing to pick');
      // the same draws, in the same order, as play.ts: the frame and the reveal first, then the pick
      final fr = no.frame != null && chance(.9);
      final frame = fr ? (chance(.2) || no.frame!.isEmpty ? null : pick(no.frame!)) : null;
      final rev = no.reveal && chance(.1);
      go(Action.nightWith(p, no.key == 'none' ? null : pick(opts), day: s.day, frame: frame, hasFrame: fr, reveal: rev ? true : null));
    } else if (s.phase == Phase.morning) {
      go(const Action.startDay());
    } else if (s.phase == Phase.day) {
      if (chance(.3)) {
        go(Action.decide(chance(.3) ? 'none' : pick(alive(s))));
      } else {
        go(Action.startVote(chance(.5)));
      }
    } else if (s.phase == Phase.vote) {
      if (chance(.05)) { go(const Action.skipPending()); continue; }
      final p = pick(alive(s).where((i) => !s.vote!.votes.containsKey(i)).toList());
      final others = alive(s).where((i) => i != p).toList();
      go(Action.vote(p, chance(.2) ? 'none' : pick(others), id: s.vote!.id));
    } else if (s.phase == Phase.verdict) {
      go(const Action.nextNight());
    }
  }
  return (steps: steps, rec: rec, state: s);
}

Map<String, Object?> copy(Map<String, Object?> r) => jsonDecode(jsonEncode(r)) as Map<String, Object?>;

void main() {
  test('every shared test game replays (the same history and winner as the TypeScript engine)', () {
    final saved = jsonDecode(fixtures.readAsStringSync()) as List;
    expect(saved.length, 60);
    for (var i = 0; i < saved.length; i++) {
      final x = replay(saved[i]);
      expect(x.error, isNull, reason: 'game ${i + 1}');
    }
  });

  test('records from before the tie rule (no tieSkip: random tie-breaks) still replay', () {
    final old = jsonDecode(File('../engine/fixtures/records-before-tie.json').readAsStringSync()) as List;
    expect(old, hasLength(60));
    for (final (i, r) in old.indexed) {
      expect((r['rules'] as Map).containsKey('tieSkip'), isFalse);
      expect(replay(r).error, isNull, reason: 'game ${i + 1}');
    }
  });

  test('records from before 1.0.0 (no Sheikh, no modes: ties kill nobody) still replay', () {
    final old = jsonDecode(File('../engine/fixtures/records-before-sheikh.json').readAsStringSync()) as List;
    expect(old, hasLength(60));
    for (final (i, r) in old.indexed) {
      expect((r as Map).containsKey('sheikh'), isFalse);
      expect(replay(r).error, isNull, reason: 'game ${i + 1}');
    }
  });

  test('the scripted 1.0.0 games (the Sheikh, the Sniper, the Jester; roles.test.ts) replay to the same result', () {
    final games = jsonDecode(File('../engine/fixtures/records-roles.json').readAsStringSync()) as List;
    expect(games.length, greaterThanOrEqualTo(10));
    for (final (i, r) in games.indexed) {
      expect(replay(r).error, isNull, reason: 'scripted game ${i + 1}');
    }
    expect(games.any((r) => (r as Map)['winner'] == 'jester'), isTrue);
  });

  test('records from 1.0.0 (no rv: re-checks, a night-1 shot, no Bodyguard) still replay', () {
    final old = jsonDecode(File('../engine/fixtures/records-1.0.json').readAsStringSync()) as List;
    expect(old, hasLength(60));
    for (final (i, r) in old.indexed) {
      expect((r as Map).containsKey('rv'), isFalse);
      expect(replay(r).error, isNull, reason: 'game ${i + 1}');
    }
  });

  test('the scripted 1.1.0 games (the Detective, the Sniper on night 1, the Bodyguard B1-B15; s18.test.ts) replay', () {
    final games = jsonDecode(File('../engine/fixtures/records-s18.json').readAsStringSync()) as List;
    expect(games.length, greaterThanOrEqualTo(12));
    for (final (i, r) in games.indexed) {
      expect((r as Map)['rv'], 2);
      expect(replay(r).error, isNull, reason: 'scripted game ${i + 1}');
      expect(jsJson(recordFromJson(Map<String, Object?>.from(r)).toJson()), jsJson(r), reason: 'reads back byte-identical');
    }
  });

  test('records from 1.2 (before the Hunter, the Mayor, the Framer and the Watcher) still replay', () {
    final old = jsonDecode(File('../engine/fixtures/records-1.2.json').readAsStringSync()) as List;
    expect(old, hasLength(60));
    for (final (i, r) in old.indexed) {
      expect((r as Map).containsKey('framer'), isFalse);
      expect(replay(r).error, isNull, reason: 'game ${i + 1}');
    }
  });

  test('the scripted 1.3.0 games (the Hunter, the Mayor, the Framer, the Watcher; s20.test.ts) replay, byte-identical', () {
    final games = jsonDecode(File('../engine/fixtures/records-s20.json').readAsStringSync()) as List;
    expect(games.length, greaterThanOrEqualTo(15));
    for (final (i, r) in games.indexed) {
      expect(replay(r).error, isNull, reason: 'scripted game ${i + 1}');
      expect(jsJson(recordFromJson(Map<String, Object?>.from(r as Map)).toJson()), jsJson(r), reason: 'reads back byte-identical');
    }
    final sh = Map<String, Object?>.from(games.firstWhere((r) => (r as Map)['mode'] == 'shadows') as Map);
    expect(replay(copy(sh)..['framer'] = sh['sheikh']).error, 'roles');
    expect(replay(copy(sh)..remove('framer')).error, 'roles');
  });

  test('1.3.0 setup: the Mafia ranges, the lean, the decks (as s20.test.ts)', () {
    const off = {'reveal': false};
    final r0 = defaultRules.merge(off);
    expect(mafiaRange('avenger', 6, r0), (min: 1, max: 2, def: 2));
    expect(mafiaRange('shadows', 9, r0), (min: 2, max: 3, def: 3));
    expect(mafiaRange('shadows', 9, defaultRules.merge({'reveal': false, 'rep': true, 'decoy': false})), (min: 2, max: 2, def: 2));
    expect(mafiaRange('avenger', 12, defaultRules.merge({'reveal': true})), (min: 3, max: 3, def: 3), reason: 'reveal on: leaning town');
    expect(mafiaRange('avenger', 12, defaultRules), (min: 2, max: 3, def: 3), reason: 'the default (reveal off, his ruling): a choice');
    expect(mafiaRange('classic', 9), isNull);
    expect(modeCounts('shadows', 9, const Counts(3, 1, 1), false, r0), const Counts(3, 1, 1, watcher: 1, sniper: 1));
    expect(modeCounts('shadows', 9, const Counts(2, 1, 1), false, r0), const Counts(2, 1, 1, watcher: 1, sniper: 1, jester: 1));
    expect(modeCounts('avenger', 6, const Counts(1, 1, 1), false, r0), const Counts(1, 1, 0, hunter: 1));
    expect(modeCounts('avenger', 7, const Counts(2, 1, 1), false, r0), const Counts(2, 1, 1, hunter: 1, mayor: 1));
    for (final m in modes) {
      for (var n = 4; n <= 20; n++) {
        for (var k = 1; k <= 9; k++) {
          final c = modeCounts(m, n, Counts(k, 1, 1), true, r0);
          expect(c.sniper > 0 && c.hunter > 0, isFalse, reason: '$m $n');
        }
      }
    }
  });

  test('the Bodyguard and the 1.1.0 rules, as the TypeScript engine (s18.test.ts)', () {
    const B = Role.bodyguard, M = Role.mafia, D = Role.doctor, T = Role.detective, C = Role.citizen;
    final roles = [M, M, D, T, B, C, C, C];
    final c = createGame(Setup([for (var i = 0; i < 8; i++) 'P${i + 1}'], const Counts(1, 1, 0), defaultRules, 'bodyguard'), seeded(1));
    var s = c.state!..roles = roles..sheikh = 1;
    var now = 1000000;
    void go(Action a) { final r = apply(s, a, Ctx(seeded(1), now += 1000)); expect(r.error, isNull, reason: a.t); s = r.state!; }
    go(const Action.begin());
    expect(nightOptions(s, 4).opts.firstWhere((o) => o.seat == 4).disabled, isTrue, reason: 'B6');
    for (final (p, q) in [(0, 5), (1, 5), (2, 6), (3, 6), (4, 5), (5, 6), (6, 7), (7, 6)]) { go(Action.night(p, q)); }
    expect([s.alive[5], s.alive[4]], [true, false], reason: 'B2');
    expect(s.stats.guards, [(4, 5)]);
    expect(viewFor(s, 3, now).checks, [(seat: 6, mafia: false)]);
    expect(mvp(Winner.citizens, roles, s.alive, s.stats)?.why, 'guard');
  });

  test('the same seeds make byte-identical records', () {
    final mine = jsJson([for (var seed = 1; seed <= 60; seed++) play(seed).rec.toJson()]);
    expect(mine, fixtures.readAsStringSync().trimRight());
  });

  test('1,000 random games: they all end, the winner is right, nothing leaks, the record replays', () {
    var steps = 0;
    for (var seed = 1; seed <= 1000; seed++) {
      final g = play(seed);
      steps += g.steps;
      final x = replay(jsonDecode(jsonEncode(g.rec.toJson())));
      expect(x.error, isNull, reason: 'seed $seed');
      expect(x.state!.phase, Phase.end);
    }
    expect(steps, greaterThan(10000));
  });

  test('an edited record is refused', () {
    final g = play(7).rec.toJson();
    void refused(Map<String, Object?> r, Pattern e) {
      final x = replay(r);
      expect(x.error, isNotNull);
      expect(RegExp('^(?:${e is RegExp ? e.pattern : RegExp.escape(e as String)})\$').hasMatch(x.error!), isTrue, reason: x.error);
    }
    expect(replay(copy(g)).error, isNull);
    refused(copy(g)..['winner'] = g['winner'] == 'mafia' ? 'citizens' : 'mafia', 'result');
    refused(copy(g)..['log'] = (g['log'] as List).sublist(1), 'result');
    refused(copy(g)..['actions'] = (g['actions'] as List).sublist(0, (g['actions'] as List).length - 1), 'result');
    final roles = copy(g), rl = roles['roles'] as List, m = rl.indexOf('mafia'), c = rl.indexOf('citizen');
    rl[m] = 'citizen';
    rl[c] = 'mafia';
    refused(roles, RegExp(r'action \d+: \w+|result|roles')); // roles: the swapped Mafia was the Sheikh
    final extra = copy(g), el = extra['roles'] as List;
    el[el.indexOf('citizen')] = 'doctor';
    refused(extra, 'roles');
    final illegal = copy(g), il = illegal['actions'] as List;
    il.insert(1, {'a': {'t': 'nextNight'}, 'at': (il[0] as Map)['at']});
    refused(illegal, 'action 1: phase');
    final time = copy(g), tl = time['actions'] as List;
    (tl[2] as Map)['at'] = ((tl[1] as Map)['at'] as int) - 1;
    refused(time, 'action 2: time');
    final draws = copy(g), dl = draws['actions'] as List;
    (dl[1] as Map)['r'] = [0.5]; // 1.0.0 games draw nothing after the deal
    refused(draws, 'action 1: random');
    refused(copy(g)..['format'] = 2, 'format');
    refused({'format': 1, 'actions': [{}]}, 'shape');
    refused(copy(g)..['actions'] = [{'a': null, 'at': 1}], 'shape');
    // the Sheikh must be one of the Mafia; a mode without a Sheikh is not a record any version writes
    refused(copy(g)..['sheikh'] = (g['roles'] as List).indexOf('citizen'), 'roles');
    refused(copy(g)..remove('sheikh'), 'roles');
  });

  test('modes: the deck is fixed by player count; each mode has its minimum', () {
    const none = Counts(1, 1, 0);
    expect(modeCounts('sniper', 6, none), const Counts(2, 1, 1, sniper: 1));
    expect(modeCounts('jester', 8, none), const Counts(2, 1, 1, jester: 1));
    expect(modeCounts('all', 12, none), const Counts(3, 1, 1, sniper: 1, jester: 1, bodyguard: 1)); // 1.1.0: + the Bodyguard
    expect(modeCounts('bodyguard', 8, none), const Counts(2, 1, 1, bodyguard: 1));
    expect(modeCounts('sniper', 8, none, true), const Counts(2, 1, 1, sniper: 1, bodyguard: 1));
    expect(modeCounts('classic', 8, none, true), const Counts(1, 1, 0));
    List<String> ns(int n) => [for (var i = 0; i < n; i++) 'N$i'];
    expect(validateSetup(ns(5), none, 'sniper').error, 'modeFew');
    expect(validateSetup(ns(8), none, 'all').error, 'modeFew');
    expect(validateSetup(ns(9), none, 'all').error, isNull);
    expect(createGame(Setup(ns(9), none, defaultRules, 'nope'), seeded(1)).error, 'mode');
  });

  test('setup limits and messages', () {
    List<String> ns(int n) => [for (var i = 0; i < n; i++) 'P$i'];
    expect(validateSetup(ns(3), const Counts(1, 1, 0)).error, 'tooFew');
    expect(validateSetup(ns(21), const Counts(1, 1, 0)).error, 'tooManyPlayers');
    expect(validateSetup(['a', 'b', 'c', 'A '], const Counts(1, 1, 0)).error, 'dupNames');
    expect(validateSetup(['a', 'b', 'c', ' '], const Counts(1, 1, 0)).error, 'badName');
    expect(validateSetup(ns(4), const Counts(1, 1, 0)).counts, const Counts(1, 1, 0));
    expect(validateSetup(ns(5), const Counts(2, 1, 1)).counts, const Counts(1, 1, 0));
    expect(validateSetup(ns(6), const Counts(2, 1, 1)).error, isNull);
    expect([for (final n in [4, 8, 12, 20]) recMafia(n)], [1, 2, 3, 5]);
    expect(presetOf(defaultRules), 'classic');
  });
}
