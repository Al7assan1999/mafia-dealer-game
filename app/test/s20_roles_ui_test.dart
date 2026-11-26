// [S20] 1.3.0 on the screens: the Avenger and Shadows modes (the Mafia range, the lean note), the Hunter's shot, the
// Mayor's reveal, the Framer's frame, the Watcher's results; pass-and-play, online and Wi-Fi; old-phone roles (C1).
// ignore_for_file: constant_identifier_names
import 'package:flutter/material.dart' hide Action;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/features/offline/game_screen.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/features/offline/setup_screen.dart';
import 'package:mafia_dealer/features/wifi/local_room.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver.dart' show tapKey;
import 'harness.dart';
import 'lan_room_test.dart' show Phone, id, newRoom, send;
import 'online_test.dart' show frames, openRoom, roomMsg, view;
import 's17_modes_test.dart' show pumpHome, tapIn;
import 's17_roles_ui_test.dart' show holding;

const M = Role.mafia, D = Role.doctor, T = Role.detective, C0 = Role.citizen, S = Role.sniper, H = Role.hunter, Y = Role.mayor, W = Role.watcher;
// Avenger, 6: 0-1 Mafia (0 = the Godfather), 2 Doctor, 3 Detective, 4 Hunter, 5 Citizen; 7: + the Mayor (5)
const AV6 = [M, M, D, T, H, C0], AV7 = [M, M, D, T, H, Y, C0];
// Shadows, 8: 0 Godfather, 1 Framer, 2 Doctor, 3 Detective, 4 Watcher, 5 Sniper, 6-7 Citizens
const SH8 = [M, M, D, T, W, S, C0, C0];
final off = defaultRules.merge({'reveal': false}); // the way the group plays

/// A saved 1.3.0 game with exactly these roles, after `actions`, open on `screen` for seat `who`.
Future<OfflineGame> resumed(WidgetTester t, List<Role> roles, String mode, List<Action> actions, String screen, int who,
    {Rules? rules, String lang = 'en', Size size = const Size(393, 851), double text = 1}) async {
  final names = [for (var i = 0; i < roles.length; i++) 'P${i + 1}'];
  final c = createGame(Setup(names, Counts(roles.where((r) => r == M).length, 1, 0), rules ?? off, mode), seeded(1));
  expect(c.error, isNull);
  var s = c.state!
    ..roles = [...roles]
    ..sheikh = 0
    ..framer = mode == 'shadows' ? 1 : null;
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
const nextDay = [Action.startDay(), Action.decide('none'), Action.nextNight()];
String textOf(WidgetTester t, String key) => t.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  setUpAll(setUpHarness);

  testWidgets('§8 setup: Avenger deals the Hunter (never the Sniper); the default rules (reveal off, his ruling) give 6 players a choice of 1 or 2 Mafia', (t) async {
    OfflineGame? dealt;
    await pumpHome(t, (p) => SetupScreen(prefs: p, audio: Audio(p), onDealt: (g) => dealt = g));
    expect(find.byKey(const Key('modeFrom_shadows')), findsOneWidget, reason: 'Shadows from 8 players');
    await tapIn(t, 'mode_avenger');
    expect(textOf(t, 'count_hunter'), '1');
    expect(textOf(t, 'count_mafia'), '2');
    expect(textOf(t, 'mafiaNote'), 'You can play 1 or 2 Mafia', reason: 'the default leans nowhere');
    await tapIn(t, 'deal');
    expect(dealt!.s.roles.where((r) => r == H), hasLength(1));
    expect(dealt!.s.roles.contains(S), isFalse);
  });

  testWidgets('§8 B: Shadows at 9 offers 2 or 3 Mafia (3 by default, no Jester); 2 brings the Jester in', (t) async {
    Counts? picked;
    await pumpHome(t, (p) => Scaffold(body: SingleChildScrollView(child: StatefulBuilder(builder: (c, set) {
      final cc = modeCounts('shadows', 9, picked ?? const Counts(1, 1, 1), false, off);
      return DeckEditor(players: 9, counts: cc, mode: 'shadows', rules: off, onChanged: (x) => set(() => picked = x));
    }))));
    expect(textOf(t, 'count_mafia'), '3');
    expect(textOf(t, 'mafiaNote'), 'You can play 2 or 3 Mafia');
    expect(find.byKey(const Key('count_jester')), findsNothing);
    expect(find.byKey(const Key('count_watcher')), findsOneWidget);
    await tapKey(t, 'minus_mafia');
    expect(textOf(t, 'count_mafia'), '2');
    expect(textOf(t, 'count_jester'), '1');
  });

  testWidgets('E-H1-H3 pass-and-play: the night kills the Hunter, the phone goes to him, his shot is shown, then the day', (t) async {
    final g = await resumed(t, AV6, 'avenger', night({0: 4, 1: 4, 2: 2, 3: 0, 4: 0, 5: 0}), 'morning', 0);
    expect(find.byKey(const Key('huntAim')), findsOneWidget);
    expect(find.byKey(const Key('startDay')), findsNothing, reason: 'the Hunter first');
    await tapKey(t, 'huntTake');
    expect(g.screen, Screen.huntPass);
    expect(g.who, 4);
    await tapKey(t, 'open');
    expect(find.text("You're out. Take someone with you?"), findsOneWidget);
    expect(find.byKey(const Key('opt_4')), findsNothing, reason: 'not himself');
    await tapKey(t, 'opt_0');
    await tapKey(t, 'confirm');
    expect(g.screen, Screen.shot);
    expect(find.text('P5 shot P1'), findsOneWidget);
    await tapKey(t, 'startDay');
    expect(g.screen, Screen.day);
    expect(g.s.alive[0], isFalse);
  });

  testWidgets('E-H5 pass-and-play: voted out, he holds fire; the verdict then goes on to the night', (t) async {
    final g = await resumed(t, AV6, 'avenger', [...night({0: 'skip', 1: 'skip', 2: 2, 3: 0, 4: 0, 5: 0}), const Action.startDay(), const Action.decide(4)], 'verdict', 0);
    await tapKey(t, 'huntTake');
    await tapKey(t, 'open');
    await tapKey(t, 'opt_hold');
    await tapKey(t, 'confirm');
    expect(find.text('P5 held fire'), findsOneWidget);
    await tapKey(t, 'nextNight');
    expect(g.s.phase, Phase.night);
  });

  testWidgets('R3 pass-and-play: the Mayor reveals from his night turn; the morning says so; his chip says ×2; the Doctor can\'t pick him', (t) async {
    final g = await resumed(t, AV7, 'avenger', const [], 'nightPick', 5);
    expect(find.byKey(const Key('revealTomorrow')), findsOneWidget);
    await tapKey(t, 'revealTomorrow');
    await tapKey(t, 'opt_0');
    await tapKey(t, 'confirm');
    expect(g.s.night.reveal, contains(5));
    await resumed(t, AV7, 'avenger', [Action.nightWith(5, 0, reveal: true), ...night({0: 6, 1: 6, 2: 2, 3: 0, 4: 0, 6: 0})], 'morning', 0);
    expect(find.text('P6 is the Mayor'), findsOneWidget);
    await tapKey(t, 'startDay');
    expect(find.text('P6 · Mayor ×2'), findsOneWidget);
    await resumed(t, AV7, 'avenger', [Action.nightWith(5, 0, reveal: true), ...night({0: 6, 1: 6, 2: 2, 3: 0, 4: 0, 6: 0}), ...nextDay], 'nightPick', 2);
    expect(t.widget<PickRow>(find.byKey(const Key('opt_5'))).onTap, isNull);
    expect(find.textContaining("Mayor: can't be protected"), findsOneWidget);
  });

  testWidgets('E-F, E-W pass-and-play: the Framer frames; the Detective waits for his next turn and reads Mafia; the Watcher sees who came', (t) async {
    final f = await resumed(t, SH8, 'shadows', const [], 'nightPick', 1);
    expect(find.text('Frame someone'), findsOneWidget);
    expect(find.byKey(const Key('frame_0')), findsNothing, reason: 'never a teammate');
    await tapKey(t, 'opt_6');
    await t.ensureVisible(find.byKey(const Key('frame_7')));
    await tapKey(t, 'frame_7');
    await tapKey(t, 'confirm');
    expect(f.s.night.frame[1], 7);
    // the Detective checked P8 (seat 7) that night: "your result will be on your next turn"
    await resumed(t, SH8, 'shadows', [Action.nightWith(1, 6, frame: 7, hasFrame: true), ...night({3: 7})], 'nightLocked', 3);
    expect(find.byKey(const Key('checkNext')), findsOneWidget);
    expect(find.byKey(const Key('checkResult')), findsNothing);
    final picks = [Action.nightWith(1, 6, frame: 7, hasFrame: true), ...night({0: 6, 2: 2, 3: 7, 4: 7, 5: 0, 6: 0, 7: 0}), ...nextDay];
    await resumed(t, SH8, 'shadows', picks, 'nightPick', 3);
    expect(find.descendant(of: find.byKey(const Key('myChecks')), matching: find.text('Mafia')), findsOneWidget, reason: 'the frame worked');
    await resumed(t, SH8, 'shadows', picks, 'nightPick', 4);
    expect(find.text('P8: visited by P2, P4'), findsOneWidget, reason: 'the Framer and the Detective');
    await resumed(t, SH8, 'shadows', picks, 'nightPick', 1);
    expect(find.text('Your frame on P8 worked: the Detective checked them'), findsOneWidget);
  });

  testWidgets('[Ben] the verdict says why there are more votes than players: the Mayor\'s counts twice', (t) async {
    final picks = [Action.nightWith(5, 0, reveal: true), ...night({0: 6, 1: 6, 2: 2, 3: 0, 4: 0, 6: 0}), const Action.startDay(), const Action.startVote(false),
      for (final (v, c) in [(0, 2), (1, 2), (2, 1), (3, 1), (4, 1), (5, 1)]) Action.vote(v, c)];
    final g = await resumed(t, AV7, 'avenger', picks, 'verdict', 0);
    expect(g.s.verdict!.tally!.first.n, 5, reason: 'the Mayor plus three');
    expect(find.byKey(const Key('tallyMayor')), findsOneWidget);
  });

  testWidgets('the Framer\'s card names him; his teammate\'s card says who the Framer is', (t) async {
    await resumed(t, SH8, 'shadows', const [], 'dealCard', 1);
    await holding(t, () => expect(t.widget<Text>(find.byKey(const Key('roleName'))).data, 'Framer'));
    await resumed(t, SH8, 'shadows', const [], 'dealCard', 0);
    await holding(t, () => expect(find.text('The Framer: P2'), findsOneWidget));
  });

  testWidgets('online: the dead Hunter aims (or holds fire); the others wait; the host can\'t start the day until he has', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'morning', ph: 'hunt', extra: {'role': 'hunter', 'alive': false, 'huntOpts': [1, 2, 3], 'hunt': {'seat': 0}, 'hunted': null,
      'result': {'k': 'killed', 'seat': 0, 'role': null}}));
    await frames(t);
    expect(find.byKey(const Key('opt_0')), findsNothing);
    await tapKey(t, 'opt_2');
    await tapKey(t, 'confirm');
    expect(r.last.msgs.last, {'t': 'hunt', 'choice': 2});
    r.last.push(view(2, 'morning', ph: 'hunt', extra: {'role': 'hunter', 'alive': false, 'huntOpts': [1, 2, 3], 'hunt': {'seat': 0}, 'hunted': null}));
    await frames(t);
    await tapKey(t, 'opt_hold');
    await tapKey(t, 'confirm');
    expect(r.last.msgs.last, {'t': 'hunt', 'choice': null});
    // a seat who watches: "P1, the Hunter, is taking aim…", no Start day for the host yet
    r.last.push(view(3, 'morning', extra: {'seat': 1, 'role': 'doctor', 'hunt': {'seat': 0}, 'hunted': null, 'result': {'k': 'killed', 'seat': 0, 'role': null}}));
    await frames(t);
    expect(find.text('P1, the Hunter, is taking aim…'), findsOneWidget);
    expect(find.byKey(const Key('startDay')), findsNothing);
    r.last.push(view(4, 'morning', extra: {'seat': 1, 'role': 'doctor', 'hunt': null, 'hunted': {'by': 0, 'seat': 2, 'role': null}, 'result': {'k': 'killed', 'seat': 0, 'role': null}}));
    await frames(t);
    expect(find.text('P1 shot P3'), findsOneWidget);
    expect(find.byKey(const Key('startDay')), findsOneWidget);
  });

  testWidgets('online: the Mayor reveals by day (after a confirm); every phone then names him and marks his ×2', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'day', extra: {'role': 'mayor', 'timer': {'left': 180}, 'mayors': <int>[]}));
    await frames(t);
    await tapIn(t, 'mayorReveal');
    await t.tap(find.widgetWithText(TextButton, "Reveal: I'm the Mayor"));
    await t.pump();
    expect(r.last.msgs.last, {'t': 'reveal'});
    r.last.push(view(2, 'day', extra: {'role': 'mayor', 'timer': {'left': 180}, 'mayors': [0]}));
    await frames(t);
    expect(find.byKey(const Key('mayorReveal')), findsNothing);
    expect(find.byKey(const Key('mayorIs_0')), findsOneWidget);
    expect(find.text('P1 · Mayor ×2'), findsOneWidget);
  });

  testWidgets('online: the Framer sends his frame with his kill vote', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'night', ph: 'night', extra: {'role': 'mafia', 'mates': [1], 'sheikh': 1, 'framer': 0, 'night': {'key': 'mafia', 'skip': null, 'frame': [2, 3], 'opts': [
      for (var i = 0; i < 4; i++) {'seat': i, 'disabled': i < 2, 'self': i == 0, 'teammate': i == 1, 'lastTarget': false, 'lastNight': false, 'mateVotes': 0, 'sheikh': false},
    ]}}));
    await frames(t);
    await tapKey(t, 'opt_2');
    expect(t.widget<Btn>(find.byKey(const Key('confirm'))).onTap, isNull, reason: '[Quin Q5] a frame or "No frame" first');
    await t.ensureVisible(find.byKey(const Key('frame_3')));
    await tapKey(t, 'frame_3');
    await tapKey(t, 'confirm');
    expect(r.last.msgs.last, {'t': 'night', 'choice': 2, 'day': 1, 'frame': 3});
    // [Quin Q5] a frame tapped on a turn that ran out doesn't carry into the next night
    Map<String, Object?> nv(int rev, int day, List<int> frame, bool Function(int) off) => view(rev, 'night', ph: 'night', extra: {'day': day, 'role': 'mafia', 'mates': [1],
      'sheikh': 1, 'framer': 0, 'night': {'key': 'mafia', 'skip': null, 'frame': frame, 'opts': [
        for (var i = 0; i < 4; i++) {'seat': i, 'disabled': off(i), 'self': i == 0, 'teammate': i == 1, 'lastTarget': false, 'lastNight': false, 'mateVotes': 0, 'sheikh': false},
      ]}});
    r.last.push(nv(2, 2, [2, 3], (i) => i < 2));
    await frames(t);
    await t.ensureVisible(find.byKey(const Key('frame_2')));
    await tapKey(t, 'frame_2');
    r.last.push(nv(3, 3, [3], (i) => i != 3));
    await frames(t);
    await tapKey(t, 'opt_3');
    expect(t.widget<Btn>(find.byKey(const Key('confirm'))).onTap, isNull, reason: 'the old frame was cleared');
    await t.ensureVisible(find.byKey(const Key('frame_none')));
    await tapKey(t, 'frame_none');
    await tapKey(t, 'confirm');
    expect(r.last.msgs.last, {'t': 'night', 'choice': 3, 'day': 3, 'frame': null});
  });

  testWidgets('[Quin Q1, Q4] online: the host goes on without the Hunter: at once if he is away or left, after a question if he is here', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    Map<String, Object?> m(int i) => {'uid': 'u$i', 'cn': i + 1, 'display': 'P${i + 1}', 'handle': 'p${i + 1}', 'avatar': {'preset': 0},
      'online': true, 'host': i == 0, 'ready': false, 'muted': false, 'seat': i, 'v': roles13Build};
    final hv = view(1, 'morning', extra: {'seat': 0, 'role': 'doctor', 'hunt': {'seat': 1}, 'hunted': null, 'result': {'k': 'killed', 'seat': 1, 'role': null},
      'roster': [for (var i = 0; i < 4; i++) {'name': 'P${i + 1}', 'alive': i != 1}]});
    r.last.push(roomMsg(1, status: 'game', members: [m(0), m(2), m(3)])); // the Hunter (seat 1) left the room
    r.last.push(hv);
    await frames(t);
    await tapIn(t, 'continue');
    expect(r.last.msgs.last, {'t': 'continue'});
    r.last.push(roomMsg(2, status: 'game', members: [m(0), m(1), m(2), m(3)])); // he is here, just not answering
    await frames(t);
    await tapIn(t, 'continue');
    expect(find.text("Go on without the Hunter's shot?"), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton)).last); // the dialog's yes
    await t.pump();
    expect(r.last.msgs.last, {'t': 'continue'});
  });

  testWidgets('[Quin Q2] pass-and-play with the night timer: the phone waits for the Hunter (no clock on his shot)', (t) async {
    final g = await resumed(t, AV6, 'avenger', night({0: 4, 1: 4, 2: 2, 3: 0, 4: 0, 5: 0}), 'morning', 0, rules: off.merge({'nightT': 30}));
    await tapKey(t, 'huntTake');
    await t.pump(const Duration(minutes: 2));
    expect(g.screen, Screen.huntPass);
    expect(g.s.hunt, isNotNull);
  });

  testWidgets("S20-7 AC1: Arabic, a small phone, large text: the Hunter's shot, the Framer's night, the Mayor's turn fit", (t) async {
    const small = Size(320, 568);
    await resumed(t, AV6, 'avenger', night({0: 4, 1: 4, 2: 2, 3: 0, 4: 0, 5: 0}), 'huntPick', 4, lang: 'ar', size: small, text: 1.3);
    expect(find.text('لا أطلق'), findsOneWidget);
    await resumed(t, SH8, 'shadows', const [], 'nightPick', 1, lang: 'ar', size: small, text: 1.3);
    expect(find.text('لفّق تهمة لأحد'), findsOneWidget);
    await resumed(t, AV7, 'avenger', const [], 'nightPick', 5, lang: 'ar', size: small, text: 1.3);
    expect(find.text('اكشفني كعمدة في الصباح'), findsOneWidget);
    await resumed(t, AV6, 'avenger', night({0: 4, 1: 4, 2: 2, 3: 0, 4: 0, 5: 0}), 'morning', 0, lang: 'ar', size: small, text: 1.3);
    expect(find.byKey(const Key('huntAim')), findsOneWidget);
  });

  test('C1: History and game pages read role2 first; an unknown role is a Citizen, never a crash', () {
    expect(roleIn({'role': 'citizen', 'role2': 'hunter'}), Role.hunter);
    expect(roleIn({'role': 'mafia'}), Role.mafia);
    expect(roleIn({'role': 'witch'}), Role.citizen);
  });

  test('[Quin Q1] Wi-Fi: the aiming Hunter leaves the room: he holds fire, the game goes on', () {
    final r = newRoom(), ps = [for (var i = 0; i < 6; i++) Phone('p$i')];
    for (var i = 0; i < 6; i++) { expect(r.join(ps[i], id(i), build: roles13Build), isNull); }
    send(r, ps[0], {'t': 'setup', 'rules': off.toJson(), 'counts': {'mafia': 2, 'detective': 1}, 'buzzMax': 3, 'mode': 'avenger'});
    send(r, ps[0], {'t': 'deal'});
    send(r, ps[0], {'t': 'start'});
    final roles = r.game!.roles, h = roles.indexOf(H), doc = roles.indexOf(D);
    for (var i = 0; i < 6; i++) {
      final no = ps[i].view!['night'] as Map;
      final choice = roles[i] == M ? h : i == doc ? doc : no['key'] == 'none' ? null : (no['opts'] as List).cast<Map>().firstWhere((o) => o['disabled'] != true)['seat'];
      send(r, ps[i], {'t': 'night', 'choice': choice, 'day': 1});
    }
    expect(r.game!.hunt?.seat, h);
    if (h == 0) return; // the host is the Hunter: leaving would close the room
    send(r, ps[h], {'t': 'leave'});
    expect(r.game!.hunt, isNull);
    expect(r.game!.log.whereType<HuntLog>().single.target, isNull);
  });

  test('Wi-Fi: Avenger and Shadows need 1.3.0 on every phone; the host phone sends the Hunter\'s aim and the Mayors like the server', () {
    final r = newRoom(), ps = [for (var i = 0; i < 6; i++) Phone('p$i')];
    for (var i = 0; i < 6; i++) { expect(r.join(ps[i], id(i), build: i == 5 ? roles13Build - 1 : roles13Build), isNull); }
    send(r, ps[0], {'t': 'setup', 'rules': off.toJson(), 'counts': {'mafia': 2, 'detective': 1}, 'buzzMax': 3, 'mode': 'avenger'});
    send(r, ps[0], {'t': 'deal'});
    expect(ps[0].last('err')?['error'], 'old_app');
    send(r, ps[0], {'t': 'setup', 'rules': off.toJson(), 'counts': {'mafia': 1, 'detective': 0}, 'buzzMax': 3, 'mode': 'classic'});
    send(r, ps[0], {'t': 'deal'});
    expect(r.game, isNotNull, reason: 'Classic still deals with a 1.2 phone');
    // the view the host sends while the Hunter aims
    final c = createGame(Setup([for (var i = 0; i < 7; i++) 'P${i + 1}'], const Counts(2, 1, 1), off, 'avenger'), seeded(1));
    var s = c.state!..roles = [...AV7]..sheikh = 0;
    for (final a in [const Action.begin(), ...night({0: 4, 1: 4, 2: 2, 3: 0, 4: 0, 5: 0, 6: 0})]) { s = apply(s, a, Ctx(seeded(1), 1)).state!; }
    final hv = viewJson(viewFor(s, 4, 1)), tv = viewJson(viewFor(s, 2, 1));
    expect(hv['ph'], 'hunt');
    expect(hv['huntOpts'], [0, 1, 2, 3, 5, 6]);
    expect(tv['hunt'], {'seat': 4});
    expect(tv['mayors'], <int>[]);
    expect(tv['hunted'], isNull);
  });
}
