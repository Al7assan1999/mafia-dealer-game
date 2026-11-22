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

  /// The last setup's names, and recently used names (chips), newest first, at most 30.
  List<String> get players => _sp.getStringList('players') ?? const [];
  set players(List<String> v) => _sp.setStringList('players', v);
  List<String> get roster => _sp.getStringList('roster') ?? const [];
  set roster(List<String> v) => _sp.setStringList('roster', v.take(30).toList());

  /// The last setup's role counts and rules (JSON).
  Map<String, Object?>? get setup => _json('setup');
  set setup(Map<String, Object?>? v) => _put('setup', v);

  /// The offline game in progress, or null.
  Map<String, Object?>? get game => _json('game');
  set game(Map<String, Object?>? v) { _put('game', v); notifyListeners(); }

  Map<String, Object?>? _json(String k) {
    final s = _sp.getString(k);
    if (s == null) return null;
    try { return jsonDecode(s) as Map<String, Object?>; } catch (_) { return null; }
  }
  void _put(String k, Map<String, Object?>? v) => v == null ? _sp.remove(k) : _sp.setString(k, jsonEncode(v));
}
