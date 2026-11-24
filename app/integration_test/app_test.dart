// On a real Android device or emulator (CI): a whole offline game through the real app, with real audio and storage,
// then Back mid-game and a cold start from the saved data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/features/offline/game_screen.dart';
import 'package:mafia_dealer/app.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/driver.dart';

late Audio audio;

/// The end of a test: the narrator stops and the last sound effects finish, so no player is left running.
Future<void> settle(WidgetTester t) async {
  audio.stop();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 12));
}

Future<Prefs> start(WidgetTester t) async {
  final prefs = await Prefs.load();
  audio = Audio(prefs);
  await audio.init();
  await t.pumpWidget(App(prefs: prefs, audio: audio, account: Account(Api(), MemoryTokens(), prefs, live: false)));
  await t.pump(const Duration(milliseconds: 500));
  return prefs;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a whole offline game on the device', (t) async {
    await (await SharedPreferences.getInstance()).clear();
    await start(t);
    await setUpGame(t, ['Dareer', 'Halawy', 'Farouq', 'Sami', 'Hokan', 'Khaddour', 'Alhassan']);
    await playToEnd(t);
    expect(gameOf(t).s.phase, Phase.end);
    await tapKey(t, 'home');
    await waitFor(t, find.byKey(const Key('newGame')));
    expect(find.byKey(const Key('resume')), findsNothing, reason: 'a finished game is not kept');
    await settle(t);
  });

  testWidgets('Back mid-game keeps the game; a cold start resumes it at the same step', (t) async {
    await (await SharedPreferences.getInstance()).clear();
    await start(t);
    await setUpGame(t, ['Dareer', 'Halawy', 'Farouq', 'Sami', 'Hokan']);
    await tapKey(t, 'open');
    final g = gameOf(t), who = g.who, screen = g.screen;
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('Leave game'));
    await t.pump(const Duration(milliseconds: 800));
    await waitFor(t, find.byKey(const Key('resume')));
    // a cold start: the widget tree is gone and the app comes back from what's stored on the device
    await t.pumpWidget(const SizedBox());
    await start(t);
    await tapKey(t, 'resume');
    await waitFor(t, find.byType(GameScreen));
    await t.pump(const Duration(milliseconds: 500));
    expect(gameOf(t).screen, screen);
    expect(gameOf(t).who, who);
    await playToEnd(t);
    await settle(t);
  });
}
