// 1.1.1 hotfixes (his list of 2026-11-26): the Sniper's night 1, Ghost view, out players see the votes, quiet room
// notices, no bar for another player's closed app, the role card again mid-game, the friends box searches, Add from a player's page;
// (his second note) a taken username is an alert; the room's side tabs float over the content and drag up and down.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/features/account/profile_screen.dart';
import 'package:mafia_dealer/features/friends/friends_screen.dart';
import 'package:mafia_dealer/features/offline/rules_card.dart';
import 'package:mafia_dealer/features/stats/player_screen.dart';
import 'package:mafia_dealer/core/ui.dart' show noir;
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_engine/mafia_engine.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'hotfix_room_test.dart' show recap;
import 'online_test.dart' show frames, member, openRoom, roomMsg, view;

void main() {
  setUpAll(setUpHarness);

  testWidgets('#1 the Sniper on night 1: "No shot tonight", not "Who do you suspect?"', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'night', ph: 'night', extra: {'role': 'sniper', 'night': {'key': 'citizen', 'opts': [for (var i = 0; i < 4; i++) {'seat': i, 'disabled': i == 0}], 'skip': null}}));
    await frames(t);
    expect(find.text('No shot tonight'), findsOneWidget);
    expect(find.text('Who do you suspect?'), findsNothing);
    expect(find.textContaining('nothing happens to them'), findsOneWidget);
  });

  testWidgets('#2 Ghost view is back in the rules (Online), and shows as a chip', (t) async {
    Rules? got;
    await t.pumpWidget(MaterialApp(theme: noir(), localizationsDelegates: L.localizationsDelegates, supportedLocales: L.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: StatefulBuilder(builder: (c, set) =>
            RulesEditor(rules: got ?? defaultRules, onChanged: (x) => set(() => got = x)))))));
    expect(find.text('Ghost view'), findsNothing, reason: 'off by default, as the old app');
    await t.tap(find.byKey(const Key('rulesToggle')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Ghost view'), 200);
    await t.tap(find.text('Ghost view'));
    await t.pumpAndSettle();
    expect(got?.ghost, isTrue);
    await t.tap(find.byKey(const Key('rulesToggle')));
    await t.pumpAndSettle();
    expect(find.text('Ghost view'), findsOneWidget, reason: 'the chip');
  });

  testWidgets('#3 out (the host too): the vote as it comes in, with Ghost view the roles', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'vote', ph: 'dead', extra: {'alive': false, 'progress': {'done': 1, 'total': 3}, 'roles': ['doctor', 'mafia', 'citizen', 'citizen'],
      'board': [{'seat': 1, 'v': 2}, {'seat': 2, 'v': null}, {'seat': 3, 'v': 'none'}]}));
    await frames(t);
    expect(find.text('You are out'), findsOneWidget);
    expect(find.byKey(const Key('voteBoard')), findsOneWidget);
    expect(find.text('VOTES SO FAR'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('voteBoard')), matching: find.text('P3')), findsWidgets);
    expect(find.text('Mafia'), findsWidgets, reason: 'Ghost view: every role');
  });

  testWidgets('#4 a buzz is a quiet line under the title, not a toast over the buttons; ten buzzes are one line', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    await frames(t);
    for (var i = 0; i < 10; i++) { r.last.push({'t': 'buzz', 'from': 'u2'}); }
    await frames(t);
    expect(find.byKey(const Key('roomNote')), findsOneWidget);
    expect(find.text('P3 buzzed you'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await t.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('roomNote')), findsNothing, reason: 'gone after 2.5 s');
  });

  testWidgets('#6 another player closing the app: no bar, a quiet line by the count, a mark on the day roster', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    final ms = [member(0, host: true, seat: 0), member(1, seat: 1), member(2, seat: 2, online: false), member(3, seat: 3)];
    r.last.push(roomMsg(1, status: 'game', members: ms));
    r.last.push(view(1, 'night', ph: 'nightDone', extra: {'progress': {'done': 2, 'total': 4}}));
    await frames(t);
    expect(find.byKey(const Key('connBar')), findsNothing);
    expect(find.text('App closed: P3'), findsOneWidget);
    // [Quin Q6] the host on his own pick screen: who, next to Continue anyway
    r.last.push(view(2, 'night', ph: 'night', extra: {'progress': {'done': 2, 'total': 4}, 'night': {'key': 'doctor', 'opts': [for (var i = 0; i < 4; i++) {'seat': i, 'disabled': false}], 'skip': null}}));
    await frames(t);
    expect(find.byKey(const Key('awayHost')), findsOneWidget);
    expect(find.byKey(const Key('continue')), findsOneWidget);
    r.last.push(view(3, 'day', extra: {'timer': {'left': 180}}));
    await frames(t);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('#9 the role card again mid-game: hold to see, then Got it', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'day', extra: {'timer': {'left': 180}, 'role': 'mafia', 'mates': [2]}));
    await frames(t);
    await tapKey(t, 'myRole');
    await frames(t);
    final card = find.byKey(const Key('roleCard'));
    expect(card, findsOneWidget);
    final g = await t.startGesture(t.getCenter(card));
    await t.pump();
    expect(find.byKey(const Key('roleName')), findsOneWidget);
    expect(find.textContaining('P3'), findsWidgets, reason: 'the other Mafia');
    await g.up();
    await t.pump();
    await tapKey(t, 'memorized');
    await frames(t);
    expect(find.byKey(const Key('roleCard')), findsNothing);
    expect(find.byKey(const Key('clock')), findsOneWidget, reason: 'back on the day');
    r.last.push(view(2, 'end', ph: 'end', extra: {'winner': 'citizens', 'recap': recap, 'roles': recap['roles']}));
    await frames(t);
    expect(find.byKey(const Key('myRole')), findsNothing);
  });

  testWidgets('[Quin Q4] the role page closes by itself when the night comes (and on a new deal or a closed room)', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'day', extra: {'timer': {'left': 180}}));
    await frames(t);
    await tapKey(t, 'myRole');
    await frames(t);
    expect(find.byKey(const Key('roleCard')), findsOneWidget);
    r.last.push(view(2, 'night', ph: 'night', extra: {'night': {'key': 'doctor', 'opts': [for (var i = 0; i < 4; i++) {'seat': i, 'disabled': false}], 'skip': null}}));
    await frames(t, 8);
    expect(find.byKey(const Key('roleCard')), findsNothing);
    expect(find.byKey(const Key('confirm')), findsOneWidget, reason: 'the night pick is on top');
  });

  testWidgets('[Quin Q3] a buzz during a vote floats over the screen: the options never move', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'vote', ph: 'vote', extra: {'voteOpts': [for (var i = 0; i < 4; i++) {'seat': i, 'disabled': i == 0}], 'voteId': 1}));
    await frames(t);
    final y = t.getTopLeft(find.byKey(const Key('opt_2'))).dy;
    r.last.push({'t': 'buzz', 'from': 'u2'});
    await frames(t);
    expect(find.byKey(const Key('roomNote')), findsOneWidget);
    expect(t.getTopLeft(find.byKey(const Key('opt_2'))).dy, y);
  });

  testWidgets('#10 a player from a shared game who is not a friend: Add friend on their page', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    final d = s.users[s.idOf('Dareer')]!;
    s.playerAnswer = {'key': 'u:${d['id']}', 'name': 'Dareer', 'userId': d['id'], 'games': 1, 'wins': 1, 'best': 'citizen',
      'roles': {'mafia': [0, 0], 'doctor': [0, 0], 'detective': [0, 0], 'citizen': [1, 1]}, 'mafia': [0, 0], 'side': [1, 1], 'nemesis': null, 'partner': null,
      'moments': {'saves': 0, 'caught': 0, 'killed': 0, 'out': 0}, 'form': [true],
      'card': {'id': d['id'], 'handle': d['handle'], 'display': 'Dareer', 'avatar': {'preset': 1}, 'fav': '', 'rel': 'none'}};
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => PlayerScreen(account: a.account, playerKey: 'u:${d['id']}')));
    await frames(t);
    await tapKey(t, 'profileAdd');
    await frames(t);
    expect(find.byKey(const Key('profileRequested')), findsOneWidget);
    expect(s.friendships, hasLength(1));
  });

  testWidgets('#8 the button by the friends box is Search: it never sends a request for the typed text', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Hokan');
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => FriendsScreen(account: a.account)));
    await frames(t);
    expect(find.byKey(const Key('addFriend')), findsNothing);
    await t.enterText(find.byKey(const Key('addHandle')), 'hokan');
    await tapKey(t, 'searchFriend');
    await t.pump(const Duration(milliseconds: 400));
    await frames(t);
    expect(s.friendships, isEmpty);
    expect(find.byKey(const Key('found_Hokan')), findsOneWidget);
  });

  testWidgets('a username someone else has: an alert, not a toast', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => ProfileScreen(account: a.account)));
    await frames(t);
    await t.enterText(find.byKey(const Key('handle')), 'DAREER');
    await t.tap(find.byKey(const Key('saveProfile')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await frames(t);
    expect(find.byKey(const Key('handleTaken')), findsOneWidget);
    expect(find.text('@DAREER belongs to another player. Pick a different username.'), findsOneWidget);
    await t.tap(find.text('OK'));
    await frames(t);
    expect(a.account.handle, 'Sami', reason: 'nothing changed');
  });

  testWidgets('the side tabs float over the room and drag up and down, in the lobby and in a game', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'day', extra: {'timer': {'left': 180}}));
    await frames(t);
    final chat = find.byKey(const Key('chat'));
    final y0 = t.getTopLeft(chat).dy;
    await t.drag(chat, const Offset(0, 250));
    await frames(t);
    expect(t.getTopLeft(chat).dy, greaterThan(y0 + 150), reason: 'the chat tab alone drags too');
    expect(y0, lessThan(56 + 160.0), reason: 'starts over the content, no longer held under the header (160 dp)');
    await t.drag(chat, const Offset(0, -2000));
    await frames(t);
    expect(t.getTopLeft(chat).dy, y0, reason: 'and back up to the top');
  });
}
