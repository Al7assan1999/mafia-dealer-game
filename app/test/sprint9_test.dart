// [QA] Sprint 9: minimize (the bar, back on the same connection, pulled back by a deal, kicked while away, leave first),
// host defaults reaching a new room, the friends drawer, the Look and host settings, Back on Home, bell history, the
// Wi-Fi list greying out games in progress, and Neon rendering the main screens.

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/features/wifi/lan.dart';
import 'package:mafia_dealer/features/wifi/wifi_screen.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/features/room/room_bar.dart';
import 'package:mafia_dealer/features/room/room_screen.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show FakeRoom, roomMsg, view;

Future<void> tapText(WidgetTester t, String text) async { await t.tap(find.text(text).last); await t.pump(); }
Future<void> frames(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 100)); } }

/// An app shell like the real one (navigator and messenger keys, the room bar), with a Home that opens a room.
Future<({FakeRoom room, Prefs prefs, Account account})> shell(WidgetTester t, {Map<String, Object> stored = const {}}) async {
  t.view.physicalSize = const Size(393, 851);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({'lang': 'en', ...stored});
  final prefs = await Prefs.load(), server = FakeServer(), tok = server.user('P1');
  final account = Account(server.api(), MemoryTokens()..t = tok, prefs, google: FakeGoogle(), live: false);
  await t.runAsync(account.restore);
  final room = FakeRoom(), audio = Audio(prefs);
  await t.pumpWidget(MaterialApp(
    theme: noir(), supportedLocales: L.supportedLocales, navigatorKey: ActiveRoom.navigatorKey, scaffoldMessengerKey: ActiveRoom.messengerKey,
    localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    builder: (context, child) => RoomBarFrame(child: child!),
    home: Builder(builder: (context) => Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextButton(key: const Key('openRoom'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RoomScreen(account: account, prefs: prefs, audio: audio, code: '123456', connect: room.connect))), child: const Text('open')),
      TextButton(key: const Key('somethingElse'), onPressed: () async { if (await leaveRoomFirst(context)) prefs.lanName = 'started'; }, child: const Text('else')),
    ])))),
  ));
  addTearDown(() async { ActiveRoom.instance.leave(); await t.pumpWidget(const SizedBox()); });
  await tapKey(t, 'openRoom');
  await frames(t);
  room.last.push(roomMsg(1));
  room.last.push({'t': 'view', 'rev': 1, 'view': null});
  await frames(t);
  return (room: room, prefs: prefs, account: account);
}

void main() {
  setUpAll(setUpHarness);

  group('minimize', () {
    testWidgets('Home keeps the room: the bar, back on the same connection, no minimize once the game runs', (t) async {
      final s = await shell(t);
      await tapKey(t, 'minimize');
      await frames(t);
      expect(find.byType(RoomScreen), findsNothing);
      expect(find.text('Your room · 4 players'), findsOneWidget);
      await tapKey(t, 'roomBar');
      await frames(t);
      expect(find.byType(RoomScreen), findsOneWidget);
      expect(s.room.socks, hasLength(1), reason: 'the same connection, no reconnect');
      expect(find.byKey(const Key('roomBar')), findsNothing);
      s.room.last.push(view(2, 'deal'));
      await frames(t);
      expect(find.byKey(const Key('minimize')), findsNothing, reason: 'lobby only');
    });

    testWidgets('dealing the roles pulls a minimized player back, with a note', (t) async {
      final s = await shell(t);
      await tapKey(t, 'minimize');
      await frames(t);
      s.room.last.push(view(2, 'deal'));
      await frames(t, 10);
      expect(find.byType(RoomScreen), findsOneWidget);
      expect(find.text('Roles are being dealt'), findsOneWidget);
    });

    testWidgets('kicked while away: the bar goes and the player is told where they are', (t) async {
      final s = await shell(t);
      await tapKey(t, 'minimize');
      await frames(t);
      s.room.last.push({'t': 'bye', 'why': 'kicked'});
      await frames(t);
      expect(find.byKey(const Key('roomBar')), findsNothing);
      expect(find.textContaining('removed'), findsWidgets);
    });

    testWidgets('starting something else asks first; Leave sends the goodbye and drops the bar', (t) async {
      final s = await shell(t);
      await tapKey(t, 'minimize');
      await frames(t);
      await tapKey(t, 'somethingElse');
      await frames(t, 3);
      expect(find.text('Leave your room first?'), findsOneWidget);
      await tapText(t, 'Leave room');
      await frames(t);
      expect(s.room.last.msgs.last, {'t': 'leave'});
      expect(find.byKey(const Key('roomBar')), findsNothing);
      expect(s.prefs.lanName, 'started');
    });
  });

  testWidgets('a room I host starts with my Settings (buzz limit, kick rule), sent once', (t) async {
    final s = await shell(t, stored: {'hostBuzzMax': 5, 'hostKick': 'any'});
    final setups = s.room.last.msgs.where((m) => m['t'] == 'setup').toList();
    expect(setups, hasLength(1));
    expect(setups.single, containsPair('buzzMax', 5));
    expect(setups.single, containsPair('kick', 'any'));
  });

  group('the friends drawer', () {
    Future<FakeServer> friends(WidgetTester t, {String lang = 'en'}) async {
      final s = FakeServer(), tok = s.user('Sami');
      for (final h in ['Dareer', 'Hokan']) { s.user(h); }
      final me = s.idOf('Sami'), d = s.idOf('Dareer'), h = s.idOf('Hokan');
      s.friends.add(me.compareTo(d) < 0 ? (me, d) : (d, me));
      s.friendships.add(me.compareTo(h) < 0 ? (me, h, h) : (h, me, h));
      await launch(t, server: s, tokens: MemoryTokens()..t = tok, lang: lang, stored: {'guideSeen': true});
      await frames(t);
      return s;
    }

    testWidgets('the edge tab: online friends and a dot for requests; opens to requests first, then friends with Invite', (t) async {
      final s = await friends(t);
      expect(find.byKey(const Key('friendsTab')), findsOneWidget);
      expect(find.byKey(const Key('onlineCount')), findsOneWidget);
      await tapKey(t, 'friendsTab');
      await frames(t);
      expect(find.byKey(const Key('friendsDrawer')), findsOneWidget);
      expect(find.byKey(const Key('dReq_Hokan')), findsOneWidget);
      expect(find.byKey(const Key('dInviteNew_Dareer')), findsOneWidget, reason: 'Invite from Home: no room yet');
      await tapKey(t, 'dAccept_Hokan');
      await frames(t);
      expect(s.friends, hasLength(2));
      await t.tapAt(const Offset(10, 400)); // the dimmed side closes it
      await frames(t);
      expect(find.byKey(const Key('friendsDrawer')), findsNothing);
    });

    testWidgets('drag the tab up or down: the spot is kept', (t) async {
      await friends(t);
      final before = t.getTopLeft(find.byKey(const Key('friendsTab'))).dy;
      await t.drag(find.byKey(const Key('friendsTab')), const Offset(0, 150));
      await frames(t);
      expect(t.getTopLeft(find.byKey(const Key('friendsTab'))).dy, greaterThan(before + 100));
      expect((await SharedPreferences.getInstance()).getDouble('drawerY'), greaterThan(0));
    });

    testWidgets('in Arabic the tab sits on the left edge', (t) async {
      await friends(t, lang: 'ar');
      expect(t.getTopLeft(find.byKey(const Key('friendsTab'))).dx, lessThan(50));
    });
  });

  testWidgets('Settings: Look switches to Neon at once; host defaults are kept', (t) async {
    final app = await launch(t, stored: {'guideSeen': true});
    await tapKey(t, 'settings');
    await frames(t, 3);
    await tapKey(t, 'theme_neon');
    await frames(t, 3);
    expect(app.prefs.theme, 'neon');
    expect(C.neon, isTrue);
    await t.scrollUntilVisible(find.byKey(const Key('kickMode')), 200, scrollable: find.byType(Scrollable).last);
    await tapKey(t, 'buzzMore');
    await tapText(t, 'Any time');
    await frames(t, 2);
    expect(app.prefs.hostBuzzMax, 4);
    expect(app.prefs.hostKick, 'any');
    app.prefs.theme = 'noir';
    await frames(t, 2);
    expect(C.neon, isFalse);
  });

  testWidgets('phone Back on Home asks before closing the app', (t) async {
    await launch(t, stored: {'guideSeen': true});
    await t.binding.handlePopRoute();
    await frames(t, 3);
    expect(find.text('Close Mafia Dealer?'), findsOneWidget);
    await tapText(t, 'Cancel');
  });

  testWidgets('bell history: an answered item is read-only with its result', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    s.note(s.idOf('Sami'), s.idOf('Dareer'), 'friend_request');
    s.notes.last['result'] = 'declined';
    s.notes.last['read'] = true;
    await launch(t, server: s, tokens: MemoryTokens()..t = tok);
    await tapKey(t, 'bell');
    await frames(t);
    expect(find.text('Declined'), findsOneWidget);
    expect(find.byKey(const Key('accept_Dareer')), findsNothing);
  });

  testWidgets('Wi-Fi list: a game in progress I hold no seat in is shown greyed, not offered', (t) async {
    WifiScreen.testAddresses = ['192.168.43.20'];
    WifiScreen.testScan = () async => [FoundRoom('192.168.43.1', '482913', 'Sami', 4, 'lobby'), FoundRoom('192.168.43.7', '119034', 'Hokan', 7, 'game')];
    addTearDown(() { WifiScreen.testScan = null; WifiScreen.testAddresses = null; });
    await launch(t, stored: {'guideSeen': true, 'lanName': 'Me'});
    await tapKey(t, 'wifi');
    await frames(t);
    expect(find.byKey(const Key('playing_119034')), findsOneWidget);
    expect(find.text("Playing · you can't join"), findsOneWidget);
    expect(find.byKey(const Key('playing_482913')), findsNothing);
  });
}
