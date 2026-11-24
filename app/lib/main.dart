import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mafia_dealer/app.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/push.dart';
import 'package:mafia_dealer/features/update/updater.dart';
import 'package:mafia_dealer/state/account.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await Prefs.load(), audio = Audio(prefs), account = Account(Api(), SecureTokens(), prefs);
  prefs.firstLaunch(); // a brand-new install hasn't seen the intro; an update counts as seen (S10-2 AC5)
  await audio.init();
  account.restore(); // silently, in the background: the app never waits for the network
  final updater = Updater(prefs);
  runApp(App(prefs: prefs, audio: audio, account: account, updater: updater));
  FcmPush.start().then((p) { if (p != null) { account.push = p; updater.push = p; } }); // push stays off on a build without Firebase
  updater.check();
  updater.cleanup(); // S13-5: the downloaded update file, once the new version runs
}
