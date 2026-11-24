// The offline game through the real UI: whole games at three phone sizes, in English and Arabic, at 1.3x text, plus
// the adversarial cases (double taps, the role card in the background, Back, killing the app, the timers).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/features/offline/game_screen.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_engine/mafia_engine.dart';

import 'driver.dart';
import 'harness.dart';

Map<String, Object?> jsonDecodeRecord(GameRecord r) => jsonDecode(jsJson(r.toJson())) as Map<String, Object?>;

const names6 = ['Dareer', 'Halawy', 'Farouq', 'Sami', 'Hokan', 'Khaddour'];
void main() {
  setUpAll(setUpHarness);

  for (final size in const [Size(360, 640), Size(393, 851), Size(412, 915)]) {
    for (final lang in ['en', 'ar']) {
      for (final text in [1.0, 1.3]) {
        testWidgets('a whole game: ${size.width.toInt()}x${size.height.toInt()}, $lang, text x$text', (t) async {
          await launch(t, size: size, lang: lang, text: text);
          expect(Directionality.of(t.element(find.byKey(const Key('newGame')))), lang == 'ar' ? TextDirection.rtl : TextDirection.ltr);
          await setUpGame(t, size.width == 360 ? names6.take(4).toList() : names6);
          final screens = await playToEnd(t);
          expect(screens, greaterThan(10));
          expect(gameOf(t).s.phase, Phase.end);
          await tapKey(t, 'home'); // leaving a finished game (this once threw while the screen closed)
          await waitFor(t, find.byKey(const Key('newGame')));
          await t.pump(const Duration(milliseconds: 400));
          expect(find.byKey(const Key('resume')), findsNothing, reason: 'a finished game is not kept');
        });
      }
    }
  }

  testWidgets('the setup refuses what the rules refuse', (t) async {
    await launch(t);
    await tapKey(t, 'newGame');
    await waitFor(t, find.byKey(const Key('name0')));
    await t.pump(const Duration(milliseconds: 400));
    await t.enterText(find.byKey(const Key('name0')), 'Sami');
    await t.enterText(find.byKey(const Key('name1')), ' sami ');
    await t.pump();
    expect(find.text('Two players have the same name'), findsOneWidget);
    expect(find.byKey(const Key('deal')), findsOneWidget);
    await t.enterText(find.byKey(const Key('name1')), 'Hokan');
    for (var i = 5; i >= 3; i--) { await tapKey(t, 'remove$i'); }
    expect(find.text('Need at least 4 players'), findsOneWidget);
    await tapKey(t, 'addPlayer');
    expect(find.text('Need at least 4 players'), findsNothing);
    // 4 players: never more than 1 Mafia, never a Detective
    await tapKey(t, 'plus_mafia');
    expect(t.widget<Text>(find.byKey(const Key('count_mafia'))).data, '1');
  });

  testWidgets('double taps never skip a player or act twice', (t) async {
    await launch(t);
    await setUpGame(t, names6);
    final g = gameOf(t);
    await tapKey(t, 'open');
    final hold = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
    await t.pump(const Duration(milliseconds: 200));
    await hold.up();
    await t.pump();
    await t.tap(find.byKey(const Key('memorized')));
    await t.tap(find.byKey(const Key('memorized')), warnIfMissed: false);
    await t.pump();
    expect(g.screen, Screen.dealPass);
    expect(g.who, 1, reason: 'one player on, not two');
    await t.tap(find.byKey(const Key('open')));
    await t.tap(find.byKey(const Key('open')), warnIfMissed: false);
    await t.pump();
    expect(g.screen, Screen.dealCard);
    expect(g.who, 1);
  });

  testWidgets('a whole game tapping every button twice: nobody is skipped, nothing happens twice', (t) async {
    await launch(t);
    await setUpGame(t, names6);
    seen.clear();
    doubleTaps = true;
    addTearDown(() => doubleTaps = false);
    await playToEnd(t);
    final g = gameOf(t);
    // every player saw their role card, in seat order
    expect([for (final (sc, w) in seen) if (sc == Screen.dealCard) w], [0, 1, 2, 3, 4, 5]);
    // every night, each player alive at dusk had exactly one turn; every ballot, one vote each
    final nights = g.rec.actions.where((a) => a.a.t == 'night').length, picks = seen.where((x) => x.$1 == Screen.nightPick).length;
    expect(picks, nights);
    final votes = g.rec.actions.where((a) => a.a.t == 'vote').length, casts = seen.where((x) => x.$1 == Screen.ballotPick).length;
    expect(casts, votes);
    final r = replay(jsonDecodeRecord(g.rec));
    expect(r.error, isNull);
  });

  testWidgets('the role card hides when the app goes to the background, and the button waits for a look', (t) async {
    await launch(t);
    await setUpGame(t, names6);
    await tapKey(t, 'open');
    expect(t.widget<Opacity>(find.ancestor(of: find.text('Got it — hide & pass'), matching: find.byType(Opacity)).first).opacity, lessThan(1));
    final hold = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
    await t.pump();
    expect(find.byKey(const Key('roleName')), findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    expect(find.byKey(const Key('roleName')), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await hold.up();
  });

  testWidgets('Back asks before leaving; the game is kept and resumes at the same step after the app is killed', (t) async {
    final prefs = (await launch(t)).prefs;
    await setUpGame(t, names6);
    for (var i = 0; i < 6; i++) {
      await tapKey(t, 'open');
      final hold = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
      await t.pump(const Duration(milliseconds: 100));
      await hold.up();
      await t.pump();
      await tapKey(t, 'memorized');
    }
    final g = gameOf(t);
    await tapKey(t, 'open');
    expect(g.screen, Screen.nightPick);
    final who = g.who, record = g.rec.toJson();
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.text('Leave this game?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pump(const Duration(milliseconds: 400));
    expect(gameOf(t).screen, Screen.nightPick, reason: 'Cancel stays in the game');
    // the app is killed: a new start from the saved data only
    await t.pumpWidget(const SizedBox());
    final again = await Prefs.load();
    await launch(t, prefs: again);
    await tapKey(t, 'resume');
    await waitFor(t, find.byType(GameScreen));
    await t.pump(const Duration(milliseconds: 400));
    final r = gameOf(t);
    expect(r.screen, Screen.nightPick);
    expect(r.who, who);
    expect(jsJson(r.rec.toJson()), jsJson(record));
    expect(prefs.game, isNotNull);
    await playToEnd(t);
  });

  testWidgets('the discussion timer: start, pause, +1 minute, reset, and time up', (t) async {
    await launch(t);
    await setUpGame(t, names6);
    final g = gameOf(t);
    while (g.screen != Screen.day) {
      switch (g.screen) {
        case Screen.dealCard:
          final hold = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
          await t.pump(const Duration(milliseconds: 100));
          await hold.up();
          await t.pump();
          await tapKey(t, 'memorized');
        case Screen.nightPick:
          final no = g.view(g.who).night!;
          if (no.key != 'none') await tapKey(t, 'opt_${no.opts.firstWhere((o) => !o.disabled).seat}');
          await tapKey(t, 'confirm');
        case Screen.morning:
          await tapKey(t, g.revealed ? 'startDay' : 'revealNow');
        case Screen.nightLocked: await tapKey(t, 'nightNext');
        case Screen.dawn: await tapKey(t, 'dawn');
        default: await tapKey(t, 'open');
      }
      if (g.s.phase == Phase.end) return; // rare: the first night decided it
    }
    String clock() => t.widget<Text>(find.byKey(const Key('clock'))).data!;
    expect(clock(), '3:00');
    await tapKey(t, 'timerGo');
    fakeNow += 65000;
    await t.pump(const Duration(seconds: 1));
    expect(clock(), '1:55');
    await tapKey(t, 'timerGo'); // pause
    fakeNow += 30000;
    await t.pump(const Duration(seconds: 1));
    expect(clock(), '1:55');
    await tapKey(t, 'timerAdd');
    await t.pump(const Duration(seconds: 1));
    expect(clock(), '2:55');
    await tapKey(t, 'timerReset');
    await t.pump(const Duration(seconds: 1));
    expect(clock(), '3:00');
    await tapKey(t, 'timerGo');
    fakeNow += 200000;
    await t.pump(const Duration(seconds: 1));
    expect(clock(), 'Time is up');
  });

  testWidgets('the night timer skips the turns not taken', (t) async {
    await launch(t);
    await tapKey(t, 'newGame');
    await waitFor(t, find.byKey(const Key('deal')));
    await t.pump(const Duration(milliseconds: 400));
    await t.ensureVisible(find.byKey(const Key('rulesToggle'))); // S13-2: the rules are a folded card
    await tapKey(t, 'rulesToggle');
    await t.pump(const Duration(milliseconds: 400));
    final chip = find.text('30 s');
    await t.ensureVisible(chip);
    await t.tap(chip);
    await t.pump();
    await tapKey(t, 'deal');
    await waitFor(t, find.byKey(const Key('open')));
    final g = gameOf(t);
    while (g.screen != Screen.nightPass) {
      await tapKey(t, 'open');
      final hold = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
      await t.pump(const Duration(milliseconds: 100));
      await hold.up();
      await t.pump();
      await tapKey(t, 'memorized');
    }
    expect(find.byKey(const Key('nightClock')), findsOneWidget);
    await tapKey(t, 'open'); // the first player is choosing when time runs out
    fakeNow += 31000;
    await t.pump(const Duration(seconds: 31));
    expect(g.screen, Screen.dawn);
    expect(g.s.phase, isNot(Phase.night));
  });

  testWidgets('the language switch mirrors the layout and is remembered', (t) async {
    final prefs = (await launch(t)).prefs;
    await tapKey(t, 'settings');
    await tapKey(t, 'lang_ar'); // [look] Settings is a page with the old English / العربية choice
    await t.pump(const Duration(milliseconds: 300));
    expect(prefs.lang, 'ar');
    await tapKey(t, 'closeSettings');
    await t.pump(const Duration(milliseconds: 600));
    expect(Directionality.of(t.element(find.byKey(const Key('newGame')))), TextDirection.rtl);
    expect(find.text('لعبة بدون إنترنت'), findsOneWidget);
  });
}
