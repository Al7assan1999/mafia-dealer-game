// [S17] 1.0.0 roles on the pass-the-phone screens: the Godfather's card, the Detective's read on him, the Sniper's night,
// two dead in one morning, and the Jester's win. Each game is a record with fixed roles, resumed like a saved game.
// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart' hide Action;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/offline/game_screen.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

const M = Role.mafia, D = Role.doctor, T = Role.detective, C0 = Role.citizen, S = Role.sniper, J = Role.jester;

/// A saved game with exactly these roles and this Godfather, after `actions`, open on `screen` for seat `who`.
Future<OfflineGame> resumed(WidgetTester t, List<Role> roles, int sheikh, String mode, List<Action> actions, String screen, int who,
    {String lang = 'en'}) async {
  final names = [for (var i = 0; i < roles.length; i++) 'P${i + 1}'];
  int n(Role r) => roles.where((x) => x == r).length;
  final c = createGame(Setup(names, Counts(n(M), 1, n(T)), defaultRules, mode), seeded(1));
  expect(c.error, isNull);
  var s = c.state!
    ..roles = [...roles]
    ..sheikh = sheikh;
  final rec = startRecord(s);
  var now = fakeNow;
  for (final a in [const Action.begin(), ...actions]) {
    final r = step(rec, s, a, Ctx(seeded(1), now += 1000));
    expect(r.error, isNull, reason: '${a.t} ${a.seat}');
    s = r.state!;
  }
  SharedPreferences.setMockInitialValues({'lang': lang});
  final prefs = await Prefs.load();
  prefs.game = {'rec': rec.toJson(), 'screen': screen, 'who': who, 'day': s.day};
  final audio = Audio(prefs), g = OfflineGame.resume(prefs, audio)!;
  t.view.physicalSize = const Size(393, 851);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox()); // a fresh GameScreen for each game
  await t.pumpWidget(MaterialApp(theme: noir(), locale: Locale(lang), supportedLocales: L.supportedLocales,
      localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: GameScreen(game: g, prefs: prefs, audio: audio)));
  await t.pump();
  addTearDown(() async { await t.pumpWidget(const SizedBox()); });
  return g;
}

/// Every seat's night turn in seat order (the picks given, the rest their first allowed option).
List<Action> nightOf(List<Role> roles, Map<int, Object> picks) => [
      for (var i = 0; i < roles.length; i++)
        Action.night(i, picks[i] ?? (roles[i] == M ? (roles.indexOf(C0)) : roles[i] == T || roles[i] == S ? (i == 0 ? 1 : 0) : 0)),
    ];

/// Presses and holds the role card while `check` runs, then lets go.
Future<void> holding(WidgetTester t, void Function() check) async {
  final g = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
  await t.pump();
  check();
  await g.up();
  await t.pump();
}

void main() {
  setUpAll(setUpHarness);

  testWidgets('the Godfather\'s card names him and says what he does; his teammate\'s card names him; every card says its side', (t) async {
    const roles = [M, M, D, T, C0, C0, C0, C0];
    await resumed(t, roles, 1, 'classic', const [], 'dealCard', 1);
    await holding(t, () {
      expect(t.widget<Text>(find.byKey(const Key('roleName'))).data, 'Godfather');
      expect(find.textContaining('your pick settles a tie'), findsOneWidget);
      expect(find.text('Mafia side · win when the Mafia are as many as everyone else'), findsOneWidget);
    });
    await resumed(t, roles, 1, 'classic', const [], 'dealCard', 0);
    await holding(t, () {
      expect(t.widget<Text>(find.byKey(const Key('roleName'))).data, 'Mafia');
      expect(find.text('Your Godfather: P2'), findsOneWidget);
    });
  });

  testWidgets('the Detective checks the Godfather: "not Mafia"', (t) async {
    const roles = [M, M, D, T, C0, C0, C0, C0];
    await resumed(t, roles, 0, 'classic', [const Action.night(0, 5), const Action.night(1, 5), const Action.night(2, 4), const Action.night(3, 0)],
        'nightLocked', 3);
    expect(t.widget<Text>(find.byKey(const Key('checkResult'))).data, 'P1 is not Mafia');
  });

  testWidgets('the Mafia see the Godfather\'s pick and that a tie goes to him', (t) async {
    const roles = [M, M, D, T, C0, C0, C0, C0];
    await resumed(t, roles, 1, 'classic', [const Action.night(1, 6)], 'nightPick', 0);
    expect(find.byKey(const Key('tieSheikh')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('opt_6')), matching: find.textContaining('Godfather\'s pick')), findsOneWidget);
  });

  testWidgets('[Ben] once the Godfather is out, the Mafia are told the lowest seat settles a tie', (t) async {
    const roles = [M, M, M, D, T, C0, C0, C0, C0, C0];
    await resumed(t, roles, 2, 'classic', [...nightOf(roles, {0: 5, 1: 5, 2: 5, 3: 6}), const Action.startDay(), const Action.decide(2), const Action.nextNight()],
        'nightPick', 0);
    expect(t.widget<Text>(find.byKey(const Key('tieSheikh'))).data, 'The Godfather is out: a tie goes to the lowest seat that voted.');
  });

  testWidgets('the Sniper: take the shot or keep the bullet; two dead in one morning, without saying who shot whom', (t) async {
    const roles = [M, M, D, T, S, J, C0, C0, C0];
    await resumed(t, roles, 1, 'all', [const Action.night(0, 8), const Action.night(1, 8), const Action.night(2, 6), const Action.night(3, 0)], 'nightPick', 4);
    expect(find.text('Take your shot?'), findsOneWidget);
    expect(find.byKey(const Key('opt_skip')), findsOneWidget);
    expect(find.text('Keep the bullet'), findsOneWidget);
    await resumed(t, roles, 1, 'all', nightOf(roles, {0: 8, 1: 8, 2: 6, 4: 6}), 'morning', 0);
    expect(find.text('Last night, these players died'), findsOneWidget);
    expect(find.text('P7'), findsOneWidget);
    expect(find.text('P9'), findsOneWidget);
  });

  testWidgets('his ruling: with roles revealed, the Godfather is named when he dies', (t) async {
    const roles = [M, M, D, T, S, J, C0, C0, C0];
    await resumed(t, roles, 1, 'all', nightOf(roles, {0: 8, 1: 8, 2: 6, 4: 1}), 'morning', 0);
    expect(find.text('They were: Godfather'), findsOneWidget);
  });

  testWidgets('the Jester voted out by day: "The Jester wins" on the recap', (t) async {
    const roles = [M, M, D, T, S, J, C0, C0, C0];
    final g = await resumed(t, roles, 1, 'all',
        [...nightOf(roles, {0: 6, 1: 6, 4: 'skip'}), const Action.startDay(), const Action.decide(5)], 'end', 0);
    expect(g.s.winner, Winner.jester);
    await t.pump();
    expect(t.widget<Text>(find.byKey(const Key('winner'))).data, 'The Jester wins');
    expect(find.text('Got the town to vote him out'), findsOneWidget);
  });

  testWidgets('Arabic: the Godfather is شيخ المافيا and the Jester الجوكر', (t) async {
    const roles = [M, M, D, T, S, J, C0, C0, C0];
    await resumed(t, roles, 0, 'all', const [], 'dealCard', 0, lang: 'ar');
    await holding(t, () => expect(t.widget<Text>(find.byKey(const Key('roleName'))).data, 'شيخ المافيا'));
    await resumed(t, roles, 0, 'all', const [], 'dealCard', 5, lang: 'ar');
    await holding(t, () => expect(t.widget<Text>(find.byKey(const Key('roleName'))).data, 'الجوكر'));
  });
}
