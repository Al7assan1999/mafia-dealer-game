// Game records (packages/engine/src/record.ts): the dealt game plus every action in order. Same JSON, same checks,
// same error codes as the TypeScript engine.
import 'dart:convert';

import 'game.dart';
import 'setup.dart';
import 'types.dart';

class RecordedAction {
  final Action a;
  final int at;
  final List<double>? r; // the random draws the action used
  const RecordedAction(this.a, this.at, [this.r]);
  Map<String, Object?> toJson() => {'a': a.toJson(), 'at': at, if (r != null) 'r': r};
}

class GameRecord {
  final int deal;
  final List<String> names;
  final Rules rules;
  final List<Role> roles;
  final List<RecordedAction> actions;
  Winner? winner;
  List<Object?> log; // JSON, as the recorder saw it
  GameRecord(this.deal, this.names, this.rules, this.roles, this.actions, this.winner, this.log);

  Map<String, Object?> toJson() => {
        'format': 1, 'deal': deal, 'names': names, 'rules': rules.toJson(), 'roles': roles.map((r) => r.name).toList(),
        'actions': actions.map((x) => x.toJson()).toList(), 'winner': winner?.name, 'log': log,
      };
}

/// A new record for a game just dealt (phase deal).
GameRecord startRecord(GameState s) => GameRecord(s.deal, [...s.names], s.rules, [...s.roles], [], null, []);

/// apply(), and on success the action joins the record (with its draws) and the record's result follows the game.
Applied step(GameRecord rec, GameState s, Action a, Ctx ctx) {
  final r = <double>[];
  final res = apply(s, a, Ctx(() { final x = ctx.rng(); r.add(x); return x; }, ctx.now));
  if (res.ok) {
    rec.actions.add(RecordedAction(a, ctx.now, r.isEmpty ? null : r));
    rec.winner = res.state!.winner;
    rec.log = res.state!.log.map((e) => e.toJson()).toList();
  }
  return res;
}

/// Replays a record given as JSON (a map, as decoded). Refuses one that doesn't hold together.
({GameState? state, String? error}) replay(Object? json) {
  try {
    return _check(json);
  } catch (_) {
    return (state: null, error: 'shape'); // a malformed record from outside
  }
}

({GameState? state, String? error}) _check(Object? json) {
  ({GameState? state, String? error}) no(String e) => (state: null, error: e);
  if (json is! Map || json['format'] != 1) return no('format');
  final roles0 = json['roles'], names0 = json['names'], actions = json['actions'];
  if (roles0 is! List || names0 is! List || roles0.length != names0.length || actions is! List) return no('shape');
  if (roles0.any((x) => !Role.values.any((r) => r.name == x))) return no('roles');
  final roles = roles0.map((x) => Role.values.byName(x as String)).toList();
  int count(Role x) => roles.where((y) => y == x).length;
  final counts = Counts(count(Role.mafia), count(Role.doctor), count(Role.detective));
  if (names0.any((x) => x is! String)) return no('setup: badName');
  final rules = recordRules(Map<String, Object?>.from(json['rules'] as Map));
  final c = createGame(Setup(names0.cast<String>(), counts, rules), () => 0, json['deal'] as int);
  if (c.error != null) return no('setup: ${c.error}');
  // the dealt roles must be a deck this setup could deal (same counts after the setup's own limits)
  final dealt = c.state!.roles;
  if (dealt.where((x) => x == Role.mafia).length != counts.mafia || dealt.where((x) => x == Role.detective).length != counts.detective ||
      counts.doctor != 1) {
    return no('roles');
  }
  var s = c.state!..roles = roles;
  num last = double.negativeInfinity;
  for (var i = 0; i < actions.length; i++) {
    final x = actions[i] as Map;
    final at = x['at'];
    if (at is! num || !at.isFinite || at < last) return no('action $i: time');
    last = at;
    final draws = [...(x['r'] as List? ?? const [])];
    if (draws.any((d) => d is! num || !(d >= 0 && d < 1))) return no('action $i: random');
    var short = false;
    final res = apply(s, Action.fromJson(Map<String, Object?>.from(x['a'] as Map)),
        Ctx(() => draws.isNotEmpty ? (draws.removeAt(0) as num).toDouble() : (short = true, 0.0).$2, at.toInt()));
    if (!res.ok) return no('action $i: ${res.error}');
    if (short || draws.isNotEmpty) return no('action $i: random');
    s = res.state!;
  }
  if (s.winner?.name != json['winner'] || jsJson(s.log.map((e) => e.toJson()).toList()) != jsJson(json['log'])) return no('result');
  return (state: s, error: null);
}

/// JSON exactly as JavaScript's JSON.stringify writes it (whole doubles without ".0"), for byte-identical records.
String jsJson(Object? v) {
  if (v == null || v is bool || v is String) return jsonEncode(v);
  if (v is int) return '$v';
  if (v is double) return !v.isFinite ? 'null' : v == v.truncateToDouble() && v.abs() < 1e21 ? '${v.toInt()}' : '$v';
  if (v is List) return '[${v.map(jsJson).join(',')}]';
  if (v is Map) return '{${v.entries.map((e) => '${jsonEncode(e.key)}:${jsJson(e.value)}').join(',')}}';
  throw ArgumentError('not JSON: $v');
}
