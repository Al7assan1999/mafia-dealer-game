// [QA] Sprint 11: his two-phone playtest notes R1–R7 against the fakes (the real push, the vibration and the old relay
// binding are checked on the emulator and in the server tests).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/account.dart';
import 'package:mafia_dealer/account_screens.dart';
import 'package:mafia_dealer/online.dart';
import 'package:mafia_dealer/stats.dart';
import 'package:mafia_dealer/update.dart' show pickApk;

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show frames, member, openRoom, roomMsg;
import 'sprint10_fixes_test.dart' show befriend, roomShell;
import 'sprint7_test.dart' show FakePush;

void main() {
  setUpAll(setUpHarness);

  testWidgets('R1: minimized, the chat button sits under the friends tab, not on the red bar', (t) async {
    await roomShell(t, (s, me) { s.user('Dareer'); befriend(s, me, s.idOf('Dareer')); });
    await tapKey(t, 'minimize');
    await frames(t);
    expect(find.descendant(of: find.byKey(const Key('roomBar')), matching: find.byKey(const Key('barChat'))), findsNothing);
    final tab = t.getRect(find.byKey(const Key('friendsTab'))), chat = t.getRect(find.byKey(const Key('barChat')));
    expect(chat.top, greaterThan(tab.bottom - 1), reason: 'under the tab');
    expect(chat.right, closeTo(tab.right, 1), reason: 'on the same edge');
    await tapKey(t, 'roomBar'); // back in the room, so the teardown's leave closes it
    await frames(t);
  });

  testWidgets('R3: a friend with no games gets a whole profile: status, Friends, empty tiles; a stranger gets Add friend', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    s.user('Hokan');
    befriend(s, s.idOf('Sami'), s.idOf('Dareer'));
    s.users[s.idOf('Dareer')]!['on'] = true;
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    await t.runAsync(a.account.loadFriends);
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => FriendsScreen(account: a.account)));
    await frames(t);
    await t.tap(find.byKey(const Key('friendStats_Dareer')));
    await frames(t);
    expect(find.byKey(const Key('noGamesYet')), findsOneWidget);
    expect(find.byKey(const Key('profileName')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('profileStatus')), matching: find.text('Online')), findsOneWidget);
    expect(find.text('Friends'), findsWidgets);
    expect(find.text('–'), findsNWidgets(4), reason: 'the four stat tiles, empty');
    expect(find.byKey(const Key('profileAdd')), findsNothing);

    final h = s.users[s.idOf('Hokan')]!;
    ActiveRoom.navigatorKey.currentState!..pop()..pop();
    await frames(t);
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => PlayerScreen(account: a.account, playerKey: 'u:${h['id']}',
        person: Person({'id': h['id'], 'handle': h['handle'], 'display': h['display'], 'avatar': {'preset': 1}, 'fav': '', 'rel': 'none'}))));
    await frames(t);
    expect(find.byKey(const Key('profileStatus')), findsNothing, reason: 'a stranger\'s presence is private');
    await tapKey(t, 'profileAdd');
    await frames(t);
    expect(find.byKey(const Key('profileRequested')), findsOneWidget);
  });

  testWidgets('R5: the message follows the finger; a short drag springs back without replying, a long one replies', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    r.last.push({'t': 'chatAll', 'msgs': [{'id': 1, 'from': 3, 'to': -1, 'text': 'Who is lying here?', 'at': DateTime.now().millisecondsSinceEpoch}]});
    await frames(t);
    await tapKey(t, 'chat');
    await frames(t);
    final x0 = t.getTopLeft(find.byKey(const Key('msg_1'))).dx, c = t.getCenter(find.byKey(const Key('row_1')));
    final g = await t.startGesture(c);
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(20, 0));
    await t.pump();
    expect(t.getTopLeft(find.byKey(const Key('msg_1'))).dx, greaterThan(x0 + 15), reason: 'the bubble moves with the finger');
    await g.up();
    await frames(t, 4);
    expect(t.getTopLeft(find.byKey(const Key('msg_1'))).dx, closeTo(x0, .5), reason: 'springs back');
    expect(find.textContaining('Who is lying here?'), findsOneWidget, reason: '40 px: no reply');
    final g2 = await t.startGesture(c);
    for (var i = 0; i < 6; i++) { await g2.moveBy(const Offset(-20, 0)); }
    await t.pump();
    expect(find.byIcon(Icons.reply), findsOneWidget, reason: 'the reply arrow behind it');
    await g2.up();
    await frames(t, 4);
    expect(find.textContaining('Who is lying here?'), findsNWidgets(2), reason: 'the message and the reply bar');
  });

  testWidgets('R6: with the app open the test push is caught and the row says it arrived; nothing in 15 s says so', (t) async {
    final s = FakeServer(), tok = s.user('Sami'), push = FakePush();
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true, 'pushAsked': true});
    a.account.push = push;
    await frames(t);
    await tapKey(t, 'settings');
    await frames(t);
    await t.ensureVisible(find.byKey(const Key('testPush')));
    await t.tap(find.byKey(const Key('testPush')));
    await frames(t);
    expect(t.widget<Text>(find.byKey(const Key('testPushResult'))).data, contains('Waiting'));
    push.inApp.add({'kind': 'test'});
    await frames(t);
    expect(t.widget<Text>(find.byKey(const Key('testPushResult'))).data, contains('Arrived on this phone'));
    await t.tap(find.byKey(const Key('testPush')));
    await t.pump(const Duration(seconds: 16));
    expect(t.widget<Text>(find.byKey(const Key('testPushResult'))).data, contains('Nothing arrived'));
  });

  testWidgets('R7: a player buzzes the host from the lobby (muted at the limit); the host pings; arriving ones flash', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1, host: false, members: [member(0), member(1, host: true), member(2), member(3)]));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    await frames(t);
    await tapKey(t, 'buzzHost');
    await frames(t);
    expect(r.last.msgs.last, {'t': 'buzz'});
    expect(find.text('Buzz sent'), findsOneWidget);
    r.last.push(roomMsg(2, host: false, members: [{...member(0), 'muted': true}, member(1, host: true), member(2), member(3)]));
    await frames(t);
    expect(find.byKey(const Key('buzzHost')), findsNothing);
    expect(find.byKey(const Key('buzzMuted')), findsOneWidget);
    final flashes = buzzFlash.value;
    r.last.push({'t': 'ping'});
    await frames(t);
    expect(find.text('The host pinged you!'), findsOneWidget);
    expect(buzzFlash.value, flashes + 1);
  });

  testWidgets('R7: the host has Ping everyone by the player list and is buzzed with a name', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    await frames(t);
    expect(find.byKey(const Key('buzzHost')), findsNothing);
    await tapKey(t, 'pingAll');
    expect(r.last.msgs.last, {'t': 'ping'});
    r.last.push({'t': 'buzz', 'from': 'u2'});
    await frames(t);
    expect(find.text('P3 buzzed you'), findsOneWidget);
  });

  test('R9: the updater takes the APK for the phone processor, then a one-for-all APK, then the first', () {
    Map<String, Object?> a(String n) => {'name': n, 'browser_download_url': 'https://x/$n'};
    final split = [a('M-0.4.0-b100003-arm64-v8a.apk'), a('M-0.4.0-b100003-armeabi-v7a.apk'), a('M-0.4.0-b100003-x86_64.apk')];
    expect(pickApk(split, 'arm64-v8a')!['name'], 'M-0.4.0-b100003-arm64-v8a.apk');
    expect(pickApk(split, 'armeabi-v7a')!['name'], 'M-0.4.0-b100003-armeabi-v7a.apk');
    expect(pickApk(split, 'x86_64')!['name'], 'M-0.4.0-b100003-x86_64.apk');
    expect(pickApk(split, '')!['name'], 'M-0.4.0-b100003-arm64-v8a.apk', reason: 'unknown processor: the first (arm64)');
    expect(pickApk([a('M-0.3.0-b100002.apk'), a('notes.txt')], 'arm64-v8a')!['name'], 'M-0.3.0-b100002.apk', reason: 'an older release');
    expect(pickApk([a('notes.txt')], 'arm64-v8a'), isNull);
  });
}
