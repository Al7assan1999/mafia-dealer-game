import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// What this phone remembers (device data only): language, volumes, recent names while not signed in, and the
// offline game in progress (its engine record plus where the phone is in it).

class Prefs extends ChangeNotifier {
  Prefs(this._sp);
  final SharedPreferences _sp;

  static Future<Prefs> load() async => Prefs(await SharedPreferences.getInstance());

  String get lang => _sp.getString('lang') ?? 'en';
  /// When you host (S9-4): new rooms start with these. The old app's defaults: buzz limit 3, kick in the lobby only.
  int get hostBuzzMax => _sp.getInt('hostBuzzMax') ?? 3;
  set hostBuzzMax(int v) { _sp.setInt('hostBuzzMax', v); notifyListeners(); }
  String get hostKick => _sp.getString('hostKick') ?? 'lobby';
  set hostKick(String v) { _sp.setString('hostKick', v); notifyListeners(); }
  /// Where the friends tab sits on the screen edge (0 top .. 1 bottom), as the player dragged it.
  double get drawerY => _sp.getDouble('drawerY') ?? 0;
  set drawerY(double v) => _sp.setDouble('drawerY', v);

  /// The look (S9-3): 'noir' (default) or 'neon'.
  String get theme => _sp.getString('theme') ?? 'noir';
  set theme(String v) { _sp.setString('theme', v); notifyListeners(); }
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

  /// The intro (S10-2). Seen = it played once to the end; a missing key means "seen" so updates and tests skip it,
  /// and main() marks a brand-new install as not seen (firstLaunch).
  bool get introSeen => _sp.getBool('introSeen') ?? true;
  set introSeen(bool v) => _sp.setBool('introSeen', v);
  void firstLaunch() { if (!_sp.containsKey('introSeen')) _sp.setBool('introSeen', _sp.getKeys().isNotEmpty); }
  /// Settings → Show the intro at start (off by default, as the old app after its first run).
  bool get introAtStart => _sp.getBool('introAtStart') ?? false;
  set introAtStart(bool v) { _sp.setBool('introAtStart', v); notifyListeners(); }
  /// The intro's own mute button (remembered).
  bool get introMute => _sp.getBool('introMute') ?? false;
  set introMute(bool v) => _sp.setBool('introMute', v);

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

  // ---------------------------------------------------------------- Wi-Fi / Hotspot (device data: no server involved)
  /// This phone's Wi-Fi identity (a random id kept on the phone) and the name it plays under when not signed in.
  String get deviceId {
    var id = _sp.getString('deviceId');
    if (id == null) { final r = Random.secure(); id = List.generate(16, (_) => r.nextInt(36).toRadixString(36)).join(); _sp.setString('deviceId', id); }
    return id;
  }
  String get lanName => _sp.getString('lanName') ?? '';
  set lanName(String v) => _sp.setString('lanName', v);
  /// The hosted room's snapshot for "Resume hosting" (null when not hosting).
  Map<String, Object?>? get lanHost => _json('lanHost');
  set lanHost(Map<String, Object?>? v) { _put('lanHost', v); Future.microtask(notifyListeners); }
  /// The Wi-Fi room this phone last joined as a player ({address, code}), for "Back to the Wi-Fi room".
  Map<String, Object?>? get lanJoin => _json('lanJoin');
  set lanJoin(Map<String, Object?>? v) { _put('lanJoin', v); Future.microtask(notifyListeners); }
  /// Finished Wi-Fi games played on this phone, newest first, at most 100 (kept on the phone: decision of 2026-11-22).
  List<Map<String, Object?>> get wifiGames {
    final s = _sp.getString('wifiGames');
    if (s == null) return [];
    try { return (jsonDecode(s) as List).map((x) => Map<String, Object?>.from(x as Map)).toList(); } catch (_) { return []; }
  }
  void addWifiGame(Map<String, Object?> g) {
    final all = [g, ...wifiGames.where((x) => x['id'] != g['id'])].take(100).toList();
    _sp.setString('wifiGames', jsonEncode(all));
    notifyListeners();
  }
  /// Changes fields of a kept Wi-Fi game (its request to online history: `req` = {id, status, reason}).
  void updateWifiGame(String id, Map<String, Object?> fields) {
    _sp.setString('wifiGames', jsonEncode([for (final g in wifiGames) g['id'] == id ? {...g, ...fields} : g]));
    notifyListeners();
  }

  /// Updates (S8-4): alerts on / off, the last check, the last build that ran, and the bullets of the release being installed.
  int get lastCheck => _sp.getInt('lastCheck') ?? 0;
  set lastCheck(int v) => _sp.setInt('lastCheck', v);
  int get lastBuild => _sp.getInt('lastBuild') ?? 0;
  set lastBuild(int v) => _sp.setInt('lastBuild', v);
  /// [S13-5] What's new in the version on this phone (Home → What's new), and which version they belong to.
  List<String> get versionNotes => _sp.getStringList('versionNotes') ?? const [];
  set versionNotes(List<String> v) => _sp.setStringList('versionNotes', v);
  String get versionNotesOf => _sp.getString('versionNotesOf') ?? '';
  set versionNotesOf(String v) => _sp.setString('versionNotesOf', v);
  /// [S13 P1] Games I hid from my history (this phone only: the record and everyone's stats stay).
  Set<String> get hiddenGames => (_sp.getStringList('hiddenGames') ?? const []).toSet();
  void hideGame(String id, bool hide) {
    final s = hiddenGames;
    hide ? s.add(id) : s.remove(id);
    _sp.setStringList('hiddenGames', s.toList());
    notifyListeners();
  }
  /// [S14-3] Home's "Game History" count and best player line, kept from the last time they were read (signed in).
  int? get homeGames => _sp.getInt('homeGames');
  set homeGames(int? v) { v == null ? _sp.remove('homeGames') : _sp.setInt('homeGames', v); notifyListeners(); }
  String get homeBest => _sp.getString('homeBest') ?? '';
  set homeBest(String v) { _sp.setString('homeBest', v); notifyListeners(); }
  List<String> get pendingNotes => _sp.getStringList('pendingNotes') ?? const [];
  set pendingNotes(List<String> v) => _sp.setStringList('pendingNotes', v);

  /// Has this phone asked for Android's notification permission (once, after the first sign-in)?
  bool get pushAsked => _sp.getBool('pushAsked') ?? false;
  set pushAsked(bool v) => _sp.setBool('pushAsked', v);

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
