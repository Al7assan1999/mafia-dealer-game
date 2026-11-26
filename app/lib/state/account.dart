import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/push.dart';
import 'package:mafia_dealer/state/models.dart';

class Account extends ChangeNotifier {
  Account(this.api, this.tokens, this.prefs, {GoogleAuth? google, this.live = true}) : google = google ?? CredentialManagerGoogle() {
    _lang = prefs.lang;
    prefs.addListener(() { if (prefs.lang != _lang) { _lang = prefs.lang; _pushRegister(); } }); // push texts follow the app's language
  }
  final Api api;
  final TokenStore tokens;
  final Prefs prefs;
  final GoogleAuth google;
  final bool live; // false in widget tests: no hub socket

  Map<String, Object?>? me; // the server's Me
  bool needsHandle = false;
  bool offline = false; // the last call found no network
  List<Person> friends = [], incoming = [], outgoing = [];
  List<Note> notes = [];
  int unread = 0;
  /// The note that just arrived live (N5 banner); null once it is gone.
  final banner = ValueNotifier<Note?>(null);
  List<String>? names; // the account's saved names (null until loaded / signed out)
  Map<String, Object?>? setup;

  bool get signedIn => me != null;
  String? get handle => me?['handle'] as String?;
  String get display => (me?['display'] as String?) ?? '';
  Person? get card => me == null ? null : Person({...me!, 'rel': 'me'});

  static const device = 'Android phone';

  Future<T?> _try<T>(Future<T> Function() f) async {
    try {
      final r = await f();
      if (offline) { offline = false; notifyListeners(); }
      return r;
    } on ApiError catch (e) {
      if (e.code == 'offline') { offline = true; notifyListeners(); }
      if (e.code == 'auth' && signedIn) await _signedOut();
      rethrow;
    }
  }

  // ---------------------------------------------------------------- session
  /// On start: a saved session signs in silently. Offline, the cached profile is shown until the network is back.
  Future<void> restore() async {
    // [S12-4] the saved account at once: reading the session (Android's secure storage) takes seconds on a cold start,
    // and Home showed "Sign in" meanwhile
    if (me == null && prefs.me != null) { me = prefs.me; notifyListeners(); }
    final t = await tokens.read();
    if (t == null) { if (me != null) { me = null; notifyListeners(); } return; }
    api.token = t;
    me = prefs.me;
    notifyListeners();
    try { await refresh(); } catch (_) {}
  }

  /// Reloads the profile, friends, bell and saved names, and (re)connects the hub.
  Future<void> refresh() async {
    final r = await _try(() => api.get('/v1/me'));
    _setMe(r!);
    await Future.wait([loadFriends(), loadNotes(), _syncSaved()].map((f) => f.catchError((_) {})));
    _hubStart();
    _pushRegister();
  }

  void _setMe(Map<String, Object?> r) {
    me = Map<String, Object?>.from(r['user'] as Map);
    needsHandle = r['needsHandle'] == true;
    prefs.me = me;
    notifyListeners();
  }

  Future<void> _signedIn(Map<String, Object?> r) async {
    api.token = r['token'] as String;
    await tokens.write(api.token);
    _setMe(r);
    await refresh().catchError((_) {});
  }

  Future<void> _signedOut() async {
    _hubStop();
    api.token = null;
    await tokens.write(null);
    me = null; needsHandle = false; friends = []; incoming = []; outgoing = []; notes = []; unread = 0; names = null; setup = null;
    prefs.me = null;
    notifyListeners();
  }

  Future<void> emailStart(String email) => _try(() => api.post('/v1/auth/email/start', {'email': email}));
  Future<void> emailVerify(String email, String code) async =>
      _signedIn((await _try(() => api.post('/v1/auth/email/verify', {'email': email, 'code': code, 'device': device})))!);
  Future<void> signInGoogle() async {
    final t = await google.idToken();
    await _signedIn((await _try(() => api.post('/v1/auth/google', {'idToken': t, 'device': device})))!);
  }

  Future<void> logout() async { try { await api.post('/v1/auth/logout'); } catch (_) {} await _signedOut(); }

  Future<List<Map<String, Object?>>> sessions() async =>
      ((await _try(() => api.get('/v1/sessions')))!['sessions'] as List).map((x) => Map<String, Object?>.from(x as Map)).toList();
  Future<void> endSession(String id, {bool current = false}) async {
    await _try(() => api.delete('/v1/sessions/$id'));
    if (current) await _signedOut();
  }

  /// Deletes the account on the server, then everything about it on this phone. Offline play stays.
  Future<void> deleteAccount() async {
    await _try(() => api.delete('/v1/me', {'confirm': 'delete'}));
    await _signedOut();
  }

  // ---------------------------------------------------------------- profile
  Future<void> patch(Map<String, Object?> fields) async => _setMe((await _try(() => api.patch('/v1/me', fields)))!);
  Future<void> avatarPreset(int i) async => _setMe({...(await _try(() => api.put('/v1/me/avatar', {'preset': i})))!, 'needsHandle': needsHandle});
  /// A JPEG, already cropped and at most 150 KB.
  Future<void> avatarPhoto(Uint8List jpeg) async =>
      _setMe({...(await _try(() => api.put('/v1/me/avatar', {'image': 'data:image/jpeg;base64,${base64Encode(jpeg)}'})))!, 'needsHandle': needsHandle});

  // ---------------------------------------------------------------- friends
  Future<void> loadFriends() async {
    final r = (await _try(() => api.get('/v1/friends')))!;
    List<Person> l(String k) => (r[k] as List).map((x) => Person(Map<String, Object?>.from(x as Map))).toList();
    friends = l('friends'); incoming = l('incoming'); outgoing = l('outgoing');
    notifyListeners();
  }

  Future<Person> find(String handle) async =>
      Person(Map<String, Object?>.from((await _try(() => api.get('/v1/users/${Uri.encodeComponent(handle.trim().replaceFirst('@', ''))}')))!['user'] as Map));
  Future<String> request(String handle) async {
    final r = (await _try(() => api.post('/v1/friend-requests', {'handle': handle.trim()})))!;
    await loadFriends();
    return r['rel'] as String;
  }
  /// [S13-4] People whose @username starts with, or whose name contains, [q] (2+ letters).
  Future<List<Person>> searchPeople(String q) async =>
      ((await _try(() => api.get('/v1/users?q=${Uri.encodeQueryComponent(q)}')))!['users'] as List).map((u) => Person(Map<String, Object?>.from(u as Map))).toList();
  Future<void> accept(String id) async { await _try(() => api.post('/v1/friend-requests/$id/accept')); await loadFriends(); }
  Future<void> decline(String id) async { await _try(() => api.delete('/v1/friend-requests/$id')); await loadFriends(); }
  Future<void> unfriend(String id) async { await _try(() => api.delete('/v1/friends/$id')); await loadFriends(); }

  // ---------------------------------------------------------------- online rooms
  /// The online room I'm in (the server knows it), or null.
  String? get roomCode => (me?['room'] as Map?)?['code'] as String?;
  /// Opens a room screen (set by the home screen; the bell uses it for invites).
  void Function(String code)? openRoom;
  /// [S13-4] who just let me in (Home says "Dareer let you in" as the room opens)
  final letIn = ValueNotifier<String?>(null);

  Future<String> createRoom() async => ((await _try(() => api.post('/v1/rooms')))!['code'] as String);
  Future<bool> roomOpen(String code) async { try { await api.get('/v1/rooms/$code'); return true; } catch (_) { return false; } }
  Future<void> reloadMe() async { try { _setMe((await _try(() => api.get('/v1/me')))!); } catch (_) {} }
  Future<void> invite(String userId, String code) => _try(() => api.post('/v1/invites', {'userId': userId, 'code': code}));
  Future<void> askToJoin(String userId) => _try(() => api.post('/v1/join-requests', {'userId': userId}));
  Future<List<Map<String, Object?>>> games() async =>
      ((await _try(() => api.get('/v1/games')))!['games'] as List).map((g) => Map<String, Object?>.from(g as Map)).toList();
  Future<Map<String, Object?>> game(String id) async => (await _try(() => api.get('/v1/games/$id')))!;
  Future<void> markGame(String id, bool valid) => _try(() => api.patch('/v1/games/$id', {'valid': valid}));

  // ---------------------------------------------------------------- safety (block, report, moderation)
  bool get isAdmin => me?['admin'] == true;
  Future<void> block(String userId) async { await _try(() => api.post('/v1/blocks', {'userId': userId})); await loadFriends().catchError((_) {}); }
  Future<void> unblock(String userId) => _try(() => api.delete('/v1/blocks/$userId'));
  Future<List<Person>> blocked() async =>
      ((await _try(() => api.get('/v1/blocks')))!['blocked'] as List).map((x) => Person(Map<String, Object?>.from(x as Map))).toList();
  /// Reports a player, or their room message (the room supplies the text).
  Future<void> report(String userId, String reason, {String? note, String? room, int? msgId}) =>
      _try(() => api.post('/v1/reports', {'userId': userId, 'reason': reason, if (note != null && note.trim().isNotEmpty) 'note': note.trim(), 'room': ?room, 'msgId': ?msgId}));
  Future<List<Map<String, Object?>>> openReports() async =>
      ((await _try(() => api.get('/v1/admin/reports')))!['reports'] as List).map((x) => Map<String, Object?>.from(x as Map)).toList();
  Future<void> moderate(String reportId, String action) => _try(() => api.post('/v1/admin/reports/$reportId', {'action': action}));

  // ---------------------------------------------------------------- the suggestions box (Sprint 19)
  /// My messages and why I can't send right now ('day' | 'waiting' | 'full' | null).
  Future<({List<Map<String, Object?>> mine, String? blocked})> feedbackMine() async {
    final r = (await _try(() => api.get('/v1/feedback')))!;
    return (mine: (r['mine'] as List).map((x) => Map<String, Object?>.from(x as Map)).toList(), blocked: r['blocked'] as String?);
  }
  Future<void> sendFeedback(Map<String, Object?> body) => _try(() => api.post('/v1/feedback', body));
  Future<Map<String, Object?>> feedbackBox() async => (await _try(() => api.get('/v1/admin/feedback')))!;
  Future<Map<String, Object?>> feedbackItem(String id) async => (await _try(() => api.get('/v1/admin/feedback/$id')))!;
  Future<void> markFeedback(String id, String status) => _try(() => api.post('/v1/admin/feedback/$id', {'status': status}));
  Future<void> deleteFeedback(String id) => _try(() => api.delete('/v1/admin/feedback/$id'));
  Future<Uint8List> feedbackShot(String id) async => (await _try(() => api.bytes('/v1/admin/feedback/$id/image')))!;
  /// Empties what the admin saw (newest `upto`); anything newer stays.
  Future<void> emptyFeedback(int upto) => _try(() => api.delete('/v1/admin/feedback?upto=$upto'));

  // ---------------------------------------------------------------- the bell
  Future<void> loadNotes() async {
    final r = (await _try(() => api.get('/v1/notifications')))!;
    notes = (r['notifications'] as List).map((x) => Note(Map<String, Object?>.from(x as Map))).toList();
    unread = r['unread'] as int? ?? 0;
    notifyListeners();
  }
  Future<void> markRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _try(() => api.post('/v1/notifications/read', {'ids': ids})).catchError((_) => null);
    await loadNotes().catchError((_) {});
  }
  Future<void> handled(String id, String result) async { await _try(() => api.post('/v1/notifications/$id/handled', {'result': result})).catchError((_) => null); await loadNotes(); }
  Future<void> readAll() async { if (unread == 0) return; await _try(() => api.post('/v1/notifications/read')); await loadNotes(); }
  Future<void> deleteNote(String? id) async { await _try(() => api.delete(id == null ? '/v1/notifications' : '/v1/notifications/$id')); await loadNotes(); }

  // ---------------------------------------------------------------- saved names and setup (decision 2)
  /// Loads them; the first time on this phone, its recent names join the account and leave the phone.
  Future<void> _syncSaved() async {
    final r = (await _try(() => api.get('/v1/me/roster')))!, s = (await _try(() => api.get('/v1/me/setup')))!;
    var server = (r['names'] as List).cast<String>();
    final local = prefs.roster;
    if (local.isNotEmpty) {
      final keys = <String>{}, merged = <String>[];
      for (final n in [...local, ...server]) { if (keys.add(n.trim().toLowerCase())) merged.add(n.trim()); }
      server = merged.take(30).toList();
      await saveNames(server);
      prefs.roster = [];
    }
    names = server;
    setup = s['setup'] == null ? null : Map<String, Object?>.from(s['setup'] as Map);
    if (setup == null && prefs.setup != null) await saveSetup(prefs.setup!).catchError((_) {});
    notifyListeners();
  }
  Future<void> saveNames(List<String> n) async { names = n; await _try(() => api.put('/v1/me/roster', {'names': n})); }
  Future<void> saveSetup(Map<String, Object?> s) async {
    final r = s['rules'], c = {'mafia': s['mafia'] ?? (s['counts'] as Map?)?['mafia'], 'detective': s['detective'] ?? (s['counts'] as Map?)?['detective']};
    setup = {'counts': c, 'rules': r, if (s['mode'] != null) 'mode': s['mode']};
    await _try(() => api.put('/v1/me/setup', setup!));
  }

  // ---------------------------------------------------------------- push notifications (S7-1)
  PushService? _push;
  String _lang = 'en';
  StreamSubscription<String>? _tokenSub;
  Map<String, String>? _pendingOpen;
  void Function(Map<String, String> data)? _onOpen;

  /// Push is available (Firebase started): register this device whenever signed in.
  set push(PushService? p) {
    _push = p;
    _tokenSub?.cancel();
    _tokenSub = p?.tokenRefresh.listen((_) => _pushRegister());
    p?.initial().then((d) { if (d != null) pushOpened(d); });
    p?.opened.listen(pushOpened);
    _pushRegister();
  }
  /// The home screen opens what a tapped notification is about; one tapped before it was ready waits for it.
  set onPushOpen(void Function(Map<String, String> data)? f) {
    _onOpen = f;
    final d = _pendingOpen;
    if (f != null && d != null) { _pendingOpen = null; f(d); }
  }
  void pushOpened(Map<String, String> data) { if (_onOpen != null) { _onOpen!(data); } else { _pendingOpen = data; } }

  Future<void> _pushRegister() async {
    final p = _push;
    if (p == null || !signedIn || api.token == null) return;
    if (!prefs.pushAsked) { prefs.pushAsked = true; await p.ask(); } // Android 13's prompt, once, after signing in
    final t = await p.token();
    if (t != null && signedIn) await api.put('/v1/me/push', {'token': t, 'lang': prefs.lang}).catchError((_) => <String, Object?>{});
  }

  // ---------------------------------------------------------------- Wi-Fi games into online history (S7-2)
  /// May I ask for this kept Wi-Fi game? I hosted it, I'm signed in, and every seat was a signed-in player.
  bool canAskWifi(Map<String, Object?> g) {
    final acc = (g['accounts'] as List?)?.cast<String?>();
    return signedIn && g['host'] == true && acc != null && acc.isNotEmpty && acc.every((x) => x != null) && acc.contains(me?['id']);
  }
  /// Was a guest at the table (so the game stays on the phones)?
  static bool hadGuest(Map<String, Object?> g) => ((g['accounts'] as List?) ?? const [null]).any((x) => x == null);
  Future<Map<String, Object?>> askWifi(Map<String, Object?> g) async {
    final acc = (g['accounts'] as List).cast<String>(), names = (g['names'] as List).cast<String>();
    final r = (await _try(() => api.post('/v1/wifi-requests', {'key': g['id'], 'record': g['record'],
      'seats': [for (var i = 0; i < acc.length; i++) {'seat': i, 'userId': acc[i], 'name': names[i]}]})))!;
    prefs.updateWifiGame(g['id'] as String, {'req': {'id': r['id'], 'status': r['status'], 'reason': r['reason']}});
    return r;
  }
  /// History → Wi-Fi from the server: my requests as host and approved games I played in.
  Future<List<Map<String, Object?>>> wifiRequests() async =>
      ((await _try(() => api.get('/v1/wifi-requests')))!['games'] as List).map((g) => Map<String, Object?>.from(g as Map)).toList();
  /// Confirm (yes) or Not me (no) from the bell.
  Future<String> answerWifi(String requestId, bool yes) async {
    final r = (await _try(() => api.post('/v1/wifi-requests/$requestId/answer', {'yes': yes})))!;
    await loadNotes().catchError((_) {});
    return r['status'] as String;
  }

  // ---------------------------------------------------------------- stats and the old app's history (S8)
  /// [S13-1] The one board, the same for everyone. source: 'all' | 'online' | 'wifi' | 'old'; days: 0 (all time) or 30.
  Future<Map<String, Object?>> stats({String source = 'all', int days = 0}) async =>
      (await _try(() => api.get('/v1/stats?source=$source&days=$days')))!;
  Future<Map<String, Object?>> player(String key, {String source = 'all', int days = 0}) async =>
      (await _try(() => api.get('/v1/stats/player?key=${Uri.encodeComponent(key)}&source=$source&days=$days')))!;
  Future<Map<String, Object?>> importOld(String code) async => (await _try(() => api.post('/v1/legacy/import', {'code': code})))!;
  /// [S12-1] Admin: every name found in imported games, and marking one real (optionally linked) / test / unknown.
  Future<List<Map<String, Object?>>> oldPlayers() async =>
      ((await _try(() => api.get('/v1/legacy/players')))!['players'] as List).map((p) => Map<String, Object?>.from(p as Map)).toList();
  Future<Map<String, Object?>> markOldPlayer(String name, String mark, {String? link}) async =>
      (await _try(() => api.put('/v1/legacy/players', {'name': name, 'mark': mark, 'link': ?link})))!;
  Future<List<Map<String, Object?>>> oldGames() async =>
      ((await _try(() => api.get('/v1/legacy/games')))!['games'] as List).map((g) => Map<String, Object?>.from(g as Map)).toList();

  // ---------------------------------------------------------------- the hub socket (presence, live notes)
  WebSocket? _ws;
  Timer? _ping, _retry;
  int _backoff = 1;
  bool _want = false;

  /// The app came to the foreground (or went away): the hub socket follows it.
  void foreground(bool on) { on ? (signedIn ? _hubStart() : null) : _hubStop(); }

  void _hubStart() {
    if (!live || !signedIn || api.token == null) return;
    _want = true;
    if (_ws != null || _retry != null) return;
    WebSocket.connect(api.socket('/v1/hub/ws').toString(), protocols: ['mafia.v1', api.token!]).then((ws) {
      if (!_want) { ws.close(1000); return; }
      _ws = ws;
      _backoff = 1;
      _ping = Timer.periodic(const Duration(seconds: 10), (_) { try { ws.add('ping'); } catch (_) {} });
      ws.listen(onHub, onDone: _hubLost, onError: (_) => _hubLost(), cancelOnError: true);
    }, onError: (_) => _hubLost());
  }

  void _hubLost() {
    _ping?.cancel();
    _ws = null;
    if (!_want || !signedIn) return;
    _retry = Timer(Duration(seconds: _backoff), () { _retry = null; _hubStart(); });
    _backoff = min(_backoff * 2, 30);
  }

  void _hubStop() {
    _want = false;
    _retry?.cancel(); _retry = null;
    _ping?.cancel();
    _ws?.close(1000);
    _ws = null;
  }

  /// One message from the hub socket (presence, a new note…). Public so a test can deliver one without a socket.
  void onHub(dynamic raw) {
    if (raw == 'pong') return;
    final m = jsonDecode(raw as String) as Map<String, Object?>;
    switch (m['t']) {
      case 'unread': unread = m['n'] as int? ?? 0;
      case 'note':
        final n = Note(Map<String, Object?>.from(m['note'] as Map));
        notes = [n, ...notes];
        unread++;
        loadFriends().catchError((_) {}); // a request or an accept changes the lists
        // [S13-4 / #9] asked to join, and the host let me in: straight into the room (Home's openRoom asks first if
        // I'm in another one); the note still lands in the bell as answered
        if (n.kind == 'let_in' && n.code != null && openRoom != null) {
          letIn.value = n.from.display;
          handled(n.id, 'joined').catchError((_) {});
          openRoom!(n.code!);
        } else {
          banner.value = n; // N5: shown on top while the app is open (the old app's banner)
        }
      case 'presence':
        for (final f in friends) {
          if (f.id == m['uid']) { f.j['on'] = m['on']; f.j['st'] = m['st']; f.j['op'] = m['op']; f.j['n'] = m['n']; }
        }
    }
    notifyListeners();
  }

  @override
  void dispose() { _hubStop(); _tokenSub?.cancel(); super.dispose(); }
}
