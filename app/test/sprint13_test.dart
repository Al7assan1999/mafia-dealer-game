// [QA] Sprint 13: his 19 notes after 0.4.2 (docs/sprint-13-prd.md). Each test is an attempt to break one AC; the
// server side (one board, admin-only import, search) is in server/test.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart' show SqSwitchTile;
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/features/chat/chat_screen.dart';
import 'package:mafia_dealer/features/friends/friends_screen.dart';
import 'package:mafia_dealer/features/history/history_screen.dart';
import 'package:mafia_dealer/features/home/home_footer.dart';
import 'package:mafia_dealer/features/room/room_screen.dart';
import 'package:mafia_dealer/features/update/updater.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show frames, openRoom, roomMsg;
import 'sprint10_fixes_test.dart' show befriend, noteOf, roomShell;
import 'sprint8_test.dart' show FakeInstaller;

void main() {
  setUpAll(setUpHarness);

  // ---------------------------------------------------------------- S13-2: room navigation and the bar
  testWidgets('#17: Home → chat (from the chat button) → the room bar → the room → Home lands on Home, not the chat', (t) async {
    await roomShell(t, (s, me) {});
    await tapKey(t, 'minimize');
    await frames(t);
    await tapKey(t, 'barChat');
    await frames(t);
    expect(find.byType(ChatScreen), findsOneWidget);
    await tapKey(t, 'roomBar');
    await frames(t);
    expect(find.byType(RoomScreen), findsOneWidget);
    await tapKey(t, 'minimize');
    await frames(t);
    expect(find.byType(ChatScreen), findsNothing, reason: 'the chat was closed when the room re-opened');
    expect(find.byKey(const Key('openRoom')), findsOneWidget, reason: 'Home');
    await tapKey(t, 'roomBar'); // back in the room, so the teardown's leave closes it
    await frames(t);
  });

  testWidgets('#18: the room bar as the old one: a live dot, "Back to room", and a dropped link said in the bar', (t) async {
    final s = await roomShell(t, (s, me) {});
    await tapKey(t, 'minimize');
    await frames(t);
    expect(find.byKey(const Key('roomBarDot')), findsOneWidget);
    expect(find.text('Back to room'), findsOneWidget);
    expect(find.textContaining('Your room'), findsOneWidget);
    s.room.refuse = true; // the network is gone, not only this socket
    s.room.last.drop();
    await t.pump(const Duration(seconds: 4));
    expect(find.text('Reconnecting to your room…'), findsOneWidget, reason: 'the old app said it in the bar itself');
    s.room.refuse = false;
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Reconnecting to your room…'), findsNothing, reason: 'back: the bar says the room again');
    await tapKey(t, 'roomBar');
    await frames(t);
  });

  testWidgets('#13: the rules are a card: preset + chips folded; a tap opens the switches in groups; the host can change one', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    await frames(t);
    await t.ensureVisible(find.byKey(const Key('rulesCard')));
    expect(find.byKey(const Key('rulesPreset')), findsOneWidget);
    expect(find.text('Mafia can skip a kill'), findsNothing, reason: 'folded');
    expect(find.textContaining('Talk '), findsOneWidget, reason: 'the discussion time as a chip');
    await tapKey(t, 'rulesToggle');
    await frames(t, 2);
    expect(find.text('Night'), findsOneWidget);
    expect(find.text('Day and reveals'), findsOneWidget);
    final sw = find.widgetWithText(SqSwitchTile, 'Mafia can skip a kill');
    await t.ensureVisible(sw);
    await t.tap(sw);
    await frames(t);
    expect(r.last.msgs.last['t'], 'setup');
    await tapKey(t, 'rulesToggle');
    await frames(t, 2);
    expect(find.text('Mafia can skip a kill'), findsNothing, reason: 'folds again');
  });

  // ---------------------------------------------------------------- S13-3: the chat
  testWidgets('#4–#6: "@" in the box offers players; Send is centred on the box; the reply bar is exactly the box\'s width', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    r.last.push({'t': 'chatAll', 'msgs': [{'id': 1, 'from': 3, 'to': -1, 'text': 'Who is lying here?', 'at': DateTime.now().millisecondsSinceEpoch}]});
    await frames(t);
    await tapKey(t, 'chat');
    await frames(t);
    final box = find.byKey(const Key('chatText')), send = find.byKey(const Key('chatSend'));
    expect((t.getCenter(send).dy - t.getCenter(box).dy).abs(), lessThan(3), reason: '#5: Send centred on the box');
    expect(find.text('0/200'), findsNothing, reason: 'no counter line pushing the box up');
    // [QA] "@" in the middle of a sentence, then a filter that matches nobody
    await t.enterText(box, 'vote @');
    await frames(t, 2);
    expect(find.byKey(const Key('mentionList')), findsOneWidget);
    await t.enterText(box, 'vote @zz');
    await frames(t, 2);
    expect(find.byKey(const Key('mentionList')), findsNothing);
    await t.enterText(box, 'email@x'); // an "@" inside a word is not a mention
    await frames(t, 2);
    expect(find.byKey(const Key('mentionList')), findsNothing);
    await t.enterText(box, 'x' * 160);
    await frames(t, 2);
    expect(find.text('160/200'), findsOneWidget, reason: 'the counter near the limit');
    await t.enterText(box, '');
    await t.tap(find.byKey(const Key('msg_1')));
    await frames(t);
    await tapKey(t, 'menuReply');
    await frames(t);
    expect(t.getSize(find.byKey(const Key('replyBar'))).width, closeTo(t.getSize(box).width, 1), reason: '#6: as wide as the box');
  });

  // ---------------------------------------------------------------- S13-4: friends
  testWidgets('#12: friends are found by part of a name; one letter asks for more; Add sends the request', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    s.users[s.idOf('Dareer')]!['display'] = 'Dareer Al-Ali';
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => FriendsScreen(account: a.account)));
    await frames(t);
    await t.enterText(find.byKey(const Key('addHandle')), 'a');
    await frames(t, 2);
    expect(find.textContaining('Type 2 letters'), findsOneWidget);
    await t.enterText(find.byKey(const Key('addHandle')), 'al-al'); // part of the display name, not of the @handle
    await t.pump(const Duration(milliseconds: 400));
    await frames(t);
    expect(find.byKey(const Key('found_Dareer')), findsOneWidget);
    await tapKey(t, 'foundAdd_Dareer');
    await frames(t);
    expect(find.byKey(const Key('foundAsked_Dareer')), findsOneWidget);
    expect(s.friendships, hasLength(1));
  });

  testWidgets('#9: the host lets me in → the room opens by itself (no "tap to join"); a plain invite still only shows the banner', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    final me = s.idOf('Sami'), d = s.idOf('Dareer');
    befriend(s, me, d);
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    String? opened;
    a.account.openRoom = (c) => opened = c;
    a.account.onHub(jsonEncode({'t': 'note', 'note': noteOf(s, me, d, 'invite', code: '111111').j}));
    await frames(t, 2);
    expect(opened, isNull, reason: 'an invite asks first');
    expect(find.byKey(const Key('noteBanner')), findsOneWidget);
    a.account.banner.value = null;
    a.account.onHub(jsonEncode({'t': 'note', 'note': noteOf(s, me, d, 'let_in', code: '222222').j}));
    await frames(t, 2);
    expect(opened, '222222');
    expect(a.account.letIn.value, 'Dareer');
    expect(find.byKey(const Key('noteBanner')), findsNothing, reason: 'no banner to tap: it already opened');
  });

  // ---------------------------------------------------------------- S13-5: Home, Settings, the update file
  testWidgets('#16 / #10: Settings has an × that closes it, and no test notification button', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    await tapKey(t, 'settings');
    await frames(t);
    expect(find.byKey(const Key('testPush'), skipOffstage: false), findsNothing);
    await tapKey(t, 'closeSettings');
    await frames(t);
    expect(find.byKey(const Key('closeSettings')), findsNothing);
  });

  testWidgets('#11: Home\'s footer: the version, Check for updates, What\'s new (the notes kept from the update)', (t) async {
    SharedPreferences.setMockInitialValues({'versionNotes': ['One board for everyone', 'Search friends'], 'versionNotesOf': appVersion});
    final p = await Prefs.load(), u = Updater(p, client: MockClient((_) async => http.Response('', 404)), installer: FakeInstaller());
    await t.pumpWidget(MaterialApp(localizationsDelegates: L.localizationsDelegates, home: Scaffold(body: HomeFooter(updater: u))));
    expect(find.text('v$appVersion'), findsOneWidget);
    await tapKey(t, 'whatsNew');
    await frames(t);
    expect(find.text('One board for everyone'), findsOneWidget); // [S14-4] a dot, not a '• ' in the text
  });

  test('#11: What\'s new with nothing kept: read once from this version\'s GitHub Release; nothing there: none', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await Prefs.load();
    final u = Updater(p, client: MockClient((r) async => r.url.path.endsWith('/releases/tags/v$appVersion-b$appBuild')
        ? http.Response(jsonEncode({'body': '- Fixed the chat\n- Faster'}), 200) : http.Response('', 404)), installer: FakeInstaller());
    expect(await u.whatsNew(), ['Fixed the chat', 'Faster']);
    expect(p.versionNotes, ['Fixed the chat', 'Faster'], reason: 'kept for next time');
    SharedPreferences.setMockInitialValues({});
    expect(await Updater(await Prefs.load(), client: MockClient((_) async => http.Response('', 404)), installer: FakeInstaller()).whatsNew(), isEmpty);
  });

  test('#15: the downloaded update file is deleted once the new version runs; the storage readout lists folders', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('s13'), cache = Directory('${dir.path}/cache')..createSync();
    File('${cache.path}/update.apk').writeAsBytesSync(List.filled(1024 * 1024, 1));
    final inst = _DirInstaller(cache.path), u = Updater(await Prefs.load(), installer: inst);
    final before = await u.storage();
    expect(before.firstWhere((r) => r.$1 == 'cache').$2, greaterThan(.9));
    await u.cleanup();
    expect(File('${cache.path}/update.apk').existsSync(), isFalse);
    await u.cleanup(); // [QA] twice: nothing to delete is fine
    dir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------- P1: history tools
  testWidgets('P1: History filters valid / invalid; a game hidden from my history shows under "Hidden" and comes back', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.games = [
      {'id': 'g1', 'winner': 'mafia', 'days': 2, 'valid': true, 'playedAt': 2, 'seat': 0, 'role': 'mafia', 'alive': true, 'players': 5},
      {'id': 'g2', 'winner': 'citizens', 'days': 3, 'valid': false, 'playedAt': 1, 'seat': 1, 'role': 'doctor', 'alive': true, 'players': 5},
    ];
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => HistoryScreen(account: a.account, prefs: a.prefs)));
    await frames(t);
    expect(find.byKey(const Key('game_g1')), findsOneWidget);
    expect(find.byKey(const Key('game_g2')), findsOneWidget);
    await tapKey(t, 'hist_valid');
    await frames(t);
    expect(find.byKey(const Key('game_g2')), findsNothing);
    await tapKey(t, 'hist_invalid');
    await frames(t);
    expect(find.byKey(const Key('game_g1')), findsNothing);
    a.prefs.hideGame('g2', true);
    await tapKey(t, 'hist_all');
    await frames(t);
    expect(find.byKey(const Key('game_g2')), findsNothing, reason: 'hidden');
    await tapKey(t, 'hist_hidden');
    await frames(t);
    expect(find.byKey(const Key('game_g2')), findsOneWidget);
    a.prefs.hideGame('g2', false);
    expect(a.prefs.hiddenGames, isEmpty);
  });
}

/// An installer whose cache folder is a real temp folder (for the update-file cleanup).
class _DirInstaller extends FakeInstaller {
  _DirInstaller(this.dir);
  final String dir;
  @override
  Future<String> cacheDir() async => dir;
}
