// [QA] Sprint 10: his playtest notes N1–N8 and P5, against the fakes (the real push and the server side are in
// server/test and the emulator session).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/account.dart';
import 'package:mafia_dealer/account_screens.dart';
import 'package:mafia_dealer/audio.dart';
import 'package:mafia_dealer/chat.dart';
import 'package:mafia_dealer/drawer.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/online.dart';
import 'package:mafia_dealer/prefs.dart';
import 'package:mafia_dealer/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show FakeRoom, openRoom, roomMsg;

Future<void> frames(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 100)); } }
void befriend(FakeServer s, String a, String b) => s.friends.add(a.compareTo(b) < 0 ? (a, b) : (b, a));
Note noteOf(FakeServer s, String me, String from, String kind, {String? code}) =>
    Note({'id': 'b1', 'kind': kind, 'from': s.card(from, me), 'code': code, 'at': 0, 'read': false});

/// The app shell (navigator keys, the room bar with its chat button) and an online room opened from Home.
Future<({FakeRoom room, Account account, Prefs prefs})> roomShell(WidgetTester t, void Function(FakeServer s, String me) setup) async {
  t.view.physicalSize = const Size(393, 851);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({'lang': 'en'});
  final prefs = await Prefs.load(), server = FakeServer(), tok = server.user('P1');
  setup(server, server.idOf('P1'));
  final account = Account(server.api(), MemoryTokens()..t = tok, prefs, google: FakeGoogle(), live: false);
  await t.runAsync(account.restore);
  await t.runAsync(account.loadFriends);
  final room = FakeRoom(), audio = Audio(prefs);
  await t.pumpWidget(MaterialApp(
    theme: noir(), supportedLocales: L.supportedLocales, navigatorKey: ActiveRoom.navigatorKey, scaffoldMessengerKey: ActiveRoom.messengerKey,
    localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    builder: (context, child) => RoomBarFrame(child: child!),
    // like Home: the friends tab with the minimized room's chat under it (R1)
    home: Builder(builder: (context) => Scaffold(body: Stack(children: [Center(child: TextButton(key: const Key('openRoom'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomScreen(account: account, prefs: prefs, audio: audio, code: '123456', connect: room.connect))),
        child: const Text('open'))),
      Positioned.fill(child: FriendsTab(account: account, prefs: prefs, audio: audio, extra: RoomChatButton(account: account))),
    ]))),
  ));
  addTearDown(() async { ActiveRoom.instance.leave(); await t.pumpWidget(const SizedBox()); });
  await tapKey(t, 'openRoom');
  await frames(t);
  room.last.push(roomMsg(1)); // members u0..u3
  room.last.push({'t': 'view', 'rev': 1, 'view': null});
  await frames(t);
  return (room: room, account: account, prefs: prefs);
}

void main() {
  setUpAll(setUpHarness);

  for (final theme in ['noir', 'neon']) {
    testWidgets('N1 ($theme): the message bar is readable: light text on the dark bar', (t) async {
      await launch(t, stored: {'theme': theme});
      toast(ActiveRoom.navigatorKey.currentContext!, 'Profile saved');
      await frames(t, 3);
      final p = t.renderObject<RenderParagraph>(find.text('Profile saved'));
      expect(p.text.style?.color, C.text);
      expect(t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor ?? Theme.of(t.element(find.byType(SnackBar))).snackBarTheme.backgroundColor, C.card2);
    });
  }

  testWidgets('N2: a friend\'s row (avatar included) opens their profile; no games yet is said plainly', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    befriend(s, s.idOf('Sami'), s.idOf('Dareer'));
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => FriendsScreen(account: a.account)));
    await frames(t);
    await t.tap(find.byKey(const Key('friendStats_Dareer')));
    await frames(t);
    expect(find.byKey(const Key('noGamesYet')), findsOneWidget);
    expect(find.text('Dareer'), findsWidgets);
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('N3 ($lang): a swipe anywhere on a message\'s line, either way, replies to it', (t) async {
      final r = (await openRoom(t, lang: lang)).room;
      r.last.push(roomMsg(1));
      r.last.push({'t': 'view', 'rev': 1, 'view': null});
      final now = DateTime.now().millisecondsSinceEpoch;
      r.last.push({'t': 'chatAll', 'msgs': [
        {'id': 1, 'from': 3, 'to': -1, 'text': 'Who is lying here?', 'at': now},
        {'id': 2, 'from': 4, 'to': -1, 'text': 'Not me', 'at': now},
      ]});
      await frames(t);
      await tapKey(t, 'chat');
      await frames(t);
      // far from the bubble: the empty end of the line
      final y1 = t.getCenter(find.byKey(const Key('row_1'))).dy, far = lang == 'ar' ? 30.0 : 360.0;
      await t.flingFrom(Offset(far, y1), const Offset(-160, 0), 900);
      await frames(t, 4);
      expect(find.textContaining('Who is lying here?'), findsNWidgets(2), reason: 'the message and the reply bar');
      await t.tap(find.byIcon(Icons.close).last);
      await frames(t, 2);
      final y2 = t.getCenter(find.byKey(const Key('row_2'))).dy;
      await t.flingFrom(Offset(200, y2), const Offset(160, 0), 900);
      await frames(t, 4);
      expect(find.textContaining('Not me'), findsNWidgets(2));
    });
  }

  testWidgets('N5: a live invite or request pops a banner; Accept works from it; it hides by itself', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    final me = s.idOf('Sami'), d = s.idOf('Dareer');
    s.friendships.add(me.compareTo(d) < 0 ? (me, d, d) : (d, me, d));
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    a.account.banner.value = noteOf(s, me, d, 'friend_request');
    await frames(t, 3);
    expect(find.byKey(const Key('noteBanner')), findsOneWidget);
    await tapKey(t, 'bannerAct');
    await frames(t);
    expect(s.friends, hasLength(1));
    expect(find.byKey(const Key('noteBanner')), findsNothing);
    String? opened;
    a.account.openRoom = (c) => opened = c;
    a.account.banner.value = noteOf(s, me, d, 'invite', code: '654321');
    await frames(t, 3);
    expect(find.text('Join'), findsOneWidget);
    await tapKey(t, 'bannerAct');
    await frames(t);
    expect(opened, '654321');
    a.account.banner.value = noteOf(s, me, d, 'invite', code: '654321');
    await frames(t, 3);
    await t.pump(const Duration(seconds: 7));
    expect(find.byKey(const Key('noteBanner')), findsNothing, reason: 'gone after 6 s');
  });

  testWidgets('N6 + N7: in my lobby the drawer offers Invite (never Ask to join); a friend in it is "In your room"; chat from the room bar', (t) async {
    final s = await roomShell(t, (s, me) {
      s.user('Dareer'); // u2: a member of the room
      s.user('Filler');
      s.user('Hokan'); // u4: online in a lobby of their own, open to requests
      s.users[s.idOf('Hokan')]!..['st'] = 'lobby'..['op'] = true;
      befriend(s, me, s.idOf('Dareer'));
      befriend(s, me, s.idOf('Hokan'));
    });
    openFriendsDrawer(ActiveRoom.navigatorKey.currentContext!, account: s.account, prefs: s.prefs, audio: Audio(s.prefs));
    await frames(t);
    expect(find.byKey(const Key('inRoom_Dareer')), findsOneWidget);
    expect(find.byKey(const Key('dInvite_Hokan')), findsOneWidget);
    expect(find.byKey(const Key('dAsk_Hokan')), findsNothing);
    await t.tapAt(const Offset(10, 400));
    await frames(t);
    await tapKey(t, 'minimize');
    await frames(t);
    expect(find.byKey(const Key('roomBar')), findsOneWidget);
    await tapKey(t, 'barChat');
    await frames(t);
    expect(find.byType(ChatScreen), findsOneWidget);
    await t.binding.handlePopRoute();
    await tapKey(t, 'roomBar'); // back in the room, so the teardown's leave closes it
    await frames(t);
  });

  testWidgets('N8: the bell marks what is new, reads it after a moment on screen, and has Mark all as read; P5 the test notification', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    s.user('Hokan');
    final me = s.idOf('Sami');
    s.note(me, s.idOf('Dareer'), 'friend_accept');
    s.note(me, s.idOf('Hokan'), 'friend_accept');
    await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    await tapKey(t, 'bell');
    await frames(t);
    expect(find.byKey(const Key('markAllRead')), findsOneWidget);
    expect(find.byKey(Key('unread_${s.notes[0]['id']}')), findsOneWidget);
    await tapKey(t, 'markAllRead');
    await frames(t);
    expect(s.notes.every((n) => n['read'] == true), true);
    expect(find.byKey(const Key('markAllRead')), findsNothing);
    expect(find.byKey(Key('unread_${s.notes[0]['id']}')), findsNothing);
    expect(s.notes, hasLength(2), reason: 'read items stay in the bell');
    await t.tapAt(const Offset(200, 40)); // close the sheet
    await frames(t);
    // P5: no push registration on this phone: it says so
    await tapKey(t, 'settings');
    await frames(t);
    await t.ensureVisible(find.byKey(const Key('testPush')));
    await t.tap(find.byKey(const Key('testPush')));
    await frames(t);
    expect(t.widget<Text>(find.byKey(const Key('testPushResult'))).data, contains('isn\'t registered for notifications'));
  });
}

