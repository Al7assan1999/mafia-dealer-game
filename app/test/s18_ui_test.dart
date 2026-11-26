// [S18] 1.1.0 on the screens: the Bodyguard (mode, the Sniper/Jester switch, his night, his card, the history and the
// player of the game), the Detective's marked results, the Sniper's night 1; offline, online and Wi-Fi.
// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart' hide Action;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/offline/game_screen.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/features/offline/setup_screen.dart';
import 'package:mafia_dealer/features/wifi/local_room.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';
import 'online_test.dart' show frames, openRoom, roomMsg, view;
import 's17_modes_test.dart' show openModes, pumpHome, tapIn;
import 's17_roles_ui_test.dart' show holding;

const M = Role.mafia, D = Role.doctor, T = Role.detective, C0 = Role.citizen, S = Role.sniper, B = Role.bodyguard;
// 8 players, Bodyguard mode: 0-1 Mafia (1 = the Godfather), 2 Doctor, 3 Detective, 4 Bodyguard, 5-7 Citizens
const BG = [M, M, D, T, B, C0, C0, C0];
// 8 players, Sniper mode with the Bodyguard: 0-1 Mafia, 2 Doctor, 3 Detective, 4 Sniper, 5 Bodyguard, 6-7 Citizens
const SB = [M, M, D, T, S, B, C0, C0];

/// A saved 1.1.0 game with exactly these roles (the mode's deck), after `actions`, open on `screen` for seat `who`.
Future<OfflineGame> resumed(WidgetTester t, List<Role> roles, String mode, List<Action> actions, String screen, int who, {String lang = 'en'}) async {
  final names = [for (var i = 0; i < roles.length; i++) 'P${i + 1}'];
  final c = createGame(Setup(names, const Counts(1, 1, 0), defaultRules.merge({'reveal': true}), mode, roles.contains(B)), seeded(1));
  expect(c.error, isNull);
  var s = c.state!
    ..roles = [...roles]
    ..sheikh = 1;
  expect(s.rv, 2);
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
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(MaterialApp(theme: noir(), locale: Locale(lang), supportedLocales: L.supportedLocales,
      localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: GameScreen(game: g, prefs: prefs, audio: audio)));
  await t.pump();
  addTearDown(() async { await t.pumpWidget(const SizedBox()); });
  return g;
}

List<Action> night(Map<int, Object?> picks) => [for (final e in picks.entries) Action.night(e.key, e.value)];
const nextDay = [Action.startDay(), Action.decide('none'), Action.nextNight()];
Finder tag(String key, String text) => find.descendant(of: find.byKey(Key(key)), matching: find.textContaining(text));

void main() {
  setUpAll(setUpHarness);

  testWidgets('S18-4 setup: the Bodyguard mode; Sniper and Jester get an "Add a Bodyguard" switch, Classic and All roles don\'t', (t) async {
    OfflineGame? dealt;
    final prefs = await pumpHome(t, (p) => SetupScreen(prefs: p, audio: Audio(p), onDealt: (g) => dealt = g));
    await openModes(t);
    expect(find.byKey(const Key('mode_bodyguard')), findsOneWidget);
    expect(find.byKey(const Key('withBodyguard')), findsNothing, reason: 'Classic');
    await tapIn(t, 'mode_sniper');
    expect(find.byKey(const Key('count_bodyguard')), findsNothing);
    await tapIn(t, 'withBodyguard');
    expect(t.widget<Text>(find.byKey(const Key('count_bodyguard'))).data, '1');
    await tapIn(t, 'mode_jester');
    expect(t.widget<SwitchListTile>(find.byKey(const Key('withBodyguard'))).value, isTrue, reason: 'kept between Sniper and Jester');
    await tapIn(t, 'mode_bodyguard');
    expect(find.byKey(const Key('withBodyguard')), findsNothing, reason: 'the Bodyguard mode always has him');
    expect(t.widget<Text>(find.byKey(const Key('count_bodyguard'))).data, '1');
    await tapIn(t, 'mode_sniper');
    await tapIn(t, 'deal');
    expect(dealt!.s.roles.where((r) => r == B), hasLength(1));
    expect(dealt!.s.roles.where((r) => r == S), hasLength(1));
    expect(prefs.setup?['bodyguard'], isTrue, reason: 'the switch is remembered');
  });

  testWidgets('the Bodyguard\'s card (English and Arabic: الحارس الشخصي) and his night: not himself, not the same player twice running', (t) async {
    await resumed(t, BG, 'bodyguard', const [], 'dealCard', 4);
    await holding(t, () {
      expect(t.widget<Text>(find.byKey(const Key('roleName'))).data, 'Bodyguard');
      expect(find.text("Citizens' side · win when every Mafia is out"), findsOneWidget);
    });
    await resumed(t, BG, 'bodyguard', const [], 'dealCard', 4, lang: 'ar');
    await holding(t, () => expect(t.widget<Text>(find.byKey(const Key('roleName'))).data, 'الحارس الشخصي'));
    await resumed(t, BG, 'bodyguard', night({0: 7, 1: 7, 2: 6, 3: 0}), 'nightPick', 4);
    expect(find.text('Who do you guard tonight?'), findsOneWidget);
    expect(t.widget<PickRow>(find.byKey(const Key('opt_4'))).onTap, isNull, reason: 'not himself');
    await resumed(t, BG, 'bodyguard', [...night({0: 7, 1: 7, 2: 6, 3: 0, 4: 5, 5: 0, 6: 0, 7: 0}), ...nextDay], 'nightPick', 4);
    expect(t.widget<PickRow>(find.byKey(const Key('opt_5'))).onTap, isNull);
    expect(tag('opt_5', 'guarded last night'), findsOneWidget);
  });

  testWidgets('B2 on screen: the Bodyguard dies in the morning; P2 the history says whom he guarded; the player of the game', (t) async {
    final g = await resumed(t, BG, 'bodyguard', night({0: 5, 1: 5, 2: 6, 3: 6, 4: 5, 5: 0, 6: 0, 7: 0}), 'morning', 0);
    expect(g.s.alive[4], isFalse);
    expect(find.text('P5'), findsOneWidget);
    expect(find.text('They were: Bodyguard'), findsOneWidget);
    // the town wins later: the Mafia voted out one by one
    final e = await resumed(t, BG, 'bodyguard', [...night({0: 5, 1: 5, 2: 6, 3: 6, 4: 5, 5: 0, 6: 0, 7: 0}), const Action.startDay(), const Action.decide(0),
      const Action.nextNight(), ...night({1: 6, 2: 7, 3: 1, 5: 1, 6: 1, 7: 1}), const Action.startDay(), const Action.decide(1)], 'end', 0);
    expect(e.s.winner, Winner.citizens);
    await t.pump();
    expect(find.textContaining('the Bodyguard guarded P6'), findsOneWidget);
    expect(find.text('Took the hit (1x)'), findsOneWidget);
    expect(find.byKey(const Key('took_4')), findsOneWidget, reason: '[Quin Q5] the recap marks the Bodyguard who took the hit');
  });

  testWidgets('S18-1 on screen: the Detective sees his earlier results marked and can\'t pick them; once everyone is checked, a list', (t) async {
    await resumed(t, BG, 'bodyguard', [...night({0: 7, 1: 7, 2: 7, 3: 0, 4: 6, 5: 0, 6: 0, 7: 0}), ...nextDay,
      ...night({0: 6, 1: 6, 2: 6, 3: 1, 4: 7, 5: 0, 6: 0, 7: 0}), ...nextDay], 'nightPick', 3);
    expect(tag('opt_0', 'Mafia'), findsOneWidget);
    expect(tag('opt_1', 'not Mafia'), findsOneWidget, reason: 'the Godfather reads not Mafia');
    expect(t.widget<PickRow>(find.byKey(const Key('opt_0'))).onTap, isNull);
    expect(t.widget<PickRow>(find.byKey(const Key('opt_2'))).onTap, isNotNull);
    // 6 players: everyone else checked over five nights (the Doctor saves the target each night)
    const six = [M, M, D, T, B, C0];
    final acts = <Action>[];
    for (final (k, q) in [0, 1, 2, 4, 5].indexed) { acts.addAll([...night({0: 5, 1: 5, 2: 5, 3: q, 4: k.isOdd ? 0 : 2, 5: 0}), ...nextDay]); }
    await resumed(t, six, 'bodyguard', acts, 'nightPick', 3);
    expect(find.text("You've checked everyone"), findsOneWidget);
    expect(find.byKey(const Key('myChecks')), findsOneWidget);
    await tapIn(t, 'confirm');
  });

  testWidgets('S18-2 on screen: on night 1 the Sniper picks like a Citizen, told his bullet is ready from night 2', (t) async {
    await resumed(t, SB, 'sniper', const [], 'nightPick', 4);
    expect(find.text('Take your shot?'), findsNothing);
    expect(find.byKey(const Key('sniperNight1')), findsOneWidget);
    expect(find.byKey(const Key('opt_skip')), findsNothing);
    await resumed(t, SB, 'sniper', [...night({0: 6, 1: 6, 2: 6, 3: 0, 4: 0, 5: 3, 6: 0, 7: 0}), ...nextDay], 'nightPick', 4);
    expect(find.text('Take your shot?'), findsOneWidget);
    expect(find.byKey(const Key('sniperNight1')), findsNothing);
  });

  testWidgets('[Quin Q4] decoy off: the Sniper\'s night 1 still says his bullet is ready from night 2', (t) async {
    final c = createGame(Setup([for (var i = 0; i < 8; i++) 'P${i + 1}'], const Counts(1, 1, 0), defaultRules.merge({'decoy': false}), 'sniper', true), seeded(1));
    final s = c.state!..roles = [...SB]..sheikh = 1;
    expect(nightOptions(apply(s, const Action.begin(), Ctx(seeded(1), 1)).state!, 4).key, 'none');
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'night', ph: 'night', extra: {'role': 'sniper', 'night': {'key': 'none', 'opts': [], 'skip': null}}));
    await frames(t);
    expect(find.byKey(const Key('sniperNight1')), findsOneWidget);
  });

  testWidgets('online: the Detective\'s marked options, and his results on his day screen (P1)', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'night', ph: 'night', extra: {'role': 'detective', 'night': {'key': 'detective', 'skip': null, 'opts': [
      for (var i = 0; i < 4; i++) {'seat': i, 'disabled': i < 2, 'self': i == 0, 'teammate': false, 'lastTarget': false, 'lastNight': false, 'mateVotes': 0, 'sheikh': false,
        if (i == 1) 'check': true},
    ]}}));
    await frames(t);
    expect(tag('opt_1', 'Mafia'), findsOneWidget);
    r.last.push(view(2, 'day', extra: {'role': 'detective', 'timer': {'left': 180}, 'checks': [{'seat': 1, 'mafia': true}, {'seat': 2, 'mafia': false}]}));
    await frames(t);
    expect(find.byKey(const Key('myChecks')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('myChecks')), matching: find.text('not Mafia')), findsOneWidget);
  });

  test('Wi-Fi: the host phone sends the Detective\'s results and the Bodyguard\'s hits like the server', () {
    final c = createGame(Setup([for (var i = 0; i < 8; i++) 'P${i + 1}'], const Counts(1, 1, 0), defaultRules.merge({'reveal': true}), 'bodyguard'), seeded(1));
    var s = c.state!..roles = [...BG]..sheikh = 1;
    for (final a in [const Action.begin(), ...night({0: 5, 1: 5, 2: 6, 3: 0, 4: 5, 5: 0, 6: 0, 7: 0}), ...nextDay]) { s = apply(s, a, Ctx(seeded(1), 1)).state!; }
    final v = viewJson(viewFor(s, 3, 1));
    expect(v['checks'], [{'seat': 0, 'mafia': true}]);
    final opts = ((v['night'] as Map)['opts'] as List).cast<Map>();
    expect(opts.firstWhere((o) => o['seat'] == 0)['check'], true);
    expect(opts.firstWhere((o) => o['seat'] == 2).containsKey('check'), isFalse);
    expect(s.stats.guards, [(4, 5)]);
  });
}
