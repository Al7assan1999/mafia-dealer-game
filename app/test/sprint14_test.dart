// [QA] Sprint 14: the old app's look. Break attempts for each AC of docs/sprint-14-prd.md (the visual match itself is in
// the emulator shots of docs/sprint-14-report.md).
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/features/home/best_line.dart';
import 'package:mafia_dealer/features/update/updater.dart';
import 'package:mafia_dealer/features/update/whats_new.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show frames, openRoom, roomMsg, view;
import 'sprint8_test.dart' show FakeInstaller, row, signedIn, statsOf;

Map<String, Object?> rel(String v, int b, String day, List<String> pts) => {'tag_name': 'v$v-b$b', 'published_at': '${day}T10:00:00Z', 'body': pts.map((p) => '- $p').join('\n')};

void main() {
  setUpAll(setUpHarness);

  // ---------------------------------------------------------------- S14-1 / S14-2: the room
  testWidgets('S14-1/2: the chat is a side tab in the lobby and in the game, never in the top bar; the Home icon stays', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    await frames(t);
    expect(find.byKey(const Key('chat')), findsOneWidget, reason: 'the lobby');
    expect(find.descendant(of: find.byType(AppBar), matching: find.byKey(const Key('chat'))), findsNothing, reason: 'not up top (his #1)');
    expect(find.descendant(of: find.byType(AppBar), matching: find.byKey(const Key('minimize'))), findsOneWidget, reason: 'the Home icon (his #2)');
    r.last.push(view(2, 'night'));
    await frames(t);
    expect(find.byKey(const Key('chat')), findsOneWidget, reason: 'and during the game');
    expect(find.byKey(const Key('friendsTab')), findsNothing, reason: 'no friends drawer inside a game (S9-2)');
  });

  // ---------------------------------------------------------------- S14-3: Home
  testWidgets('S14-3: Home as the old app: three tiles, the best player (a tap opens Player Stats), the version row', (t) async {
    BestLine.read = false;
    final s = FakeServer()..statsAnswer = statsOf([row('u:1', 'Dareer', w: 5, g: 6, rank: 1)]);
    await signedIn(t, s);
    await frames(t, 4);
    for (final k in ['history', 'stats', 'howToPlay', 'bell', 'homeLang', 'homeTheme', 'settings']) { // the version row needs an updater (sprint13_test checks it)
      expect(find.byKey(Key(k), skipOffstage: false), findsOneWidget, reason: k);
    }
    expect(find.byKey(const Key('friends')), findsNothing, reason: 'friends are in the side drawer, as the old app');
    await t.ensureVisible(find.byKey(const Key('bestLine')));
    expect(find.text('Best player: Dareer · 83%'), findsOneWidget);
    await tapKey(t, 'bestLine');
    await frames(t, 4);
    expect(find.text('Dareer'), findsWidgets, reason: 'Player Stats opened');
  });

  testWidgets('S14-3: a guest has the three tiles too, no best player; Player Stats asks to sign in; the flag switches the language', (t) async {
    final a = await launch(t);
    await frames(t, 2);
    expect(find.byKey(const Key('bestLine')), findsNothing);
    await tapKey(t, 'homeLang');
    await frames(t, 2);
    expect(a.prefs.lang, 'ar');
    await tapKey(t, 'homeTheme');
    await frames(t, 2);
    expect(a.prefs.theme, 'neon');
  });

  // ---------------------------------------------------------------- S14-4: What's new
  test('S14-4: the release list comes with the check (server), else the server alone, else GitHub; newest first', () async {
    SharedPreferences.setMockInitialValues({});
    final asked = <String>[];
    var serverHistory = true;
    final u = Updater(await Prefs.load(), installer: FakeInstaller(), client: MockClient((req) async {
      asked.add(req.url.toString());
      if (req.url.path == '/v1/app/latest') {
        return http.Response(jsonEncode({'tag_name': 'v0.4.7-b100011', 'assets': [], if (serverHistory) 'history': [rel('0.4.7', 100011, '2026-11-25', ['A', 'B']), rel('0.4.6', 100010, '2026-11-24', ['C'])]}), 200);
      }
      return http.Response(jsonEncode([rel('0.4.5', 100008, '2026-11-24', ['D'])]), 200);
    }));
    final r = await u.releases();
    expect([for (final x in r) x.version], ['0.4.7', '0.4.6']);
    expect(r.first.notes, ['A', 'B']);
    expect(r.first.date?.year, 2026);
    expect(asked.where((x) => x.contains('github')), isEmpty, reason: 'the server answered');
    u.history = const [];
    serverHistory = false; // an older server answer without a history: GitHub's list
    expect([for (final x in await u.releases()) x.version], ['0.4.5']);
  });

  testWidgets('S14-4: What\'s new lists every release with its points and date; Update · vX when a newer one is out; OK closes', (t) async {
    SharedPreferences.setMockInitialValues({});
    final u = Updater(await Prefs.load(), installer: FakeInstaller(), client: MockClient((_) async => http.Response('', 404)))
      ..history = [ReleaseNote('0.4.7', 100011, DateTime(2026, 11, 25), ['Old look everywhere', 'Chat by the drawer']), ReleaseNote('0.4.6', 100010, DateTime(2026, 11, 24), ['Settings'])]
      ..latest = Release('0.4.7', 100011, 'https://x/a.apk', 'https://x', ['Old look everywhere']);
    await t.pumpWidget(MaterialApp(localizationsDelegates: L.localizationsDelegates, home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => whatsNewSheet(c, u), child: const Text('go'))))));
    await t.tap(find.text('go'));
    await frames(t, 3);
    expect(find.byKey(const Key('whatsNewSheet')), findsOneWidget);
    for (final x in ['v0.4.7', 'v0.4.6', 'Old look everywhere', 'Chat by the drawer', 'Settings']) { expect(find.text(x), findsOneWidget, reason: x); }
    expect(find.text('Update · v0.4.7'), findsOneWidget);
    await tapKey(t, 'notesOk');
    await frames(t, 3);
    expect(find.byKey(const Key('whatsNewSheet')), findsNothing);
  });

  testWidgets('S14-4: nothing anywhere: "No notes for this version", no empty dialog', (t) async {
    SharedPreferences.setMockInitialValues({});
    final u = Updater(await Prefs.load(), installer: FakeInstaller(), client: MockClient((_) async => http.Response('', 404)));
    await t.pumpWidget(MaterialApp(localizationsDelegates: L.localizationsDelegates, home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => whatsNewSheet(c, u), child: const Text('go'))))));
    await t.tap(find.text('go'));
    await frames(t, 3);
    expect(find.byKey(const Key('whatsNewSheet')), findsNothing);
    expect(find.text('No notes for this version.'), findsOneWidget);
  });

  // ---------------------------------------------------------------- S14-5: transitions
  testWidgets('S14-5: a page fades in (half visible mid-way), and appears at once with animations off', (t) async {
    await launch(t);
    await frames(t, 2);
    await t.tap(find.byKey(const Key('settings')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    final fades = t.widgetList<FadeTransition>(find.ancestor(of: find.byKey(const Key('closeSettings')), matching: find.byType(FadeTransition)));
    expect(fades.any((f) => f.opacity.value > .05 && f.opacity.value < .95), isTrue, reason: 'mid-way, not a jump cut (his #4)');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('closeSettings')), findsOneWidget);
  });

  // ---------------------------------------------------------------- S14-6: the game card
  testWidgets('S14-6: an offline game screen sits in one card, buttons inside it, "Round 1 · 6/6 alive" under it', (t) async {
    await launch(t);
    await setUpGame(t, ['Dareer', 'Halawy', 'Farouq', 'Sami', 'Hokan', 'Khaddour']);
    await frames(t, 2);
    expect(find.text('Round 1 · 6/6 alive'), findsOneWidget);
    expect(find.byKey(const Key('stageFoot')), findsOneWidget);
  });
}
