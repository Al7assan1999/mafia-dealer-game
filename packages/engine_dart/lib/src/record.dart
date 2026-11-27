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
  final Mode mode;
  final int? sheikh; // 1.0.0; older records are Classic with no Sheikh (their own tie rule)
  final int? framer; // 1.3.0, Shadows (1.4.0: and Lone Wolves 13+)
  final int? silencer; // 1.4.0, Lone Wolves 11+
  final int? rv; // 1.1.0 rules (GameState.rv), 3 = 1.4.0; older records replay by their own
  final List<RecordedAction> actions;
  Winner? winner;
  List<Object?> log; // JSON, as the recorder saw it
  GameRecord(this.deal, this.names, this.rules, this.roles, this.actions, this.winner, this.log,
      {this.mode = 'classic', this.sheikh, this.framer, this.silencer, this.rv});

  Map<String, Object?> toJson() => {
        'format': 1, 'deal': deal, 'names': names, 'rules': rules.toJson(), 'roles': roles.map((r) => r.name).toList(),
        if (sheikh != null) 'mode': mode,
        if (sheikh != null) 'sheikh': sheikh,
        if (framer != null) 'framer': framer,
        if (silencer != null) 'silencer': silencer,
        if (rv != null) 'rv': rv,
        'actions': actions.map((x) => x.toJson()).toList(), 'winner': winner?.name, 'log': log,
      };
}

/// A record read back from its JSON (a saved or resumed game). Check it with [replay] first.
GameRecord recordFromJson(Map<String, Object?> j) => GameRecord(
      j['deal'] as int, (j['names'] as List).cast<String>(), recordRules(Map<String, Object?>.from(j['rules'] as Map)),
      (j['roles'] as List).map((x) => Role.values.byName(x as String)).toList(),
      (j['actions'] as List).map((x) {
        final m = x as Map;
        return RecordedAction(Action.fromJson(Map<String, Object?>.from(m['a'] as Map)), m['at'] as int,
            (m['r'] as List?)?.map((d) => (d as num).toDouble()).toList());
      }).toList(),
      j['winner'] == null ? null : Winner.values.byName(j['winner'] as String), (j['log'] as List).cast<Object?>(),
      mode: j['mode'] as String? ?? 'classic', sheikh: j['sheikh'] as int?, framer: j['framer'] as int?, silencer: j['silencer'] as int?, rv: j['rv'] as int?);

/// A new record for a game just dealt (phase deal).
GameRecord startRecord(GameState s) =>
    GameRecord(s.deal, [...s.names], s.rules, [...s.roles], [], null, [], mode: s.mode, sheikh: s.sheikh, framer: s.framer, silencer: s.silencer, rv: s.rv);

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
  final sheikh = json['sheikh'], mode = json['mode'];
  final old = !json.containsKey('sheikh'); // before 1.0.0: Classic, no Sheikh
  if (old ? json.containsKey('mode') : !(sheikh is int && sheikh >= 0 && sheikh < roles.length && roles[sheikh] == Role.mafia && mode is String)) {
    return no('roles');
  }
  // 1.1.0: rv only with a Sheikh; the Bodyguard only in a 1.1.0 game
  final rv = json['rv'];
  if (json.containsKey('rv') && ((rv != 2 && rv != 3) || old)) return no('format');
  final pre = !json.containsKey('rv');
  if (pre && (count(Role.bodyguard) > 0 || mode == 'bodyguard')) return no('roles');
  // 1.3.0: the new roles and modes only in a 1.1.0+ game; the Framer only in Shadows, a Mafia other than the Sheikh
  final fresh = count(Role.hunter) + count(Role.mayor) + count(Role.watcher) > 0 || mode == 'avenger' || mode == 'shadows';
  if (fresh && pre) return no('roles');
  // 1.4.0: the Serial Killer, Cupid and their modes only in a 1.4.0 game (rv 3); the Silencer in Lone Wolves 11+
  final wave2 = count(Role.killer) + count(Role.cupid) > 0 || mode == 'lovers' || mode == 'lonewolves';
  if (wave2 && rv != 3) return no('roles');
  final m0 = mode is String ? mode : 'classic', n0 = roles.length;
  final framer = json['framer'], silencer = json['silencer'];
  if (hasFramer(m0, n0)
      ? !(framer is int && framer >= 0 && framer < roles.length && roles[framer] == Role.mafia && framer != sheikh)
      : json.containsKey('framer')) {
    return no('roles');
  }
  if (hasSilencer(m0, n0)
      ? !(silencer is int && silencer >= 0 && silencer < roles.length && roles[silencer] == Role.mafia && silencer != sheikh && silencer != framer)
      : json.containsKey('silencer')) {
    return no('roles');
  }
  final counts = Counts(count(Role.mafia), count(Role.doctor), count(Role.detective), sniper: count(Role.sniper), jester: count(Role.jester),
      bodyguard: count(Role.bodyguard));
  if (names0.any((x) => x is! String)) return no('setup: badName');
  final rules = recordRules(Map<String, Object?>.from(json['rules'] as Map));
  final c = createGame(Setup(names0.cast<String>(), counts, rules, old ? 'classic' : mode as String, count(Role.bodyguard) > 0, rv != 3), () => 0, json['deal'] as int);
  if (c.error != null) return no('setup: ${c.error}');
  // the dealt roles must be a deck this setup could deal (same counts after the setup's own limits)
  // (a 1.0.0 "All roles" deck had a Citizen where 1.1.0 deals the Bodyguard)
  final dealt = c.state!.roles;
  int n(Role r) => dealt.where((x) => x == r || (pre && r == Role.citizen && x == Role.bodyguard)).length;
  if (Role.values.any((r) => (pre && r == Role.bodyguard ? 0 : n(r)) != count(r))) return no('roles');
  var s = c.state!
    ..roles = roles
    ..sheikh = old ? null : sheikh as int
    ..framer = framer as int?
    ..silencer = silencer as int?
    ..rv = pre ? null : rv as int;
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
