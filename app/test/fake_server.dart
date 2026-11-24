// A small in-memory stand-in for the server's REST API (the real one is tested in server/), so the app's account
// screens can be tested without a network. Switches: offline (no network), and codes / Google tokens are known.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/core/api.dart';

class FakeServer {
  bool offline = false;
  bool slow = false; // the next email/start answers slow_down
  final users = <String, Map<String, Object?>>{}; // id -> Me (plus 'rel')
  final sessions = <String, String>{}; // token -> user id
  final codes = <String, String>{}; // email -> code
  final byEmail = <String, String>{};
  final friendships = <(String, String, String)>[]; // (a, b, requested_by) pending; accepted ones in friends
  final friends = <(String, String)>{};
  final notes = <Map<String, Object?>>[];
  final saved = <String, Map<String, Object?>>{};
  final calls = <String>[];
  final blocks = <(String, String)>{}; // (blocker, blocked)
  final reports = <Map<String, Object?>>[];
  String? admin;
  final pushTokens = <String, Map<String, Object?>>{}; // user id -> {token, lang}
  final wifiAsked = <Map<String, Object?>>[]; // POST /v1/wifi-requests bodies
  final wifiAnswers = <(String, String, bool)>[]; // (user, request, yes)
  List<Map<String, Object?>> wifiGames = []; // GET /v1/wifi-requests
  Map<String, Object?> wifiAnswer = {'status': 'pending', 'reason': null}; // what the next request gets
  String? wifiError; // the next request fails with this (e.g. slow_down)
  final openRooms = <String>{};
  List<Map<String, Object?>> games = []; // GET /v1/games
  // Sprint 8: what the stats and old-history endpoints answer (tests fill them in)
  Map<String, Object?> statsAnswer = {'board': [], 'me': null, 'minGames': 3, 'games': 0, 'titles': {'best': null, 'mafia': null, 'det': null, 'doc': null, 'first': null}};
  Map<String, Object?>? playerAnswer;
  final statsAsked = <String>[]; // the query strings
  Object importAnswer = {'found': 0, 'imported': 0, 'duplicates': 0, 'broken': 0, 'waiting': 0}; // or an error code string
  List<Map<String, Object?>> oldPlayers = []; // [S12-1] GET /v1/legacy/players (the admin's Old players)
  List<Map<String, Object?>> oldGamesAnswer = [];
  var _n = 0;

  Api api() => Api(base: 'https://fake', client: MockClient(_handle));

  /// An account made directly (no sign-in), with a session token.
  String user(String handle, {String? email}) {
    final id = 'u${++_n}';
    users[id] = {'id': id, 'handle': handle, 'display': handle, 'avatar': {'preset': 0}, 'fav': '', 'showOnline': true, 'emails': [?email], 'google': false};
    if (email != null) byEmail[email] = id;
    final tok = 't$id';
    sessions[tok] = id;
    return tok;
  }
  String idOf(String handle) => users.values.firstWhere((u) => (u['handle'] as String?)?.toLowerCase() == handle.toLowerCase())['id'] as String;

  Map<String, Object?> card(String id, String me) {
    final u = users[id]!, a = me.compareTo(id) < 0 ? (me, id) : (id, me);
    final pend = friendships.where((f) => f.$1 == a.$1 && f.$2 == a.$2).firstOrNull;
    final rel = friends.contains(a) ? 'friends' : pend == null ? 'none' : pend.$3 == me ? 'requested' : 'incoming';
    return {'id': id, 'handle': u['handle'], 'display': u['display'], 'avatar': u['avatar'], 'fav': u['fav'], 'rel': id == me ? 'me' : rel,
      if (rel == 'friends') ...{'on': true, 'st': u['st'] ?? '', 'op': u['op'] ?? false, 'n': u['n'] ?? 0}};
  }

  Future<http.Response> _handle(http.Request r) async {
    if (offline) throw const SocketException('no network');
    final path = r.url.path, m = r.method, body = r.body.isEmpty ? <String, Object?>{} : jsonDecode(r.body) as Map<String, Object?>;
    calls.add('$m $path');
    http.Response ok(Object j) => http.Response(jsonEncode(j), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    http.Response err(int s, String e) => http.Response(jsonEncode({'error': e}), s);
    final tok = r.headers['authorization']?.replaceFirst('Bearer ', ''), me = tok == null ? null : sessions[tok];
    Map<String, Object?> meOf(String id) => {'user': {...users[id]!, 'admin': id == admin, 'room': null}, 'needsHandle': users[id]!['handle'] == null};
    String newSession(String id) { final t = 's${++_n}'; sessions[t] = id; return t; }

    if (path == '/v1/auth/email/start') {
      if (slow) { slow = false; return err(429, 'slow_down'); }
      codes[body['email'] as String] = '123456';
      return ok({'ok': true});
    }
    if (path == '/v1/auth/email/verify') {
      final e = body['email'] as String;
      if (codes[e] != body['code']) return err(400, 'code');
      var id = byEmail[e];
      if (id == null) {
        id = 'u${++_n}';
        users[id] = {'id': id, 'handle': null, 'display': e.split('@').first, 'avatar': {'preset': 0}, 'fav': '', 'showOnline': true, 'emails': [e], 'google': false};
        byEmail[e] = id;
      }
      return ok({'token': newSession(id), ...meOf(id)});
    }
    if (path == '/v1/auth/google') {
      if (body['idToken'] != FakeGoogle.token) return err(401, 'google');
      final id = byEmail['g@example.com'] ??= user('gUser', email: 'g@example.com').substring(1);
      return ok({'token': newSession(id), ...meOf(id)});
    }
    if (me == null) return err(401, 'auth');

    if (path == '/v1/auth/logout') { sessions.remove(tok); return ok({'ok': true}); }
    if (path == '/v1/me' && m == 'GET') return ok(meOf(me));
    if (path == '/v1/me' && m == 'PATCH') {
      final h = body['handle'] as String?;
      if (h != null && users.values.any((u) => u['id'] != me && (u['handle'] as String?)?.toLowerCase() == h.replaceFirst('@', '').toLowerCase())) return err(409, 'handle_taken');
      users[me]!.addAll({...body, if (h != null) 'handle': h.replaceFirst('@', '')});
      return ok(meOf(me));
    }
    if (path == '/v1/me' && m == 'DELETE') {
      if (body['confirm'] != 'delete') return err(400, 'bad_request');
      users.remove(me);
      sessions.removeWhere((_, v) => v == me);
      return ok({'ok': true});
    }
    if (path == '/v1/me/avatar') {
      if (body['preset'] != null) {
        users[me]!['avatar'] = {'preset': body['preset']};
      } else {
        final b64 = (body['image'] as String).split(',').last;
        if (base64Decode(b64).length > 150000) return err(413, 'too_big');
        users[me]!['avatar'] = {'photo': 1};
        lastPhoto = base64Decode(b64);
      }
      return ok({'user': users[me]});
    }
    if (path == '/v1/me/roster') {
      if (m == 'PUT') saved.putIfAbsent(me, () => {})['names'] = body['names'];
      return ok({'names': saved[me]?['names'] ?? []});
    }
    if (path == '/v1/me/setup') {
      if (m == 'PUT') saved.putIfAbsent(me, () => {})['setup'] = body;
      return ok({'setup': saved[me]?['setup']});
    }
    if (path == '/v1/sessions') {
      return ok({'sessions': [for (final e in sessions.entries) if (e.value == me) {'id': e.key, 'device': 'Android phone', 'createdAt': 0, 'lastSeenAt': 0, 'current': e.key == tok}]});
    }
    if (path.startsWith('/v1/sessions/')) { sessions.remove(path.split('/').last); return ok({'ok': true}); }
    if (path == '/v1/games' && m == 'GET') return ok({'games': games}); // [S13 P1] the online history
    if (path == '/v1/users' && m == 'GET') { // [S13-4] search: the start of an @handle or any part of a name
      final q = (r.url.queryParameters['q'] ?? '').toLowerCase();
      if (q.length < 2) return err(400, 'bad_request');
      final hits = users.values.where((u) => u['id'] != me && u['handle'] != null && !blocks.contains((me, u['id'] as String)) && !blocks.contains((u['id'] as String, me))
          && ((u['handle'] as String).toLowerCase().startsWith(q) || (u['display'] as String).toLowerCase().contains(q)));
      return ok({'users': [for (final u in hits.take(20)) card(u['id'] as String, me)]});
    }
    if (path.startsWith('/v1/users/')) {
      final h = Uri.decodeComponent(path.split('/').last);
      final u = users.values.where((u) => (u['handle'] as String?)?.toLowerCase() == h.toLowerCase()).firstOrNull;
      return u == null ? err(404, 'not_found') : ok({'user': card(u['id'] as String, me)});
    }
    if (path == '/v1/friends') {
      final mine = [for (final f in friends) if (f.$1 == me || f.$2 == me) f.$1 == me ? f.$2 : f.$1];
      final inc = [for (final f in friendships) if ((f.$1 == me || f.$2 == me) && f.$3 != me) f.$3];
      final out = [for (final f in friendships) if (f.$3 == me) f.$1 == me ? f.$2 : f.$1];
      return ok({'friends': mine.map((i) => card(i, me)).toList(), 'incoming': inc.map((i) => card(i, me)).toList(), 'outgoing': out.map((i) => card(i, me)).toList()});
    }
    if (path.startsWith('/v1/friends/') && m == 'DELETE') {
      final o = path.split('/').last;
      friends.removeWhere((f) => (f.$1 == me && f.$2 == o) || (f.$2 == me && f.$1 == o));
      return ok({'rel': 'none'});
    }
    if (path == '/v1/friend-requests' && m == 'POST') {
      final h = (body['handle'] as String).replaceFirst('@', '');
      final u = users.values.where((u) => (u['handle'] as String?)?.toLowerCase() == h.toLowerCase()).firstOrNull;
      if (u == null) return err(404, 'not_found');
      final o = u['id'] as String;
      if (o == me) return err(400, 'self');
      final a = me.compareTo(o) < 0 ? (me, o) : (o, me);
      final pend = friendships.where((f) => f.$1 == a.$1 && f.$2 == a.$2).firstOrNull;
      if (pend != null && pend.$3 == o) { friendships.remove(pend); friends.add(a); return ok({'rel': 'friends', 'user': card(o, me)}); }
      if (pend == null && !friends.contains(a)) friendships.add((a.$1, a.$2, me));
      return ok({'rel': 'requested', 'user': card(o, me)});
    }
    if (path.startsWith('/v1/friend-requests/')) {
      final o = path.split('/')[3], a = me.compareTo(o) < 0 ? (me, o) : (o, me);
      friendships.removeWhere((f) => f.$1 == a.$1 && f.$2 == a.$2);
      if (path.endsWith('/accept')) { friends.add(a); return ok({'rel': 'friends'}); }
      return ok({'rel': 'none'});
    }
    if (path == '/v1/blocks' && m == 'GET') return ok({'blocked': [for (final b in blocks) if (b.$1 == me) card(b.$2, me)]});
    if (path == '/v1/blocks' && m == 'POST') {
      final o = body['userId'] as String;
      blocks.add((me, o));
      friends.removeWhere((f) => (f.$1 == me && f.$2 == o) || (f.$2 == me && f.$1 == o));
      return ok({'ok': true});
    }
    if (path.startsWith('/v1/blocks/')) { blocks.remove((me, path.split('/').last)); return ok({'ok': true}); }
    if (path == '/v1/reports') { reports.add({...body, 'by': me, 'id': 'r${++_n}'}); return ok({'ok': true}); }
    if (path.startsWith('/v1/admin/')) {
      if (me != admin) return err(403, 'forbidden');
      if (m == 'GET') return ok({'reports': [for (final r in reports) {'id': r['id'], 'reason': r['reason'], 'note': r['note'] ?? '', 'display': users[r['userId']]?['display'], 'handle': users[r['userId']]?['handle'], 'reporter': users[r['by']]?['display'], 'message': null}]});
      final r = reports.firstWhere((x) => x['id'] == path.split('/').last);
      reports.remove(r);
      if (body['action'] == 'ban') { users[r['userId']]!['banned'] = true; sessions.removeWhere((_, v) => v == r['userId']); }
      return ok({'ok': true});
    }
    if (path == '/v1/me/push') { if (m == 'PUT') { pushTokens[me] = body; } else { pushTokens.remove(me); } return ok({'ok': true}); }
    if (path == '/v1/wifi-requests' && m == 'POST') {
      if (wifiError != null) { final e = wifiError!; wifiError = null; return err(429, e); }
      wifiAsked.add(body);
      return ok({'id': 'w${++_n}', ...wifiAnswer});
    }
    if (path == '/v1/wifi-requests' && m == 'GET') return ok({'games': wifiGames});
    if (path.startsWith('/v1/wifi-requests/') && path.endsWith('/answer')) {
      final id = path.split('/')[3];
      wifiAnswers.add((me, id, body['yes'] == true));
      notes.removeWhere((n) => n['to'] == me && n['id'] == 'w:$id');
      return ok({'status': 'pending'});
    }
    if (path == '/v1/stats') { statsAsked.add(r.url.query); return ok(statsAnswer); }
    if (path == '/v1/stats/player') return playerAnswer == null ? err(404, 'not_found') : ok(playerAnswer!);
    if (path == '/v1/legacy/players' && m == 'GET') return admin == me ? ok({'players': oldPlayers}) : err(403, 'forbidden');
    if (path == '/v1/legacy/players' && m == 'PUT') {
      if (admin != me) return err(403, 'forbidden');
      final link = body['link'] as String?;
      if (link != null && !users.values.any((u) => (u['handle'] as String?)?.toLowerCase() == link.replaceAll('@', '').toLowerCase())) return err(404, 'not_found');
      final p = oldPlayers.firstWhere((x) => x['name'] == body['name']);
      p['mark'] = body['mark']; p['link'] = body['mark'] == 'real' && link != null ? '@${link.replaceAll('@', '')}' : null;
      return ok({'ok': true, 'name': p['name'], 'mark': p['mark'], 'link': p['link']});
    }
    if (path == '/v1/legacy/import') { final a = importAnswer; return a is String ? err(a == 'busy' ? 502 : 404, a) : ok(a); }
    if (path == '/v1/legacy/games') return ok({'games': oldGamesAnswer});
    if (path.startsWith('/v1/rooms/') && m == 'GET') return openRooms.contains(path.split('/').last) ? ok({'open': true, 'status': 'lobby', 'host': 'x'}) : err(404, 'no_room');
    if (path == '/v1/notifications' && m == 'GET') {
      final l = notes.where((n) => n['to'] == me).toList();
      return ok({'notifications': l, 'unread': l.where((n) => n['read'] != true).length});
    }
    if (path == '/v1/notifications/read') {
      final ids = (body['ids'] as List?)?.cast<String>(); // the given ones (N8), or all
      for (final n in notes) { if (n['to'] == me && (ids == null || ids.contains(n['id']))) n['read'] = true; }
      return ok({'ok': true});
    }
    if (path == '/v1/me/push/test') { final has = pushTokens.containsKey(me); return ok({'devices': has ? 1 : 0, 'thisPhone': has}); }
    if (path.startsWith('/v1/notifications') && m == 'DELETE') {
      final id = path.split('/').length > 3 ? path.split('/').last : null;
      notes.removeWhere((n) => n['to'] == me && (id == null || n['id'] == id));
      return ok({'ok': true});
    }
    return err(404, 'not_found');
  }

  List<int>? lastPhoto;

  /// A Wi-Fi request in someone's bell: asked to confirm (wifi_confirm) or my result (wifi_result).
  void wifiNote(String to, String fromId, String kind, Map<String, Object?> wifi) =>
      notes.add({'id': 'w:${wifi['request']}', 'to': to, 'kind': kind, 'from': card(fromId, to), 'code': null, 'at': 0, 'expiresAt': 0, 'read': false, 'wifi': wifi});

  /// A friend note in someone's bell.
  void note(String to, String fromId, String kind) =>
      notes.add({'id': 'n${++_n}', 'to': to, 'kind': kind, 'from': card(fromId, to), 'code': null, 'at': 0, 'expiresAt': 0, 'read': false});
}

class FakeGoogle implements GoogleAuth {
  static const token = 'google-id-token-for-tests';
  bool cancel = false;
  @override
  bool available = true;
  @override
  Future<String> idToken() async { if (cancel) throw ApiError('cancel'); return token; }
}
