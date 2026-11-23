// [QA] Sprint 7: push registration and taps, Wi-Fi games into online history (the button, the guest line, every
// status, rejected reasons, the daily limit, games approved on another phone), Confirm / Not me and Accept in the bell,
// History signed out, and the Notifications row in Settings.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/account.dart';
import 'package:mafia_dealer/account_screens.dart';
import 'package:mafia_dealer/push.dart';
import 'package:mafia_engine/mafia_engine.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';

class FakePush implements PushService {
  int asked = 0;
  String? tok = 'fcm-token-for-tests-0123456789';
  final refresh = StreamController<String>.broadcast(), taps = StreamController<Map<String, String>>.broadcast();
  Map<String, String>? first;
  @override
  Future<void> ask() async => asked++;
  @override
  Future<String?> token() async => tok;
  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Future<Map<String, String>?> initial() async => first;
  @override
  Stream<Map<String, String>> get opened => taps.stream;
  final inApp = StreamController<Map<String, String>>.broadcast();
  @override
  Stream<Map<String, String>> get received => inApp.stream;
  final topics = <String, bool>{};
  @override
  Future<void> topic(String name, bool on) async => topics[name] = on;
}

/// A finished 4-player Wi-Fi game record (A B C D), as the phones keep it.
Map<String, Object?> wifiRecord() {
  final g = createGame(Setup(['A', 'B', 'C', 'D'], const Counts(1, 1, 0), defaultRules), seeded(1)).state!;
  final rec = startRecord(g);
  var s = step(rec, g, const Action.begin(), Ctx(seeded(2), 1)).state!;
  for (var i = 0; i < 4 && s.phase != Phase.end; i++) { final r = step(rec, s, Action.remove(i), Ctx(seeded(2), 2)); if (r.ok) s = r.state!; }
  return jsonDecode(jsonEncode(rec.toJson())) as Map<String, Object?>;
}

Future<void> frames(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 100)); } }

void main() {
  setUpAll(setUpHarness);

  group('push', () {
    testWidgets('signed in: Android is asked once, the token is registered with the language, and again when it changes', (t) async {
      final s = FakeServer(), tok = s.user('Sami'), push = FakePush();
      final app = await launch(t, server: s, tokens: MemoryTokens()..t = tok);
      await t.runAsync(() async { app.account.push = push; await Future<void>.delayed(const Duration(milliseconds: 50)); });
      expect(push.asked, 1);
      expect(s.pushTokens[s.idOf('Sami')], {'token': push.tok, 'lang': 'en'});
      await t.runAsync(() async { app.prefs.lang = 'ar'; await Future<void>.delayed(const Duration(milliseconds: 50)); });
      expect(s.pushTokens[s.idOf('Sami')]!['lang'], 'ar');
      await t.runAsync(() async { push.tok = 'fcm-token-renewed-0123456789'; push.refresh.add(push.tok!); await Future<void>.delayed(const Duration(milliseconds: 50)); });
      expect(s.pushTokens[s.idOf('Sami')]!['token'], 'fcm-token-renewed-0123456789');
      await t.runAsync(() async { await app.account.refresh(); });
      expect(push.asked, 1, reason: 'the permission prompt is asked once, ever');
    });

    testWidgets('signed out: nothing is asked or registered', (t) async {
      final s = FakeServer(), push = FakePush(), app = await launch(t, server: s);
      await t.runAsync(() async { app.account.push = push; await Future<void>.delayed(const Duration(milliseconds: 50)); });
      expect(push.asked, 0);
      expect(s.pushTokens, isEmpty);
    });

    testWidgets('a tapped invite to a closed room says it expired and opens the bell; friends open Friends; one tapped at launch waits for Home', (t) async {
      final s = FakeServer(), tok = s.user('Sami'), push = FakePush()..first = {'kind': 'friend_request', 'id': 'n1'};
      final app = await launch(t, server: s, tokens: MemoryTokens()..t = tok);
      await t.runAsync(() async { app.account.push = push; await Future<void>.delayed(const Duration(milliseconds: 50)); });
      await frames(t);
      expect(find.byType(FriendsScreen), findsOneWidget, reason: 'the notification that launched the app');
      await t.pageBack();
      await frames(t);
      await t.runAsync(() async { push.taps.add({'kind': 'invite', 'code': '123456', 'id': 'n2'}); await Future<void>.delayed(const Duration(milliseconds: 100)); });
      await frames(t);
      expect(find.text('This invite has expired'), findsOneWidget);
      expect(find.byType(BellSheet), findsOneWidget);
    });
  });

  group('Wi-Fi games into online history', () {
    Future<(Launched, String)> withGame(WidgetTester t, {bool host = true, bool guest = false, String lang = 'en', FakeServer? server}) async {
      final s = server ?? FakeServer(), tok = s.user('Sami');
      for (final h in ['Dareer', 'Hokan', 'Fater']) { s.user(h); }
      final app = await launch(t, server: s, tokens: MemoryTokens()..t = tok, lang: lang);
      final me = s.idOf('Sami');
      app.prefs.addWifiGame({'id': '123456-99', 'record': wifiRecord(), 'names': ['A', 'B', 'C', 'D'], 'mySeat': 0, 'at': 99, 'code': '123456', 'host': host,
        'accounts': [me, s.idOf('Dareer'), guest ? null : s.idOf('Hokan'), s.idOf('Fater')]});
      return (app, me);
    }
    Future<void> openHistory(WidgetTester t, {bool tab = true}) async {
      await tapKey(t, 'history');
      await frames(t);
      if (tab) { await tapKey(t, 'tabWifi'); await frames(t); }
    }

    testWidgets('the host asks from History → Wi-Fi: the request carries the record and every seat\'s account, then shows the progress', (t) async {
      final (app, me) = await withGame(t);
      await openHistory(t);
      await tapKey(t, 'addOnline');
      await frames(t);
      final sent = app.server.wifiAsked.single;
      expect(sent['key'], '123456-99');
      expect((sent['record'] as Map)['names'], ['A', 'B', 'C', 'D']);
      expect(sent['seats'], [for (final (i, h) in ['Sami', 'Dareer', 'Hokan', 'Fater'].indexed) {'seat': i, 'userId': app.server.idOf(h), 'name': 'ABCD'[i]}]);
      expect(find.text('Waiting for 3 of 4 to confirm'), findsOneWidget);
      expect(find.byKey(const Key('addOnline')), findsNothing, reason: 'asked once');
      expect(app.prefs.wifiGames.single['req'], {'id': 'w5', 'status': 'pending', 'reason': null});
      expect(me, isNotEmpty);
    });

    testWidgets('a guest at the table: a line instead of the button; a player who didn\'t host sees neither', (t) async {
      await withGame(t, guest: true);
      await openHistory(t);
      expect(find.text('A guest played, so this game stays on the phones.'), findsOneWidget);
      expect(find.byKey(const Key('addOnline')), findsNothing);
    });

    testWidgets('not the host: no button and no line', (t) async {
      await withGame(t, host: false);
      await openHistory(t);
      expect(find.byKey(const Key('addOnline')), findsNothing);
      expect(find.byKey(const Key('guestStays')), findsNothing);
    });

    testWidgets('a rejection shows its reason; the daily limit says to try tomorrow (Arabic too)', (t) async {
      final s = FakeServer()..wifiAnswer = {'status': 'rejected', 'reason': 'short'};
      await withGame(t, server: s);
      await openHistory(t);
      await tapKey(t, 'addOnline');
      await frames(t);
      expect(find.text('Not added: the game was too short to be real'), findsOneWidget);
    });

    testWidgets('over the daily limit: a toast, and the button stays for tomorrow', (t) async {
      final s = FakeServer()..wifiError = 'slow_down';
      await withGame(t, server: s, lang: 'ar');
      await openHistory(t);
      await tapKey(t, 'addOnline');
      await frames(t, 3);
      expect(find.text('طلبات كثيرة اليوم، حاول غدًا'), findsOneWidget);
      expect(find.byKey(const Key('addOnline')), findsOneWidget);
    });

    testWidgets('the server\'s view wins (others\' answers), and a game approved on another phone shows up from the server', (t) async {
      final s = FakeServer();
      s.wifiGames = [
        {'id': 'w1', 'key': '123456-99', 'status': 'pending', 'reason': null, 'playedAt': 99, 'players': 4, 'winner': 'citizens', 'host': true, 'waiting': 1, 'total': 4, 'gameId': null, 'seat': 0, 'role': 'mafia', 'record': null},
        {'id': 'w2', 'key': '654321-50', 'status': 'approved', 'reason': null, 'playedAt': 50, 'players': 4, 'winner': 'citizens', 'host': false, 'waiting': 0, 'total': 4, 'gameId': 'w-w2', 'seat': 2, 'role': 'citizen', 'record': wifiRecord()},
      ];
      await withGame(t, server: s);
      await openHistory(t);
      expect(find.text('Waiting for 1 of 4 to confirm'), findsOneWidget);
      expect(find.byKey(const Key('wifi_654321-50')), findsOneWidget);
      expect(find.text('In online history'), findsOneWidget);
    });
  });

  group('the bell', () {
    testWidgets('a Wi-Fi request: who asks, the game, my role; Confirm sends yes and the item goes', (t) async {
      final s = FakeServer(), tok = s.user('Dareer');
      s.user('Sami');
      s.wifiNote(s.idOf('Dareer'), s.idOf('Sami'), 'wifi_confirm', {'request': 'r1', 'status': 'pending', 'reason': null, 'players': 6, 'winner': 'mafia',
        'playedAt': DateTime(2026, 11, 23).millisecondsSinceEpoch, 'seat': 2, 'role': 'doctor'});
      await launch(t, server: s, tokens: MemoryTokens()..t = tok);
      await tapKey(t, 'bell');
      await frames(t);
      expect(find.textContaining('asks to add the Wi-Fi game of 23 November 2026 to online history: 6 players, Mafia wins. You were Doctor.'), findsOneWidget);
      await tapKey(t, 'wifiYes_r1');
      await frames(t);
      expect(s.wifiAnswers, [(s.idOf('Dareer'), 'r1', true)]);
      expect(find.byKey(const Key('wifiYes_r1')), findsNothing);
    });

    testWidgets('Not me sends no; in Arabic the item reads right to left', (t) async {
      final s = FakeServer(), tok = s.user('Dareer');
      s.user('Sami');
      s.wifiNote(s.idOf('Dareer'), s.idOf('Sami'), 'wifi_confirm', {'request': 'r2', 'status': 'pending', 'reason': null, 'players': 4, 'winner': 'citizens', 'playedAt': 0, 'seat': 1, 'role': 'citizen'});
      await launch(t, server: s, tokens: MemoryTokens()..t = tok, lang: 'ar');
      await tapKey(t, 'bell');
      await frames(t);
      expect(find.text('لست أنا'), findsOneWidget);
      expect(Directionality.of(t.element(find.byKey(const Key('wifiNo_r2')))), TextDirection.rtl);
      await tapKey(t, 'wifiNo_r2');
      await frames(t);
      expect(s.wifiAnswers.single.$3, isFalse);
    });

    testWidgets('my result in the bell, and Accept right on a friend request', (t) async {
      final s = FakeServer(), tok = s.user('Sami');
      s.user('Dareer');
      final me = s.idOf('Sami'), d = s.idOf('Dareer');
      s.friendships.add(me.compareTo(d) < 0 ? (me, d, d) : (d, me, d));
      s.note(me, d, 'friend_request');
      s.wifiNote(me, me, 'wifi_result', {'request': 'r3', 'status': 'declined', 'reason': 'not_me', 'players': 4, 'winner': 'citizens', 'playedAt': 0, 'seat': 0, 'role': 'mafia'});
      await launch(t, server: s, tokens: MemoryTokens()..t = tok);
      await tapKey(t, 'bell');
      await frames(t);
      expect(find.textContaining('Not added: a player said Not me'), findsOneWidget);
      await tapKey(t, 'accept_Dareer');
      await frames(t);
      expect(s.friends, isNotEmpty);
      expect(find.byKey(const Key('accept_Dareer')), findsNothing);
    });
  });

  testWidgets('Settings has a Notifications row (it opens Android\'s settings for the channels)', (t) async {
    await launch(t);
    await tapKey(t, 'settings');
    await frames(t, 3);
    expect(find.byKey(const Key('notifSettings')), findsOneWidget);
    expect(find.text("Invites, friends, game approvals, titles and new versions, when the app is closed. Choose which in Android's settings."), findsOneWidget);
  });
}
