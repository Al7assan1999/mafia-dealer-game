// [QA] Sprint 15: his adjustments (Home's 0.4.6 top row, Settings ×: in sprint14_test), the old recap card, the old
// history search and filters, the round line online. Break attempts per AC of docs/sprint-15-prd.md.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/features/guide/guide_screen.dart';
import 'package:mafia_dealer/features/history/history_screen.dart';
import 'package:mafia_dealer/features/offline/recap_card.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show frames, openRoom, roomMsg, view;
import 'sprint10_fixes_test.dart' show roomShell;

void main() {
  setUpAll(setUpHarness);

  testWidgets('S15-1: Home\'s top row as 0.4.6: @handle, friends, bell, gear; no language or look boxes', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await launch(t, server: s, tokens: MemoryTokens()..t = tok);
    await frames(t, 3);
    for (final k in ['profile', 'friends', 'bell', 'settings']) { expect(find.byKey(Key(k)), findsOneWidget, reason: k); }
    expect(find.byKey(const Key('homeLang')), findsNothing);
    expect(find.byKey(const Key('homeTheme')), findsNothing);
    await tapKey(t, 'friends');
    await frames(t, 3);
    expect(find.byKey(const Key('tabSent'), skipOffstage: false), findsOneWidget, reason: 'the friends icon opens Friends');
  });

  testWidgets('S15-4: the recap card: who won, the player of the game, every role in the grid, the dead crossed out', (t) async {
    await t.pumpWidget(MaterialApp(localizationsDelegates: L.localizationsDelegates, home: Scaffold(body: SingleChildScrollView(child: RecapCard(mafia: false, days: 3,
        players: const [(name: 'Dareer', role: Role.mafia, alive: false), (name: 'Sami', role: Role.doctor, alive: true), (name: 'Hokan', role: Role.citizen, alive: true)],
        best: (name: 'Sami', why: 'Saved 2', role: Role.doctor), lines: const [(night: true, text: 'Night 1: nobody died'), (night: false, text: 'Day 1: Dareer out')])))));
    await frames(t, 2);
    expect(find.text('Citizens win'), findsOneWidget);
    expect(find.byKey(const Key('mvpName')), findsOneWidget);
    expect(find.text('Dareer'), findsOneWidget);
    final dead = t.widget<Text>(find.text('Dareer'));
    expect(dead.style?.decoration, TextDecoration.lineThrough);
    expect(find.text('Day 1: Dareer out'), findsOneWidget);
    // [QA] S15 Arabic pass: the date came in Arabic-Indic digits (٢٤ … ٢٠٢٦) next to 0-9 everywhere else
    await t.pumpWidget(MaterialApp(locale: const Locale('ar'), supportedLocales: L.supportedLocales, localizationsDelegates: L.localizationsDelegates,
        home: Scaffold(body: SingleChildScrollView(child: RecapCard(mafia: true, days: 1, players: const [(name: 'Dareer', role: Role.mafia, alive: true)],
            best: null, lines: const [])))));
    await frames(t, 2);
    final now = DateTime.now();
    expect(find.textContaining(RegExp('^${now.day} .+ ${now.year}\$')), findsOneWidget);
  });

  testWidgets('S15-5: History: search by a player\'s name, the Winner filter, the count; a name nobody had: none', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.games = [
      {'id': 'g1', 'winner': 'mafia', 'days': 2, 'valid': true, 'playedAt': 2, 'seat': 0, 'role': 'mafia', 'alive': true, 'players': 5, 'names': ['Sami', 'Dareer', 'Hokan', 'Farouq', 'Halawy']},
      {'id': 'g2', 'winner': 'citizens', 'days': 3, 'valid': true, 'playedAt': 1, 'seat': 1, 'role': 'doctor', 'alive': true, 'players': 5, 'names': ['Sami', 'Khaddour', 'Hokan', 'Mona', 'Rami']},
      {'id': 'g3', 'winner': 'citizens', 'days': 1, 'valid': true, 'playedAt': 0, 'seat': 1, 'role': 'citizen', 'alive': true, 'players': 4}, // an older server: no names
    ];
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => HistoryScreen(account: a.account, prefs: a.prefs)));
    await frames(t);
    expect(find.text('3 GAMES'), findsOneWidget);
    await t.enterText(find.byKey(const Key('histSearch')), 'dar');
    await frames(t);
    expect(find.byKey(const Key('game_g1')), findsOneWidget);
    expect(find.byKey(const Key('game_g2')), findsNothing);
    expect(find.text('1 GAME'), findsOneWidget);
    await t.enterText(find.byKey(const Key('histSearch')), 'nobody here');
    await frames(t);
    expect(find.text('0 GAMES'), findsOneWidget);
    await t.enterText(find.byKey(const Key('histSearch')), '');
    await tapKey(t, 'win_citizens');
    await frames(t);
    expect(find.byKey(const Key('game_g1')), findsNothing);
    expect(find.byKey(const Key('game_g2')), findsOneWidget);
    expect(find.byKey(const Key('game_g3')), findsOneWidget, reason: 'a game without names still shows when nothing is searched');
  });

  testWidgets('S15-6: online game screens show "Round · alive" too', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push(view(2, 'night', extra: {'day': 2, 'roster': [for (var i = 0; i < 4; i++) {'name': 'P${i + 1}', 'alive': i != 3}]}));
    await frames(t);
    expect(find.text('Round 2 · 3/4 alive'), findsOneWidget);
  });

  // [QA] S15 emulator pass: TalkBack found neither the red room bar (the page above it hid it) nor the chat's Send
  testWidgets('the room bar and the chat Send button have labels a screen reader finds', (t) async {
    final h = t.ensureSemantics();
    await roomShell(t, (s, me) {});
    await tapKey(t, 'chat');
    await frames(t);
    expect(find.byTooltip('Send'), findsOneWidget);
    await t.binding.handlePopRoute();
    await frames(t);
    await tapKey(t, 'minimize');
    await frames(t);
    final bar = t.getSemantics(find.byKey(const Key('roomBar')));
    expect(bar.getSemanticsData().label, contains('Back to room'));
    expect(bar.rect.height, lessThan(120), reason: 'its own node, not the whole screen (the emulator showed [0,0][1080,2337])');
    await tapKey(t, 'roomBar'); // back in the room, so the teardown's leave closes it
    await frames(t);
    h.dispose();
  });

  // [QA] S15 Arabic pass: the back chevron pointed left on the right edge (the icon mirrors itself and the code mirrored it again)
  testWidgets('Arabic: the back button and "Back to room" use the self-mirroring icons, not a second swap', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await launch(t, server: s, tokens: MemoryTokens()..t = tok, lang: 'ar');
    await frames(t);
    await tapKey(t, 'friends');
    await frames(t);
    expect(Directionality.of(t.element(find.byType(BackButtonIcon).first)), TextDirection.rtl);
    expect(find.byIcon(Icons.chevron_left), findsWidgets); // drawn pointing right in Arabic
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  // [BA] S15-5 old-look compare: the old guide had table rules and a suggested setup; its numbers follow the engine
  testWidgets('How to Play has the table rules and a suggested setup that matches what the setup screen suggests', (t) async {
    expect([for (final n in [4, 5, 6, 9, 10, 13]) recMafia(n)], [1, 1, 2, 2, 3, 3]); // "4-5: 1 · 6-9: 2 · 10-13: 3"
    await t.pumpWidget(MaterialApp(localizationsDelegates: L.localizationsDelegates, home: const GuideScreen()));
    await frames(t, 2);
    expect(find.text('TABLE RULES'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('6-9 players: 2 Mafia'), 300);
    expect(find.text('SUGGESTED SETUP'), findsOneWidget);
  });
}
