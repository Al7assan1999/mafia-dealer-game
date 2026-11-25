// [S17-1, S17-4, S17-6] Modes: one tap in the setup and the lobby, the deck fixed by the mode, old phones kept out of
// the new roles, a role this app doesn't know, and the guide's modes.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/features/guide/guide_screen.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/features/offline/setup_screen.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_engine/mafia_engine.dart' hide Action;
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';
import 'online_test.dart' show frames, member, openRoom, roomMsg, view;

Future<Prefs> pumpHome(WidgetTester t, Widget Function(Prefs) home, {Map<String, Object> stored = const {}, String lang = 'en'}) async {
  t.view.physicalSize = const Size(393, 851);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({'lang': lang, ...stored});
  final prefs = await Prefs.load();
  await t.pumpWidget(MaterialApp(theme: noir(), locale: Locale(lang), supportedLocales: L.supportedLocales,
      localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: home(prefs)));
  await t.pump();
  return prefs;
}

Future<void> tapIn(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await t.tap(f);
  await t.pump();
}

void main() {
  setUpAll(setUpHarness);

  testWidgets('setup: four modes; one tap picks Sniper and fixes the deck; All roles needs 9; Sniper is Suggested at 6; the mode is kept', (t) async {
    OfflineGame? dealt;
    final prefs = await pumpHome(t, (p) => SetupScreen(prefs: p, audio: Audio(p), onDealt: (g) => dealt = g));
    for (final m in modes) { expect(find.byKey(Key('mode_$m')), findsOneWidget); }
    expect(find.byKey(const Key('suggested_sniper')), findsOneWidget);                 // 6 players
    expect(t.widget<Text>(find.byKey(const Key('modeFrom_all'))).data, 'From 9 players');
    await tapIn(t, 'mode_all');                                                        // can't be picked yet
    expect(find.byKey(const Key('count_sniper')), findsNothing);
    expect(find.byKey(const Key('minus_mafia')), findsOneWidget, reason: 'Classic: the table picks the counts');
    await tapIn(t, 'mode_sniper');
    expect(find.byKey(const Key('minus_mafia')), findsNothing, reason: 'a mode fixes the deck');
    expect(t.widget<Text>(find.byKey(const Key('count_sniper'))).data, '1');
    expect(t.widget<Text>(find.byKey(const Key('count_mafia'))).data, '2');
    expect(find.byKey(const Key('modeFixed')), findsOneWidget);
    await tapIn(t, 'deal');
    expect(dealt, isNotNull);
    expect(dealt!.s.mode, 'sniper');
    expect(dealt!.s.roles.where((r) => r == Role.sniper), hasLength(1));
    expect(dealt!.s.roles[dealt!.s.sheikh!], Role.mafia, reason: 'every game has a Godfather');
    expect(prefs.setup?['mode'], 'sniper');
  });

  testWidgets('Arabic setup: the modes in Arabic, right to left, with their minimum and the suggested one', (t) async {
    await pumpHome(t, (p) => SetupScreen(prefs: p, audio: Audio(p)), lang: 'ar');
    expect(find.text('كل الأدوار'), findsOneWidget);
    expect(find.text('القنّاص'), findsWidgets);
    expect(t.widget<Text>(find.byKey(const Key('modeFrom_all'))).data, 'من 9 لاعبين');
    expect(find.text('مقترح'), findsOneWidget);
    expect(Directionality.of(t.element(find.byKey(const Key('mode_all')))), TextDirection.rtl);
    expect(t.takeException(), isNull);
  });

  testWidgets('setup: a setup saved before 1.0.0 opens as Classic; a saved mode opens as that mode', (t) async {
    await pumpHome(t, (p) => SetupScreen(prefs: p, audio: Audio(p)), stored: {'setup': jsonEncode({'mafia': 2, 'detective': 1, 'rules': {}})});
    expect(find.byKey(const Key('minus_mafia')), findsOneWidget);
    expect(find.byKey(const Key('modeFixed')), findsNothing);
  });

  testWidgets('lobby: the host picks a mode with one tap; a phone below 1.0.0 is named and the deal waits for it, in Classic too', (t) async {
    final r = (await openRoom(t)).room;
    Map<String, Object?> room(String mode, List<int?> builds) {
      final m = roomMsg(1, members: [for (var i = 0; i < 6; i++) {...member(i, host: i == 0), 'v': builds[i]}]); // `v` null: none sent
      (m['room'] as Map)['mode'] = mode;
      return m;
    }
    r.last.push(room('classic', [modesBuild, modesBuild, modesBuild - 1, modesBuild, modesBuild, modesBuild]));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    await frames(t);
    expect(find.byKey(const Key('oldAppNote')), findsOneWidget, reason: 'his ruling: Classic waits for 1.0.0 too');
    expect(find.byKey(const Key('modeOld_3')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('oldAppNote'))).data, 'Everyone must update the app to 1.0.0 to play');
    await t.scrollUntilVisible(find.byKey(const Key('mode_jester')), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const Key('mode_jester')));
    await t.pump();
    final setup = r.last.msgs.lastWhere((m) => m['t'] == 'setup');
    expect(setup['mode'], 'jester');
    r.last.push(room('jester', [modesBuild, modesBuild, modesBuild - 1, modesBuild, null, modesBuild]));
    await frames(t);
    expect(find.byKey(const Key('oldAppNote')), findsOneWidget);
    expect(find.byKey(const Key('modeOld_3')), findsOneWidget);
    expect(find.byKey(const Key('modeOld_5')), findsOneWidget, reason: 'a phone that sent no build');
    expect(t.widget<Text>(find.byKey(const Key('dealSummary'))).data, startsWith('6 players · Jester ·'));
    r.last.push(room('jester', List.filled(6, modesBuild)));
    await frames(t);
    expect(find.byKey(const Key('oldAppNote')), findsNothing);
  });

  testWidgets('a role this app doesn\'t know (a later version): "Update the app", not a crash', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(2, 'deal', extra: {'role': 'witch'}));
    await frames(t);
    expect(find.textContaining('Update the app to play'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('How to Play lists the new roles and every mode with its minimum', (t) async {
    await pumpHome(t, (_) => const GuideScreen());
    for (final x in ['Godfather', 'Sniper', 'Jester']) { expect(find.text(x), findsWidgets); }
    await t.scrollUntilVisible(find.byKey(const Key('guideModes')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('All roles · From 9 players'), findsOneWidget);
    expect(find.text('Classic · From 4 players'), findsOneWidget);
  });
}
