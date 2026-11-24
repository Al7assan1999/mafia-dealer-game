// Online play against a scripted room server: the lobby, host controls, newest-rev-wins, the per-phone suspense,
// a drop and catch-up (narrated once), taps resent after a drop, the connection bar, errors, and phone sizes.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/features/room/room_screen.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/state/room_conn.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';

class FakeSock implements Sock {
  final _in = StreamController<dynamic>();
  final sent = <String>[];
  bool closed = false;
  @override
  Stream<dynamic> get stream => _in.stream;
  @override
  void add(String data) { if (data == 'ping') { if (pong) _in.add('pong'); return; } sent.add(data); }
  @override
  Future<void> close([int code = 1000]) async { closed = true; if (!_in.isClosed) await _in.close(); }
  bool pong = true;
  void push(Map<String, Object?> m) => _in.add(jsonEncode(m));
  /// The network drops: the socket ends without a goodbye.
  void drop() => _in.close();
  List<Map<String, Object?>> get msgs => sent.map((s) => jsonDecode(s) as Map<String, Object?>).toList();
}

class FakeRoom {
  final urls = <Uri>[];
  final socks = <FakeSock>[];
  bool refuse = false;
  FakeSock get last => socks.last;
  Future<Sock> connect(Uri url, List<String> protocols) async {
    urls.add(url);
    if (refuse) throw Exception('no network');
    final s = FakeSock();
    socks.add(s);
    return s;
  }
}

const rules = {'skip': true, 'norep': false, 'saverev': false, 'decoy': true, 'self': true, 'rep': false, 'reveal': true, 'timer': 180, 'nightT': 0, 'ghost': false, 'skipVote': true};
Map<String, Object?> member(int i, {bool host = false, bool online = true, int? seat, bool ready = false}) =>
    {'uid': 'u$i', 'cn': i + 1, 'display': 'P${i + 1}', 'handle': 'p${i + 1}', 'avatar': {'preset': i % 10}, 'online': online, 'host': host, 'ready': ready, 'muted': false, 'seat': seat};
Map<String, Object?> roomMsg(int rev, {bool host = true, String status = 'lobby', List<Map<String, Object?>>? members, int deal = 0}) => {
      't': 'room', 'rev': rev,
      'room': {'code': '123456', 'rules': rules, 'counts': {'mafia': 1, 'doctor': 1, 'detective': 0}, 'buzzMax': 3, 'status': status, 'deal': deal, 'gameId': null, 'valid': null,
        'members': members ?? [member(0, host: true), member(1), member(2), member(3)]},
      'me': {'uid': 'u0', 'cn': 1, 'host': host},
    };
final roster = [for (var i = 0; i < 4; i++) {'name': 'P${i + 1}', 'alive': true}];
Map<String, Object?> view(int rev, String phase, {String ph = 'table', Map<String, Object?> extra = const {}}) => {
      't': 'view', 'rev': rev,
      'view': {'deal': 1, 'phase': phase, 'day': 1, 'roster': roster, 'timer': null, 'progress': null, 'board': null, 'voteId': null, 'result': null,
        'winner': null, 'roles': null, 'recap': null, 'seat': 0, 'role': 'doctor', 'alive': true, 'mates': [], 'check': null, 'ph': ph, 'night': null, 'voteOpts': null, ...extra},
    };
Map<String, Object?> nightOpts = {'key': 'doctor', 'opts': [for (var i = 0; i < 4; i++) {'seat': i, 'disabled': false, 'self': i == 0, 'teammate': false, 'lastTarget': false, 'lastNight': false, 'mateVotes': 0}], 'skip': null};

Future<({FakeRoom room, Prefs prefs, FakeServer server})> openRoom(WidgetTester t, {Size size = const Size(393, 851), String lang = 'en', double text = 1, bool narrate = true}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(() { t.view.reset(); t.platformDispatcher.clearTextScaleFactorTestValue(); });
  SharedPreferences.setMockInitialValues({'lang': lang, 'narrate': narrate});
  final prefs = await Prefs.load(), server = FakeServer(), tok = server.user('P1');
  final account = Account(server.api(), MemoryTokens()..t = tok, prefs, google: FakeGoogle(), live: false);
  await t.runAsync(account.restore);
  final room = FakeRoom();
  await t.pumpWidget(MaterialApp(
    theme: noir(), locale: Locale(lang), supportedLocales: L.supportedLocales,
    localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    home: RoomScreen(account: account, prefs: prefs, audio: Audio(prefs), code: '123456', connect: room.connect),
  ));
  await t.pump();
  addTearDown(() async { await t.pumpWidget(const SizedBox()); });
  return (room: room, prefs: prefs, server: server);
}

RoomConn connOf(WidgetTester t) => (t.state(find.byType(RoomScreen, skipOffstage: false)) as dynamic).conn as RoomConn;
Future<void> frames(WidgetTester t, [int n = 5]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 100)); } }

void main() {
  setUpAll(setUpHarness);

  testWidgets('lobby: the code, the members with the crown, the host deals; a player waits', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    await frames(t);
    expect(find.byKey(const Key('code')), findsOneWidget);
    expect(find.text('P1 (you)'), findsOneWidget);
    expect(find.text('PLAYERS (4)'), findsOneWidget);
    await tapKey(t, 'deal');
    expect(r.last.msgs.last, {'t': 'deal'});
    // not the host any more: the deal button is gone, "waiting for the host"
    r.last.push(roomMsg(2, host: false, members: [member(0), member(1, host: true), member(2), member(3)]));
    await frames(t);
    expect(find.byKey(const Key('deal')), findsNothing);
    expect(find.text('Waiting for the host'), findsOneWidget);
  });

  testWidgets('the newest rev wins: an older room or view is ignored', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(5));
    r.last.push({'t': 'view', 'rev': 5, 'view': null});
    r.last.push(roomMsg(3, members: [member(0, host: true), member(1), member(2), member(3), member(4)]));
    await frames(t);
    expect(find.text('PLAYERS (4)'), findsOneWidget);
    expect(connOf(t).rev, 5);
  });

  testWidgets('night: pick and confirm sends the choice for this night; a tap during a drop goes out once after reconnecting', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'night', ph: 'night', extra: {'night': nightOpts}));
    await frames(t);
    await tapKey(t, 'opt_2');
    await tapKey(t, 'confirm');
    expect(r.last.msgs.last, {'t': 'night', 'choice': 2, 'day': 1});
    // the network drops; the player taps again (the view still shows the night): it waits, then goes out once
    r.last.drop();
    await frames(t);
    await tapKey(t, 'opt_3');
    await tapKey(t, 'confirm');
    await t.pump(const Duration(seconds: 2)); // the retry after 1 s
    expect(r.socks.length, 2);
    expect(r.urls.last.queryParameters['rev'], '1', reason: 'reconnects with the last rev seen');
    expect(r.last.msgs, [{'t': 'night', 'choice': 3, 'day': 1}]);
  });

  testWidgets('the morning: held until the narrator says the name, then shown; after a drop the missed morning is narrated once', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'night', ph: 'nightDone'));
    await frames(t);
    // drop during the night; the morning happens meanwhile
    r.last.drop();
    await t.pump(const Duration(seconds: 2));
    expect(r.urls.last.queryParameters['rev'], '1');
    final morning = {'result': {'k': 'killed', 'seat': 2, 'role': 'citizen'}};
    r.last.push({'t': 'events', 'rev': 2, 'events': [{'t': 'phase', 'phase': 'morning', 'day': 1}]});
    r.last.push(roomMsg(3, status: 'game'));
    r.last.push(view(3, 'morning', extra: morning));
    await frames(t, 3); // (silent test audio reaches the name at once; holding is checked with the narrator off)
    expect(find.text('P3'), findsOneWidget, reason: 'the missed morning is narrated and shown');
    expect(find.text('They were: Citizen'), findsOneWidget);
    // a repeat of the same events (an old rev) changes nothing: no second suspense
    r.last.push({'t': 'events', 'rev': 2, 'events': [{'t': 'phase', 'phase': 'morning', 'day': 1}]});
    r.last.push(view(3, 'morning', extra: morning));
    await t.pump();
    expect(find.text('The sun is rising'), findsNothing);
  });

  testWidgets('too far behind ("missed"): the current view only, no narration of the past', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push({'t': 'missed'});
    r.last.push(roomMsg(9, status: 'game'));
    r.last.push(view(9, 'morning', extra: {'result': {'k': 'nobody'}}));
    await frames(t);
    expect(find.text('The sun is rising'), findsNothing);
    expect(find.text('Nobody died last night'), findsOneWidget);
  });

  testWidgets('"This phone narrates" off: no narrator, the reveal opens on the fallback timer', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push({'t': 'events', 'rev': 2, 'events': [{'t': 'phase', 'phase': 'morning', 'day': 1}]});
    r.last.push(view(2, 'morning', extra: {'result': {'k': 'killed', 'seat': 1, 'role': null}}));
    await frames(t, 3);
    expect(find.text('The sun is rising'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    expect(find.text('P2'), findsOneWidget);
  });

  testWidgets('the connection bar: red after 3 s down, green when back, amber when weak or a player is gone', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1, status: 'game', members: [member(0, host: true, seat: 0), member(1, seat: 1), member(2, seat: 2), member(3, seat: 3)]));
    r.last.push(view(1, 'day'));
    await frames(t);
    expect(find.byKey(const Key('connBar')), findsNothing, reason: 'nothing for a normal join');
    r.refuse = true;
    r.last.drop();
    await t.pump(const Duration(seconds: 4));
    expect(find.text('Connection lost · reconnecting…'), findsOneWidget);
    r.refuse = false;
    await t.pump(const Duration(seconds: 4)); // the next retry (backoff 1, 2, 4 s) gets through
    expect(find.text('Connected again'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('connBar')), findsNothing);
    r.last.pong = false;
    await t.pump(const Duration(seconds: 11));
    expect(find.text('Weak connection'), findsOneWidget);
    r.last.pong = true;
    r.last.push(roomMsg(2, status: 'game', members: [member(0, host: true, seat: 0), member(1, seat: 1, online: false), member(2, seat: 2), member(3, seat: 3)]));
    await t.pump(const Duration(seconds: 10));
    expect(find.text("P2's connection is lost"), findsOneWidget);
  });

  testWidgets('host controls: day timer and votes for the host only; "Continue" only when someone is offline', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'day', extra: {'timer': {'left': 180}}));
    await frames(t);
    await tapKey(t, 'timerGo');
    expect(r.last.msgs.last, {'t': 'timer', 'op': 'start'});
    await tapKey(t, 'secretVote');
    expect(r.last.msgs.last, {'t': 'startVote', 'open': false});
    r.last.push(roomMsg(2, status: 'game', members: [member(0, host: true, seat: 0), member(1, seat: 1, online: false), member(2, seat: 2), member(3, seat: 3)]));
    r.last.push(view(2, 'night', ph: 'nightDone', extra: {'progress': {'done': 2, 'total': 4}}));
    await frames(t);
    await tapKey(t, 'continue');
    expect(r.last.msgs.last, {'t': 'continue'});
    r.last.push(roomMsg(3, host: false, status: 'game'));
    r.last.push(view(3, 'day', extra: {'timer': {'left': 120}}));
    await frames(t);
    expect(find.byKey(const Key('timerGo')), findsNothing);
    expect(find.byKey(const Key('buzz')), findsOneWidget);
  });

  testWidgets('a refused join shows why and a way home', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push({'t': 'err', 'error': 'no_room'});
    await frames(t);
    expect(find.text('No room with that code'), findsOneWidget);
  });

  for (final (size, lang) in [(const Size(360, 640), 'ar'), (const Size(412, 915), 'en')]) {
    testWidgets('online screens fit: ${size.width.toInt()}x${size.height.toInt()} $lang at 1.3x', (t) async {
      final r = (await openRoom(t, size: size, lang: lang, text: 1.3)).room;
      r.last.push(roomMsg(1));
      r.last.push({'t': 'view', 'rev': 1, 'view': null});
      await frames(t);
      r.last.push(roomMsg(2, status: 'game'));
      r.last.push(view(2, 'night', ph: 'night', extra: {'night': nightOpts}));
      await frames(t);
      r.last.push(view(3, 'vote', ph: 'vote', extra: {'voteId': 7, 'voteOpts': [for (var i = 0; i < 4; i++) {'seat': i, 'disabled': i == 0}]}));
      await frames(t);
      expect(find.byKey(const Key('castVote')), findsOneWidget);
    });
  }
}
