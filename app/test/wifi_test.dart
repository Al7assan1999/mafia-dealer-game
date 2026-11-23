// [QA] Wi-Fi through the real UI: the app hosts a room (the Dart room, bridged in memory instead of sockets) and plays a
// whole game against three scripted phones; the finished game lands in History → Wi-Fi on this phone; the host
// narrates and guests start quiet; the Wi-Fi screen's list, "nothing found", address join and name check; the report
// dialog waits for a reason.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/account.dart';
import 'package:mafia_dealer/api.dart';
import 'package:mafia_dealer/audio.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/lan/lan.dart';
import 'package:mafia_dealer/lan/local_room.dart';
import 'package:mafia_dealer/lan/wifi_screen.dart';
import 'package:mafia_dealer/online.dart';
import 'package:mafia_dealer/prefs.dart';
import 'package:mafia_dealer/room.dart';
import 'package:mafia_dealer/ui.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'lan_room_test.dart' show Phone;

/// A socket into the Dart room, in memory (the real server is tested over a socket in lan_room_test.dart).
class _BridgeSock implements Sock {
  _BridgeSock(this.room);
  final LocalRoom room;
  final _in = StreamController<dynamic>();
  late final _BridgeConn conn;
  @override
  Stream<dynamic> get stream => _in.stream;
  @override
  void add(String data) => room.message(conn, data);
  @override
  Future<void> close([int code = 1000]) async { room.closed(conn); if (!_in.isClosed) await _in.close(); }
}

class _BridgeConn implements LanConn {
  _BridgeConn(this.uid, this.sock);
  @override
  final String uid;
  final _BridgeSock sock;
  @override
  void send(String data) { if (!sock._in.isClosed) sock._in.add(data); }
  @override
  void close([int code = 1000]) { if (!sock._in.isClosed) sock._in.close(); }
}

Connector bridge(LocalRoom room) => (url, protocols) async {
      final id = Identity.parse(protocols[1])!, s = _BridgeSock(room);
      s.conn = _BridgeConn(id.uid, s);
      scheduleMicrotask(() => room.join(s.conn, id, since: int.tryParse(url.queryParameters['rev'] ?? '')));
      return s;
    };

Future<Prefs> openLan(WidgetTester t, LocalRoom room, {required bool host, String uid = 'p0'}) async {
  t.view.physicalSize = const Size(393, 851);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({'lang': 'en', 'guideSeen': true});
  final prefs = await Prefs.load(), server = FakeServer(), audio = Audio(prefs);
  final account = Account(server.api(), MemoryTokens(), prefs, google: FakeGoogle(), live: false);
  final api = Api(base: 'http://127.0.0.1:$lanPort')..token = Identity(uid, 'P${uid.substring(1)}x').token();
  await t.pumpWidget(MaterialApp(
    theme: noir(), supportedLocales: L.supportedLocales,
    localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    home: RoomScreen(account: account, prefs: prefs, audio: audio, code: room.code, api: api, lan: true, lanHost: host, connect: bridge(room)),
  ));
  await t.pump();
  addTearDown(() async { await t.pumpWidget(const SizedBox()); });
  return prefs;
}

RoomConn connOf(WidgetTester t) => (t.state(find.byType(RoomScreen, skipOffstage: false)) as dynamic).conn as RoomConn;

/// The scripted phones act on whatever their latest view asks.
void bots(LocalRoom room, List<Phone> ps) {
  for (final p in ps) {
    final v = p.view, rm = p.last('room')?['room'] as Map?;
    if (v == null) continue;
    void send(Map<String, Object?> m) { final s = jsonEncode(m); if (p.got.where((x) => x['t'] == '_sent' && x['s'] == s).isEmpty) { p.got.add({'t': '_sent', 's': s}); room.message(p, s); } }
    if (v['phase'] == 'deal' && rm != null) send({'t': 'ready', 'deal': rm['deal']});
    if (v['ph'] == 'night') {
      final no = v['night'] as Map, opt = (no['opts'] as List).cast<Map>().where((o) => o['disabled'] != true).first;
      send({'t': 'night', 'choice': no['key'] == 'none' ? null : opt['seat'], 'day': v['day']});
    }
    if (v['ph'] == 'vote') {
      final o = (v['voteOpts'] as List).cast<Map>().where((x) => x['seat'] != v['seat']).toList();
      send({'t': 'vote', 'choice': o.first['seat'], 'id': v['voteId']});
    }
  }
}

void main() {
  setUpAll(setUpHarness);

  testWidgets('the app hosts a whole Wi-Fi game with three phones; it is kept in History → Wi-Fi', (t) async {
    final room = LocalRoom('654321', 'p0', rng: seeded(3));
    final prefs = await openLan(t, room, host: true);
    final ps = [for (var i = 1; i <= 3; i++) Phone('p$i')];
    for (final p in ps) { room.join(p, Identity(p.uid, 'Bot${p.uid}')); }
    await t.pump(const Duration(milliseconds: 300));
    expect(Audio(prefs).muted, isFalse);
    final c = connOf(t);
    for (var i = 0; i < 400 && c.view?['phase'] != 'end'; i++) {
      await t.pump(const Duration(milliseconds: 100));
      bots(room, ps);
      final v = c.view;
      bool on(String k) => find.byKey(Key(k)).evaluate().isNotEmpty;
      if (v == null) { if (on('deal')) await tapKey(t, 'deal'); continue; }
      if (v['phase'] == 'deal') {
        if (on('roleCard')) {
          final hold = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
          await t.pump(const Duration(milliseconds: 200));
          await hold.up();
          await t.pump();
          await tapKey(t, 'memorized');
        }
        continue;
      }
      if (v['ph'] == 'night') {
        final no = v['night'] as Map, opt = (no['opts'] as List).cast<Map>().where((o) => o['disabled'] != true).first;
        if (no['key'] != 'none') await tapKey(t, 'opt_${opt['seat']}');
        await tapKey(t, 'confirm');
        continue;
      }
      if (v['ph'] == 'vote') {
        final o = (v['voteOpts'] as List).cast<Map>().where((x) => x['seat'] != v['seat']).toList();
        await tapKey(t, 'opt_${o.first['seat']}');
        await tapKey(t, 'castVote');
        continue;
      }
      if (on('revealNow')) { await tapKey(t, 'revealNow'); continue; }
      for (final k in ['startDay', 'secretVote', 'nextNight']) { if (on(k)) { await tapKey(t, k); break; } }
    }
    expect(c.view?['phase'], 'end');
    await t.pump(const Duration(milliseconds: 300));
    final saved = prefs.wifiGames;
    expect(saved, hasLength(1));
    expect(replay(saved.single['record']).error, isNull);
    expect(saved.single['mySeat'], 0);
    expect(find.byKey(const Key('inviteFriends')), findsNothing, reason: 'no friend invites on Wi-Fi');
  });

  testWidgets('guests start with "This phone narrates" off; one tap turns it on for this room only', (t) async {
    final room = LocalRoom('111111', 'p0');
    room.join(Phone('p0'), Identity('p0', 'Host'));
    final prefs = await openLan(t, room, host: false, uid: 'p5');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
    await tapKey(t, 'narrate');
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    expect(prefs.narrate, isTrue, reason: 'the online setting is untouched (default on)');
  });

  testWidgets('Wi-Fi screen: rooms found are listed; "nothing found" helps; the name is required; an address that answers nothing says so', (t) async {
    WifiScreen.testAddresses = ['192.168.43.20'];
    WifiScreen.testScan = () async => [FoundRoom('192.168.43.1', '123456', 'Sami', 3, 'lobby')];
    addTearDown(() { WifiScreen.testScan = null; WifiScreen.testAddresses = null; });
    final app = await launch(t);
    await tapKey(t, 'wifi');
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Sami · 123456'), findsOneWidget);
    expect(find.text('3 players · waiting'), findsOneWidget);
    await t.enterText(find.byKey(const Key('lanName')), '');
    await tapKey(t, 'hostRoom');
    expect(find.byKey(const Key('error')), findsOneWidget);
    WifiScreen.testScan = () async => [];
    await tapKey(t, 'searchAgain');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('nothingFound')), findsOneWidget);
    await t.enterText(find.byKey(const Key('lanName')), 'Hokan');
    await t.enterText(find.byKey(const Key('lanAddress')), '127.0.0.1');
    await t.runAsync(() async { await t.tap(find.byKey(const Key('joinAddress'))); await Future<void>.delayed(const Duration(seconds: 2)); });
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text("Nothing answered at 127.0.0.1. Check the address on the host's screen."), findsOneWidget);
    expect(app.prefs.lanName, 'Hokan');
  });

  testWidgets('History → Wi-Fi shows the games kept on this phone, with the detail page', (t) async {
    final g = createGame(Setup(['A', 'B', 'C', 'D'], const Counts(1, 1, 0), defaultRules), seeded(1)).state!;
    final rec = startRecord(g);
    var s = g;
    for (final a in [const Action.begin()]) { s = step(rec, s, a, Ctx(seeded(2), 1)).state!; }
    for (var i = 0; i < 4; i++) { final r = step(rec, s, Action.remove(i), Ctx(seeded(2), 2)); if (r.ok) s = r.state!; if (s.phase == Phase.end) break; }
    final app = await launch(t);
    app.prefs.addWifiGame({'id': 'x', 'record': jsonDecode(jsonEncode(rec.toJson())), 'names': g.names, 'mySeat': 1, 'at': 1, 'code': '1'});
    await t.pumpWidget(MaterialApp(
      theme: noir(), supportedLocales: L.supportedLocales,
      localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: HistoryScreen(account: app.account, prefs: app.prefs),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await tapKey(t, 'tabWifi');
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('wifi_x')), findsOneWidget);
    await tapKey(t, 'wifi_x');
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('A'), findsOneWidget);
  });
}
