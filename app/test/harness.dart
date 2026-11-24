// What every widget test needs: real fonts, a fake clock, silent audio, and the app at a phone size with a fake server.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/app.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

var fakeNow = 1_000_000_000;

Future<void> setUpHarness() async {
  Audio.silent = true;
  OfflineGame.clock = () => fakeNow;
  for (final (family, files) in [
    ('Plex', ['IBMPlexSansArabic-Regular.ttf', 'IBMPlexSansArabic-Bold.ttf']),
    ('Elite', ['SpecialElite-Regular.ttf']),
    ('Messiri', ['ElMessiri-Variable.ttf']),
    ('Readex', ['ReadexPro-Variable.ttf']),
  ]) {
    final l = FontLoader(family);
    for (final f in files) { l.addFont(rootBundle.load('assets/fonts/$f')); }
    await l.load();
  }
}

class Launched {
  Launched(this.prefs, this.account, this.server);
  final Prefs prefs;
  final Account account;
  final FakeServer server;
}

/// The app on a phone of this size, with fresh (or the given) saved data and a fake server.
Future<Launched> launch(WidgetTester t, {Size size = const Size(393, 851), String lang = 'en', double text = 1, Prefs? prefs,
    FakeServer? server, TokenStore? tokens, FakeGoogle? google, Map<String, Object> stored = const {}}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(() { t.view.reset(); t.platformDispatcher.clearTextScaleFactorTestValue(); });
  if (prefs == null) {
    SharedPreferences.setMockInitialValues({'lang': lang, ...stored});
    prefs = await Prefs.load();
  }
  server ??= FakeServer();
  final audio = Audio(prefs), account = Account(server.api(), tokens ?? MemoryTokens(), prefs, google: google ?? FakeGoogle(), live: false);
  await t.runAsync(audio.init);
  await t.runAsync(account.restore);
  await t.pumpWidget(App(prefs: prefs, audio: audio, account: account));
  await t.pump();
  return Launched(prefs, account, server);
}
