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
  final names = [for (var i = 0; i < n; i++) 'Player ${i + 1}'];
  final c = createGame(Setup(names, Counts(mafia, 1, mafia >= 2 ? 1 : 0), rules), r);
  expect(c.error, isNull);
  var s = c.state!, now = 1000000, steps = 0;
  final rec = startRecord(s);

  void check() {
    final al = alive(s), m = al.where((i) => s.roles[i] == Role.mafia).length;
    if (s.phase == Phase.end) {
      expect(s.winner, m == 0 ? Winner.citizens : Winner.mafia);
    } else {
      expect(m > 0 && m < al.length - m, isTrue, reason: 'seed $seed: game should have ended');
    }
    for (var i = 0; i < n; i++) {
      final v = viewFor(s, i, now);
      if (s.phase != Phase.end && !(rules.ghost && !s.alive[i])) expect(v.roles, isNull, reason: 'no roles before the end');
      if (s.roles[i] != Role.mafia) expect(v.mates, isEmpty);
      if (v.check != null) expect(s.roles[i], Role.detective);
    }
    for (final (d, q) in s.stats.caught) {
      expect(s.roles[d], Role.detective);
      expect(s.roles[q], Role.mafia);
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
      go(Action.night(p, no.key == 'none' ? null : pick(opts), day: s.day));
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
    refused(roles, RegExp(r'action \d+: \w+|result'));
    final extra = copy(g), el = extra['roles'] as List;
    el[el.indexOf('citizen')] = 'doctor';
    refused(extra, 'roles');
    final illegal = copy(g), il = illegal['actions'] as List;
    il.insert(1, {'a': {'t': 'nextNight'}, 'at': (il[0] as Map)['at']});
    refused(illegal, 'action 1: phase');
    final time = copy(g), tl = time['actions'] as List;
    (tl[2] as Map)['at'] = ((tl[1] as Map)['at'] as int) - 1;
    refused(time, 'action 2: time');
    final draws = copy(g), dl = draws['actions'] as List, k = dl.indexWhere((x) => (x as Map).containsKey('r'));
    ((dl[k] as Map)['r'] as List).add(0.5);
    refused(draws, 'action $k: random');
    refused(copy(g)..['format'] = 2, 'format');
    refused({'format': 1, 'actions': [{}]}, 'shape');
    refused(copy(g)..['actions'] = [{'a': null, 'at': 1}], 'shape');
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
