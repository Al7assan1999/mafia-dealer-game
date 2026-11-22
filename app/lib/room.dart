// One online room's socket: the latest room and view (newest rev wins), the narration events in order (once each,
// also after a reconnect), the connection bar's state, and taps sent during a drop resent after reconnecting.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';

/// The bit of a socket this needs (a real dart:io WebSocket, or a scripted one in tests).
abstract class Sock {
  Stream<dynamic> get stream;
  void add(String data);
  Future<void> close([int code = 1000]);
}

class _IoSock implements Sock {
  _IoSock(this.ws);
  final WebSocket ws;
  @override
  Stream<dynamic> get stream => ws;
  @override
  void add(String data) => ws.add(data);
  @override
  Future<void> close([int code = 1000]) => ws.close(code);
}

typedef Connector = Future<Sock> Function(Uri url, List<String> protocols);
Future<Sock> ioConnect(Uri url, List<String> protocols) async => _IoSock(await WebSocket.connect(url.toString(), protocols: protocols));

/// The connection bar: nothing, red (lost, reconnecting), amber (weak; or a player's connection is lost), green (back).
enum Link { ok, down, weak, back }

class RoomConn extends ChangeNotifier {
  RoomConn(this.api, this.code, {this.connect = ioConnect});
  final Api api;
  final String code;
  final Connector connect;

  Map<String, Object?>? room, me, view;
  int rev = 0;
  String? bye; // kicked / closed / left: the room is over for this phone
  String? error; // the last refused action (err)
  bool missed = false; // too far behind: no narration of old events
  Link link = Link.ok;

  /// The server's clock minus this phone's (ms), from every `room` message: timers show the server's time.
  int clockOffset = 0;
  int get serverNow => DateTime.now().millisecondsSinceEpoch + clockOffset;

  // ---------------------------------------------------------------- chat
  final chat = <int, Map<String, Object?>>{}; // id -> message, as the server sends them
  final outbox = <String, Map<String, Object?>>{}; // my messages not confirmed yet (cid -> message + 'failed')
  final _chatTimers = <Timer>[]; // each message's "not confirmed in 10 s" timer, cancelled with the room
  final unread = <String, int>{}; // conversation ('all' or the other player's cn) -> unread count
  String? openConv; // the conversation on screen (its messages don't count as unread)
  int get myCn => (me?['cn'] as int?) ?? -99;
  int get unreadTotal => unread.values.fold(0, (a, b) => a + b);
  static String convOf(Map<String, Object?> m, int me) => m['to'] == -1 ? 'all' : '${m['from'] == me ? m['to'] : m['from']}';
  List<Map<String, Object?>> messages(String conv) =>
      (chat.values.where((m) => convOf(m, myCn) == conv).toList()..sort((a, b) => (a['id'] as int) - (b['id'] as int)));

  /// Narration: the events of a change with the view after it. After a reconnect: all the missed events at once, with
  /// the current view (the game screen narrates only what still matches it).
  final _narr = StreamController<({List<Map<String, Object?>> events, Map<String, Object?>? view})>.broadcast();
  Stream<({List<Map<String, Object?>> events, Map<String, Object?>? view})> get narration => _narr.stream;
  final _side = StreamController<Map<String, Object?>>.broadcast(); // buzz, ping, chat (one-off messages)
  Stream<Map<String, Object?>> get side => _side.stream;

  Sock? _ws;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping, _retry, _downT, _weakT, _backT;
  int _backoff = 1;
  bool _closed = false;
  final _pending = <String>[]; // sent while down: resent on reconnect (the server ignores repeats)
  final _queue = <Map<String, Object?>>[]; // events waiting for their view

  bool get open => _ws != null;
  bool get isHost => me?['host'] == true;
  String? get myUid => me?['uid'] as String?;
  List<Map<String, Object?>> get members => ((room?['members'] as List?) ?? const []).map((m) => Map<String, Object?>.from(m as Map)).toList();

  Future<void> start() => _connect();

  Future<void> _connect() async {
    if (_closed) return;
    final url = api.socket('/v1/rooms/$code/ws${rev > 0 ? '?rev=$rev' : ''}');
    _downT ??= Timer(const Duration(seconds: 3), () { if (!open && !_closed) { link = Link.down; notifyListeners(); } });
    try {
      final ws = await connect(url, ['mafia.v1', api.token ?? '']);
      if (_closed) { ws.close(); return; }
      _ws = ws;
      _sub = ws.stream.listen(_onMsg, onDone: _lost, onError: (_) => _lost(), cancelOnError: true);
      _downT?.cancel(); _downT = null;
      _backoff = 1;
      if (link == Link.down) { link = Link.back; _backT?.cancel(); _backT = Timer(const Duration(seconds: 2), () { link = Link.ok; notifyListeners(); }); }
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 10), (_) => _sendPing());
      for (final p in List.of(_pending)) { ws.add(p); }
      _pending.clear();
      notifyListeners();
    } catch (_) {
      _lost();
    }
  }

  void _sendPing() {
    try { _ws?.add('ping'); } catch (_) {}
    _weakT?.cancel();
    _weakT = Timer(const Duration(milliseconds: 1200), () { if (link == Link.ok) { link = Link.weak; notifyListeners(); } });
  }

  void _lost() {
    _sub?.cancel(); _sub = null;
    _ws = null;
    _ping?.cancel(); _weakT?.cancel();
    if (_closed || bye != null) return;
    _downT ??= Timer(const Duration(seconds: 3), () { if (!open && !_closed) { link = Link.down; notifyListeners(); } });
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff), _connect);
    _backoff = min(_backoff * 2, 10);
    notifyListeners();
  }

  void _onMsg(dynamic raw) {
    if (raw == 'pong') {
      _weakT?.cancel();
      if (link == Link.weak) { link = Link.ok; notifyListeners(); }
      return;
    }
    final m = jsonDecode(raw as String) as Map<String, Object?>;
    final r = m['rev'] as int?;
    switch (m['t']) {
      case 'events':
        if (r != null && r <= rev) return; // seen already
        if (r != null) rev = r;
        _queue.addAll((m['events'] as List).map((e) => Map<String, Object?>.from(e as Map)));
      case 'room':
        if (r != null && r < rev) return;
        room = Map<String, Object?>.from(m['room'] as Map);
        final now = m['now'] as int?;
        if (now != null) { final o = now - DateTime.now().millisecondsSinceEpoch; clockOffset = clockOffset == 0 ? o : (clockOffset * 3 + o) ~/ 4; }
        me = Map<String, Object?>.from(m['me'] as Map);
        if (r != null) rev = max(rev, r);
      case 'view':
        if (r != null && r < rev) return;
        view = m['view'] == null ? null : Map<String, Object?>.from(m['view'] as Map);
        if (r != null) rev = max(rev, r);
        // the events of this change (or, after a reconnect, every event missed meanwhile) are narrated with this view
        if (_queue.isNotEmpty) { _narr.add((events: List.of(_queue), view: view)); _queue.clear(); }
        missed = false;
      case 'missed':
        missed = true;
        _queue.clear();
      case 'err':
        final ref = m['ref'] as String?;
        if (ref != null && outbox.containsKey(ref)) { outbox[ref]!['failed'] = true; break; } // a chat message refused (slow down)
        error = m['error'] as String?;
      case 'chatAll':
        chat..clear()..addEntries((m['msgs'] as List).map((x) { final c = Map<String, Object?>.from(x as Map); return MapEntry(c['id'] as int, c); }));
      case 'chat':
        final c = Map<String, Object?>.from(m['msg'] as Map), fresh = !chat.containsKey(c['id']);
        chat[c['id'] as int] = c;
        if (m['cid'] != null) outbox.remove(m['cid']);
        final conv = convOf(c, myCn);
        if (fresh && c['from'] != myCn && conv != openConv) unread[conv] = (unread[conv] ?? 0) + 1;
      case 'bye':
        bye = m['why'] as String?;
        _closed = true;
      default:
        _side.add(m); // buzz, ping, chat…
    }
    notifyListeners();
  }

  /// Sends a chat message (to -1 = Everyone, or a player's cn). It shows as "sending" until the server confirms it, and as
  /// "not sent" if refused or unconfirmed after 10 s.
  void sendChat(int to, String text, {int? reply, List<int> mentions = const []}) {
    final cid = '${DateTime.now().microsecondsSinceEpoch}';
    final msg = {'t': 'chat', 'to': to, 'text': text, 'cid': cid, 'reply': ?reply, if (mentions.isNotEmpty) 'mentions': mentions};
    outbox[cid] = {...msg, 'at': DateTime.now().millisecondsSinceEpoch};
    send(msg);
    _chatTimers.add(Timer(const Duration(seconds: 10), () { if (outbox.containsKey(cid)) { outbox[cid]!['failed'] = true; notifyListeners(); } }));
    notifyListeners();
  }
  void retryChat(String cid) {
    final m = outbox.remove(cid);
    if (m != null) sendChat(m['to'] as int, m['text'] as String, reply: m['reply'] as int?, mentions: ((m['mentions'] as List?) ?? const []).cast<int>());
  }
  void openConversation(String? conv) { if (_gone) return; openConv = conv; if (conv != null) unread.remove(conv); notifyListeners(); }

  /// Sends an action. During a drop it waits and goes out after reconnecting.
  void send(Map<String, Object?> msg) {
    final s = jsonEncode(msg);
    error = null;
    if (_ws == null) { _pending.add(s); return; }
    try { _ws!.add(s); } catch (_) { _pending.add(s); }
  }

  /// The app went to the background (close) or came back (reconnect and catch up).
  void foreground(bool on) {
    if (_closed) return;
    if (!on) { _retry?.cancel(); _ws?.close(1000); return; }
    if (_ws == null) { _retry?.cancel(); _connect(); }
  }

  /// For tests: the network drops (the socket dies without a goodbye).
  @visibleForTesting
  void dropForTest() { _ws?.close(4001); _lost(); }

  /// Leaving this screen (the room may go on without me, or I left it).
  void close() {
    _closed = true;
    for (final t in [_ping, _retry, _downT, _weakT, _backT, ..._chatTimers]) { t?.cancel(); }
    _sub?.cancel();
    _ws?.close(1000);
    _ws = null;
  }

  @override
  void dispose() { _gone = true; close(); _narr.close(); _side.close(); super.dispose(); }
  bool _gone = false;
}
