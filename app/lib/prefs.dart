// What this phone remembers (device data only): language, volumes, recent names while not signed in, and the
// offline game in progress (its engine record plus where the phone is in it).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Prefs extends ChangeNotifier {
  Prefs(this._sp);
  final SharedPreferences _sp;

  static Future<Prefs> load() async => Prefs(await SharedPreferences.getInstance());

  String get lang => _sp.getString('lang') ?? 'en';
  set lang(String v) { _sp.setString('lang', v); notifyListeners(); }

  double get voice => _sp.getDouble('voice') ?? 1;
  set voice(double v) { _sp.setDouble('voice', v); notifyListeners(); }
  double get sfx => _sp.getDouble('sfx') ?? 1;
  set sfx(double v) { _sp.setDouble('sfx', v); notifyListeners(); }

  /// Online: does this phone narrate? (Off on all but one phone when everyone sits together.)
  bool get narrate => _sp.getBool('narrate') ?? true;
  set narrate(bool v) { _sp.setBool('narrate', v); notifyListeners(); }

  /// Has the first-launch "How to play" offer been seen (opened or dismissed)?
  bool get guideSeen => _sp.getBool('guideSeen') ?? false;
  set guideSeen(bool v) { _sp.setBool('guideSeen', v); notifyListeners(); }

  /// The last setup's names, and recently used names (chips), newest first, at most 30.
  List<String> get players => _sp.getStringList('players') ?? const [];
  set players(List<String> v) => _sp.setStringList('players', v);
  List<String> get roster => _sp.getStringList('roster') ?? const [];
  set roster(List<String> v) => _sp.setStringList('roster', v.take(30).toList());

  /// The last setup's role counts and rules (JSON).
  Map<String, Object?>? get setup => _json('setup');
  set setup(Map<String, Object?>? v) => _put('setup', v);

  /// The signed-in profile as last seen (shown while offline). The session token itself is in secure storage.
  Map<String, Object?>? get me => _json('me');
  set me(Map<String, Object?>? v) => _put('me', v);

  /// The offline game in progress, or null.
  Map<String, Object?>? get game => _json('game');
  // told a moment later: the game screen sets this while it closes, when the widget tree can't rebuild
  set game(Map<String, Object?>? v) { _put('game', v); Future.microtask(notifyListeners); }

  Map<String, Object?>? _json(String k) {
    final s = _sp.getString(k);
    if (s == null) return null;
    try { return jsonDecode(s) as Map<String, Object?>; } catch (_) { return null; }
  }
  void _put(String k, Map<String, Object?>? v) => v == null ? _sp.remove(k) : _sp.setString(k, jsonEncode(v));
}
