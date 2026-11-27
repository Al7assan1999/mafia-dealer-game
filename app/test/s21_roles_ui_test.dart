// [S21] 1.4.0 on the screens: the Lovers and Lone Wolves modes, Cupid's two picks, the lovers' news, broken hearts, the
// Serial Killer, the Silencer (his pick, the morning line, the silenced phone); pass-and-play, online and Wi-Fi; the new
// endings; History's winner2 (D3).
// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart' hide Action;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/features/offline/game_screen.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/features/offline/setup_screen.dart';
import 'package:mafia_dealer/features/wifi/local_room.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver.dart' show tapKey;
import 'fake_server.dart';
import 'harness.dart';
import 'lan_room_test.dart' show Phone, id, newRoom, send;
import 'online_test.dart' show frames, openRoom, roomMsg, view;
import 's17_modes_test.dart' show openModes, pumpHome, tapIn;

const M = Role.mafia, D = Role.doctor, T = Role.detective, C0 = Role.citizen, B = Role.bodyguard, J = Role.jester, W = Role.watcher, K = Role.killer, U = Role.cupid;
// Lovers, 8: 0-1 Mafia (0 the Godfather), 2 Doctor, 3 Detective, 4 Cupid, 5-7 Citizens
const LV8 = [M, M, D, T, U, C0, C0, C0];
// Lone Wolves, 9: 0-1 Mafia, 2 Doctor, 3 Detective, 4 Bodyguard, 5 Serial Killer, 6-8 Citizens
const LW9 = [M, M, D, T, B, K, C0, C0, C0];
// Lone Wolves, 11: 0 Godfather, 1 Silencer, 2 Mafia, 3 Doctor, 4 Detective, 5 Bodyguard, 6 Serial Killer, 7 Watcher, 8 Jester, 9-10 Citizens
const LW11 = [M, M, M, D, T, B, K, W, J, C0, C0];
final off = defaultRules.merge({'reveal': false});

/// A saved 1.4.0 game with exactly these roles, after `actions`, open on `screen` for seat `who`.
Future<OfflineGame> resumed(WidgetTester t, List<Role> roles, String mode, List<Action> actions, String screen, int who,
    {int? silencer, String lang = 'en', Size size = const Size(393, 851), double text = 1}) async {
  final names = [for (var i = 0; i < roles.length; i++) 'P${i + 1}'];
  final c = createGame(Setup(names, Counts(roles.where((r) => r == M).length, 1, 0), off, mode), seeded(1));
  expect(c.error, isNull);
  var s = c.state!
    ..roles = [...roles]
    ..sheikh = 0
    ..framer = null
    ..silencer = silencer;
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
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(() { t.view.reset(); t.platformDispatcher.clearTextScaleFactorTestValue(); });
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(MaterialApp(theme: noir(), locale: Locale(lang), supportedLocales: L.supportedLocales,
      localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: GameScreen(game: g, prefs: prefs, audio: audio)));
  await t.pump();
  addTearDown(() async { await t.pumpWidget(const SizedBox()); });
  return g;
}

List<Action> night(Map<int, Object?> picks) => [for (final e in picks.entries) Action.night(e.key, e.value)];
String textOf(WidgetTester t, String key) => t.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  setUpAll(setUpHarness);

  testWidgets('setup: Lovers deals Cupid from 8; Lone Wolves deals the Serial Killer from 9, and the Silencer from 11', (t) async {
    OfflineGame? dealt;
    await pumpHome(t, (p) => SetupScreen(prefs: p, audio: Audio(p), onDealt: (g) => dealt = g));
    await openModes(t);
    expect(textOf(t, 'modeFrom_lovers'), 'From 8 players');
    expect(textOf(t, 'modeFrom_lonewolves'), 'From 9 players');
    for (var i = 0; i < 3; i++) { await tapIn(t, 'addPlayer'); }
    await tapIn(t, 'mode_lonewolves');
    expect(textOf(t, 'count_killer'), '1');
    await tapIn(t, 'deal');
    expect(dealt!.s.roles.where((r) => r == K), hasLength(1));
  });

  testWidgets('pass-and-play: Cupid picks two (Confirm waits for both); the lovers learn name and side on their next turn', (t) async {
    final g = await resumed(t, LV8, 'lovers', const [], 'nightPick', 4);
    expect(find.text('Link two lovers'), findsOneWidget);
    await tapKey(t, 'opt_5');
    expect(t.widget<Btn>(find.byKey(const Key('confirm'))).onTap, isNull, reason: 'one lover is not a couple');
    await tapKey(t, 'opt_1');
    await tapKey(t, 'confirm');
    expect(g.s.night.cupid[4], (5, 1));
    await resumed(t, LV8, 'lovers', [Action.nightWith(4, 6, pair: 7, hasPair: true), ...night({0: 5, 1: 5, 2: 2, 3: 0, 5: 0, 6: 0, 7: 0}),
      const Action.startDay(), const Action.decide('none'), const Action.nextNight()], 'nightPick', 6);
    expect(find.text('Your lover: P8 (town side)'), findsOneWidget);
  });

  testWidgets('pass-and-play: a broken heart in the morning; the Serial Killer\'s kill; who can\'t vote today', (t) async {
    await resumed(t, LV8, 'lovers', [Action.nightWith(4, 5, pair: 1, hasPair: true), ...night({0: 5, 1: 5, 2: 2, 3: 0, 5: 0, 6: 0, 7: 0})], 'morning', 0);
    expect(find.text('P2 died of a broken heart'), findsOneWidget);
    await resumed(t, LW11, 'lonewolves', [...night({0: 9, 2: 9, 3: 3, 4: 0, 5: 4, 6: 10, 7: 9, 8: 0, 9: 0, 10: 0}),
      Action.nightWith(1, 9, silence: 8, hasSilence: true)], 'morning', 0, silencer: 1);
    expect(find.text("P9 can't vote today"), findsOneWidget);
    expect(find.text('P11'), findsOneWidget, reason: 'the Serial Killer\'s victim, named with the others');
  });

  testWidgets('pass-and-play: the Silencer must pick someone or "Nobody" before he confirms', (t) async {
    final g = await resumed(t, LW11, 'lonewolves', const [], 'nightPick', 1, silencer: 1);
    await tapKey(t, 'opt_9');
    expect(t.widget<Btn>(find.byKey(const Key('confirm'))).onTap, isNull);
    await t.ensureVisible(find.byKey(const Key('silence_none')));
    await tapKey(t, 'silence_none');
    await tapKey(t, 'confirm');
    expect(g.s.night.done.contains(1), isTrue);
    expect(g.s.night.silence[1], isNull);
  });

  testWidgets('pass-and-play: the Serial Killer\'s win ends the game in his colour, with no Mafia voice', (t) async {
    final g = await resumed(t, LW9, 'lonewolves', [...night({0: 6, 1: 6, 2: 2, 3: 0, 4: 2, 5: 7, 6: 0, 7: 0, 8: 0}), const Action.startDay(), const Action.decide(0),
      const Action.nextNight(), ...night({1: 8, 2: 2, 3: 1, 4: 5, 5: 1, 8: 1}), const Action.startDay(), const Action.decide(2), const Action.nextNight(),
      ...night({3: 4, 4: 3, 5: 3})], 'end', 0);
    expect(g.s.winner, Winner.killer);
    await t.pump();
    expect(find.textContaining('The Serial Killer wins'), findsWidgets);
  });

  testWidgets('online: Cupid sends his two; the Silencer his pick; the morning names the silenced and the broken heart', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'night', ph: 'night', extra: {'role': 'cupid', 'night': {'key': 'cupid', 'skip': null, 'opts': [
      for (var i = 0; i < 4; i++) {'seat': i, 'disabled': false, 'self': i == 0, 'teammate': false, 'lastTarget': false, 'lastNight': false, 'mateVotes': 0, 'sheikh': false},
    ]}}));
    await frames(t);
    await tapKey(t, 'opt_2');
    expect(t.widget<Btn>(find.byKey(const Key('confirm'))).onTap, isNull);
    await tapKey(t, 'opt_3');
    await tapKey(t, 'confirm');
    expect(r.last.msgs.last, {'t': 'night', 'choice': 2, 'day': 1, 'pair': 3});
    r.last.push(view(2, 'night', ph: 'night', extra: {'role': 'mafia', 'mates': [1], 'sheikh': 1, 'silencer': 0, 'night': {'key': 'mafia', 'skip': null, 'silence': [1, 2, 3], 'opts': [
      for (var i = 0; i < 4; i++) {'seat': i, 'disabled': i < 2, 'self': i == 0, 'teammate': i == 1, 'lastTarget': false, 'lastNight': false, 'mateVotes': 0, 'sheikh': false},
    ]}}));
    await frames(t);
    await tapKey(t, 'opt_2');
    await t.ensureVisible(find.byKey(const Key('silence_3')));
    await tapKey(t, 'silence_3');
    await tapKey(t, 'confirm');
    expect(r.last.msgs.last, {'t': 'night', 'choice': 2, 'day': 1, 'silence': 3});
    r.last.push(view(3, 'morning', extra: {'seat': 0, 'role': 'doctor', 'silenced': 3,
      'result': {'k': 'killed', 'seat': 2, 'role': null, 'hearts': [{'seat': 1, 'role': null}]}}));
    await frames(t);
    expect(find.text('P2 died of a broken heart'), findsOneWidget);
    expect(find.text("P4 can't vote today"), findsOneWidget);
  });

  testWidgets('online: the silenced player\'s vote screen says why he can\'t vote', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'vote', ph: 'voted', extra: {'seat': 0, 'role': 'citizen', 'silenced': 0, 'voteId': 5}));
    await frames(t);
    expect(find.text("You can't vote today"), findsOneWidget);
  });

  testWidgets('[Quin Q2] signed in: the Mafia count chosen for the Sniper mode is kept (the account copy has no "ranged")', (t) async {
    final names = [for (var i = 0; i < 10; i++) 'P${i + 1}'];
    SharedPreferences.setMockInitialValues({'lang': 'en', 'players': names});
    final prefs = await Prefs.load();
    prefs.setup = {'mafia': 2, 'detective': 1, 'rules': off.toJson(), 'mode': 'sniper', 'bodyguard': false, 'ranged': true};
    final server = FakeServer(), account = Account(server.api(), MemoryTokens()..t = server.user('P1'), prefs, google: FakeGoogle(), live: false);
    await t.runAsync(account.restore);
    expect(account.signedIn, isTrue);
    expect(account.setup?['ranged'], isNull, reason: 'the account copy keeps counts, rules and mode only');
    t.view.physicalSize = const Size(393, 851);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: noir(), supportedLocales: L.supportedLocales,
        localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: SetupScreen(prefs: prefs, audio: Audio(prefs), account: account)));
    await t.pump();
    expect(textOf(t, 'count_mafia'), '2', reason: 'not back to the range default (3)');
  });

  testWidgets('[Quin Q3] online: a lover sees the partner on the morning and day screens (R4: the morning of day 1)', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'morning', extra: {'seat': 0, 'role': 'citizen', 'lover': {'seat': 2, 'side': 'mafia'}, 'result': {'k': 'nobody'}}));
    await frames(t);
    expect(find.byKey(const Key('loverNews')), findsOneWidget);
    expect(textOf(t, 'loverNews'), contains('P3'));
    r.last.push(view(2, 'day', extra: {'seat': 0, 'role': 'citizen', 'lover': {'seat': 2, 'side': 'mafia'}, 'timer': {'left': 60}}));
    await frames(t);
    expect(find.byKey(const Key('loverNews')), findsOneWidget);
  });

  testWidgets('[Quin Q8] the end screen\'s backdrop: blood for the Serial Killer, as for the Mafia', (t) async {
    await resumed(t, LW9, 'lonewolves', [...night({0: 6, 1: 6, 2: 2, 3: 0, 4: 2, 5: 7, 6: 0, 7: 0, 8: 0}), const Action.startDay(), const Action.decide(0),
      const Action.nextNight(), ...night({1: 8, 2: 2, 3: 1, 4: 5, 5: 1, 8: 1}), const Action.startDay(), const Action.decide(2), const Action.nextNight(),
      ...night({3: 4, 4: 3, 5: 3})], 'end', 0);
    await t.pump();
    expect(t.widget<Stage>(find.byType(Stage).first).color, C.blood);
    expect([winStage(Winner.lovers), winStage(Winner.draw), winStage(Winner.citizens), winStage(Winner.jester)], [C.night, C.day, C.glory, C.glory]);
  });

  test('D3: a game from the server reads winner2 first; the old field is what a 1.3 phone would show', () {
    expect(winnerIn({'winner': 'citizens', 'winner2': 'killer'}), 'killer');
    expect(winnerIn({'winner': 'mafia'}), 'mafia');
  });

  test('Wi-Fi: Lovers and Lone Wolves need 1.4.0 on every phone; the host sends the silenced and the lovers like the server', () {
    final r = newRoom(), ps = [for (var i = 0; i < 8; i++) Phone('p$i')];
    for (var i = 0; i < 8; i++) { expect(r.join(ps[i], id(i), build: i == 7 ? roles14Build - 1 : roles14Build), isNull); }
    send(r, ps[0], {'t': 'setup', 'rules': off.toJson(), 'counts': {'mafia': 2, 'detective': 1}, 'buzzMax': 3, 'mode': 'lovers'});
    send(r, ps[0], {'t': 'deal'});
    expect(ps[0].last('err')?['error'], 'old_app');
    final c = createGame(Setup([for (var i = 0; i < 11; i++) 'P${i + 1}'], const Counts(3, 1, 1), off, 'lonewolves'), seeded(1));
    var s = c.state!..roles = [...LW11]..sheikh = 0..framer = null..silencer = 1;
    for (final a in [const Action.begin(), ...night({0: 9, 2: 9, 3: 3, 4: 0, 5: 4, 6: 10, 7: 9, 8: 0, 9: 0, 10: 0}), Action.nightWith(1, 9, silence: 8, hasSilence: true)]) {
      s = apply(s, a, Ctx(seeded(1), 1)).state!;
    }
    final mv = viewJson(viewFor(s, 0, 1)), tv = viewJson(viewFor(s, 3, 1));
    expect(tv['silenced'], 8);
    expect(mv['silencer'], 1);
    expect(tv.containsKey('silencer'), isFalse, reason: 'only the Mafia know him');
  });

  testWidgets('S21-6: Arabic, a small phone, large text: Cupid\'s night and the Silencer\'s night fit', (t) async {
    const small = Size(320, 568);
    await resumed(t, LV8, 'lovers', const [], 'nightPick', 4, lang: 'ar', size: small, text: 1.3);
    expect(find.text('اربط عاشقَين'), findsOneWidget);
    await resumed(t, LW11, 'lonewolves', const [], 'nightPick', 1, silencer: 1, lang: 'ar', size: small, text: 1.3);
    expect(find.text('أسكِت أحدًا'), findsOneWidget);
  });
}
