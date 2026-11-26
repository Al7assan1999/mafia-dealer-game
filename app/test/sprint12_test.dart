// [QA] Sprint 12: the full QA cycle's findings (docs/qa/qa-report.md Q1–Q10) and P3, against the fakes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/features/friends/friends_screen.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/app.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/l10n/app_localizations_en.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/features/room/room_screen.dart';
import 'package:mafia_dealer/features/old_history/old_players_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show frames, openRoom, roomMsg;
import 'sprint10_fixes_test.dart' show befriend, noteOf;

/// A session store as slow as Android's secure storage on a cold start.
class SlowTokens implements TokenStore {
  SlowTokens(this.t);
  final String? t;
  final gate = Completer<void>();
  @override
  Future<String?> read() async { await gate.future; return t; }
  @override
  Future<void> write(String? token) async {}
}

void main() {
  setUpAll(setUpHarness);

  testWidgets('S12-1: Old players (admin): the names found, marked Real (linked to an @username), Test, Not sure', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    s.admin = s.idOf('Sami');
    s.oldPlayers = [
      {'name': 'Dareer', 'games': 40, 'mark': 'unknown', 'link': null},
      {'name': 'Player 1', 'games': 3, 'mark': 'unknown', 'link': null},
    ];
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => OldPlayersScreen(account: a.account)));
    await frames(t);
    expect(find.text('in 40 games'), findsOneWidget);
    await tapKey(t, 'op_Player 1_test');
    await frames(t);
    expect(s.oldPlayers[1]['mark'], 'test');
    await tapKey(t, 'op_Dareer_real');
    await frames(t);
    await tapKey(t, 'op_Dareer_link');
    await t.enterText(find.byKey(const Key('opLinkField')), '@dareer');
    await tapKey(t, 'opLinkSave');
    await frames(t);
    expect(s.oldPlayers[0], {'name': 'Dareer', 'games': 40, 'mark': 'real', 'link': '@dareer'});
    expect(find.text('@dareer'), findsOneWidget);
  });

  testWidgets('S12-1: Profile shows Old players to the admin only', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    await tapKey(t, 'profile');
    await frames(t, 3);
    expect(find.byKey(const Key('oldPlayers'), skipOffstage: false), findsNothing);
  });

  testWidgets('S12-2: Join waits for 6 digits; a code with no room is answered on the Online screen; an open one opens', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.openRooms.add('654321');
    await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    await tapKey(t, 'online');
    await frames(t);
    FilledButton join() => t.widget<FilledButton>(find.byKey(const Key('joinRoom')));
    expect(join().onPressed, isNull);
    await t.enterText(find.byKey(const Key('roomCode')), '12345');
    await frames(t, 2);
    expect(join().onPressed, isNull);
    expect(find.text('Type all 6 digits'), findsOneWidget);
    await t.enterText(find.byKey(const Key('roomCode')), '123456');
    await frames(t, 2);
    await tapKey(t, 'joinRoom');
    await frames(t);
    expect(find.byType(RoomScreen), findsNothing, reason: 'no empty room screen for a code that has no room');
    expect(find.text('No room with that code'), findsOneWidget);
    await t.enterText(find.byKey(const Key('roomCode')), '654321');
    await frames(t, 2);
    expect(find.text('No room with that code'), findsNothing, reason: 'typing clears it');
    await tapKey(t, 'joinRoom');
    await frames(t);
    expect(find.byType(RoomScreen), findsOneWidget);
    ActiveRoom.navigatorKey.currentState!.pop();
    await t.pumpWidget(const SizedBox());
  });

  test('S12-3: no counted English text without a plural (1 vote, not 1 votes)', () {
    final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, Object?>;
    final bad = <String>[];
    for (final e in en.entries.where((e) => e.key.startsWith('@') && e.value is Map)) {
      final key = e.key.substring(1), text = en[key];
      if (text is! String || text.contains('plural,')) continue;
      final ints = ((e.value as Map)['placeholders'] as Map? ?? const {}).entries.where((p) => (p.value as Map?)?['type'] == 'int').map((p) => p.key);
      for (final n in ints) {
        // "{n} players", "{n} votes": a count followed by a plural noun must be an ICU plural
        if (RegExp('(^|[^/])\\{$n\\} [a-z]{2,}s\\b').hasMatch(text)) bad.add('$key: $text');
      }
    }
    expect(bad, isEmpty);
    expect(LEn().votesN(1), '1 vote');
    expect(LEn().roomPlayers(1, 'Lobby'), '1 player · Lobby');
    expect(LEn().needN(1), 'Needs 1 game');
  });

  testWidgets('S12-4: a cold start shows the saved account at once, while the session is still being read', (t) async {
    t.view.physicalSize = const Size(393, 851);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = FakeServer(), tok = s.user('Sami');
    SharedPreferences.setMockInitialValues({'lang': 'en', 'guideSeen': true, 'me': jsonEncode(s.users[s.idOf('Sami')])});
    final tokens = SlowTokens(tok), l = await launchWith(t, s, tokens);
    expect(l.signedIn, isTrue, reason: 'from the phone\'s memory, before the session read finishes');
    expect(find.byKey(const Key('signIn')), findsNothing);
    expect(find.byKey(const Key('profile')), findsOneWidget);
    tokens.gate.complete();
    await frames(t);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('S12-4: no saved session after all: the cached account goes', (t) async {
    t.view.physicalSize = const Size(393, 851);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = FakeServer();
    s.user('Sami');
    SharedPreferences.setMockInitialValues({'lang': 'en', 'guideSeen': true, 'me': jsonEncode(s.users[s.idOf('Sami')])});
    final tokens = SlowTokens(null);
    final a = await launchWith(t, s, tokens);
    tokens.gate.complete();
    await frames(t);
    expect(a.signedIn, isFalse);
    expect(find.byKey(const Key('signIn')), findsOneWidget);
  });

  testWidgets('S12-5: the banner sits below the top icons (the bell stays tappable) and swipes away', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    final me = s.idOf('Sami'), d = s.idOf('Dareer');
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    a.account.banner.value = noteOf(s, me, d, 'friend_request');
    await frames(t, 3);
    final banner = t.getRect(find.byKey(const Key('noteBanner'))), bell = t.getRect(find.byKey(const Key('bell')));
    expect(banner.top, greaterThan(bell.bottom - 1), reason: 'below the bell, not over it');
    await t.fling(find.byKey(const Key('noteBanner')), const Offset(0, -150), 1000);
    await frames(t, 4);
    expect(find.byKey(const Key('noteBanner')), findsNothing);
  });

  testWidgets('S12-6: a closed room shows its message and Home only; the friends tab is there (it may float over the code card, 1.1.1)', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    await frames(t);
    final code = t.getRect(find.byKey(const Key('code'))).bottom;
    final tab = find.byKey(const Key('friendsTab'));
    // [1.1.1 hotfix, his note] the side tabs float over the content now (the room code too) and drag out of the way
    expect(code, greaterThan(0));
    expect(tab, findsOneWidget);
    r.last.push({'t': 'bye', 'why': 'closed'});
    await frames(t);
    for (final k in ['chat', 'narrate', 'leave', 'friendsTab']) { expect(find.byKey(Key(k)), findsNothing, reason: k); }
  });

  testWidgets('S12-6: a tap on a chat message opens its menu; Send is off while the box is empty', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    r.last.push({'t': 'chatAll', 'msgs': [{'id': 1, 'from': 3, 'to': -1, 'text': 'Who is lying here?', 'at': DateTime.now().millisecondsSinceEpoch}]});
    await frames(t);
    await tapKey(t, 'chat');
    await frames(t);
    expect(t.widget<IconButton>(find.byKey(const Key('chatSend'))).onPressed, isNull);
    await t.enterText(find.byKey(const Key('chatText')), 'hi');
    await frames(t, 2);
    expect(t.widget<IconButton>(find.byKey(const Key('chatSend'))).onPressed, isNotNull);
    await t.tap(find.byKey(const Key('msg_1')));
    await frames(t);
    expect(find.byKey(const Key('menuReply')), findsOneWidget);
  });

  testWidgets('S12-6: TalkBack can open the role card (a long-press action), and close it again', (t) async {
    final sem = t.ensureSemantics();
    await launch(t, stored: {'guideSeen': true});
    await setUpGame(t, ['Dareer', 'Halawy', 'Farouq', 'Sami', 'Hokan']);
    await tapKey(t, 'open');
    await frames(t);
    final node = t.getSemantics(find.byKey(const Key('roleCard')));
    expect(node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
    longPress(t, node.id);
    await frames(t, 2);
    expect(find.byKey(const Key('roleName')), findsOneWidget);
    longPress(t, t.getSemantics(find.byKey(const Key('roleCard'))).id);
    await frames(t, 2);
    expect(find.byKey(const Key('roleName')), findsNothing);
    sem.dispose();
  });

  testWidgets('P3: a friend\'s room shows how many are in it (drawer and Friends)', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    befriend(s, s.idOf('Sami'), s.idOf('Dareer'));
    s.users[s.idOf('Dareer')]!..['st'] = 'lobby'..['op'] = true;
    s.users[s.idOf('Dareer')]!..['st'] = 'game'..['n'] = 5;
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    await t.runAsync(a.account.loadFriends);
    await frames(t);
    expect(friendStatus(LEn(), a.account.friends.first), 'In a game · 5 players');
    await tapKey(t, 'friendsTab');
    await frames(t);
    expect(find.text('In a game · 5 players'), findsOneWidget);
  });

}

/// What TalkBack sends for "double-tap and hold".
void longPress(WidgetTester t, int id) =>
    t.binding.performSemanticsAction(SemanticsActionEvent(type: SemanticsAction.longPress, nodeId: id, viewId: t.view.viewId));

/// The app as main() starts it: restore() runs in the background, the first frame doesn't wait for the session.
Future<Account> launchWith(WidgetTester t, FakeServer s, TokenStore tokens) async {
  final prefs = await Prefs.load(), audio = Audio(prefs), account = Account(s.api(), tokens, prefs, google: FakeGoogle(), live: false);
  unawaited(account.restore());
  await t.pumpWidget(App(prefs: prefs, audio: audio, account: account));
  await frames(t, 2);
  return account;
}
