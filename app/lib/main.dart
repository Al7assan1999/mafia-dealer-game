import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'audio.dart';
import 'game.dart';
import 'game_screen.dart';
import 'l10n/app_localizations.dart';
import 'prefs.dart';
import 'setup.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await Prefs.load(), audio = Audio(prefs);
  await audio.init();
  runApp(App(prefs: prefs, audio: audio));
}

class App extends StatelessWidget {
  const App({super.key, required this.prefs, required this.audio});
  final Prefs prefs;
  final Audio audio;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: prefs,
        builder: (context, _) => MaterialApp(
          title: 'Mafia Dealer',
          debugShowCheckedModeBanner: false,
          theme: noir(),
          locale: Locale(prefs.lang),
          supportedLocales: L.supportedLocales,
          localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: Home(prefs: prefs, audio: audio),
        ),
      );
}

class Home extends StatelessWidget {
  const Home({super.key, required this.prefs, required this.audio});
  final Prefs prefs;
  final Audio audio;

  void _play(BuildContext context, OfflineGame g) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(game: g, prefs: prefs, audio: audio)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: prefs, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final l = L.of(context), saved = prefs.game != null;
    return Scaffold(
      body: Stage(children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: IconButton(key: const Key('settings'), tooltip: l.settingsT, icon: const Icon(Icons.settings_outlined, color: C.mute),
              onPressed: () => showModalBottomSheet(context: context, backgroundColor: C.card, builder: (_) => SettingsSheet(prefs: prefs))),
        ),
        const SizedBox(height: 24),
        Center(
          child: Transform.rotate(
            angle: -.1,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: C.red, width: 2), borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.theater_comedy_outlined, color: C.red, size: 48),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Big(l.appName, sub: l.tag, size: 38),
        const SizedBox(height: 36),
        if (saved)
          Sec(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l.resumeQ, style: const TextStyle(color: C.mute)),
              const SizedBox(height: 12),
              Btn(l.resumeGame, key: const Key('resume'), icon: Icons.play_arrow, onTap: () {
                final g = OfflineGame.resume(prefs, audio);
                if (g != null) _play(context, g);
              }),
              const SizedBox(height: 10),
              Btn(l.discard, ghost: true, onTap: () async {
                if (await ask(context, l.discardQ, l.discardD, l.discard)) prefs.game = null;
              }),
            ]),
          ),
        Btn(l.newGame, key: const Key('newGame'), icon: Icons.groups_outlined, onTap: () async {
          if (saved && !await ask(context, l.discardQ, l.discardD, l.discard)) return;
          if (!context.mounted) return;
          prefs.game = null;
          final g = await Navigator.of(context).push<OfflineGame>(MaterialPageRoute(builder: (_) => SetupScreen(prefs: prefs, audio: audio)));
          if (g != null && context.mounted) _play(context, g);
        }),
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.newGameSub, textAlign: TextAlign.center, style: const TextStyle(color: C.dim))),
      ]),
    );
  }
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.prefs});
  final Prefs prefs;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: prefs,
        builder: (context, _) {
          final l = L.of(context);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l.settingsT, style: head.copyWith(fontSize: 22)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Text(l.language)),
                  OutlinedButton(key: const Key('lang'), onPressed: () => prefs.lang = prefs.lang == 'en' ? 'ar' : 'en', child: Text(l.langSwitch, style: const TextStyle(color: C.text))),
                ]),
                const SizedBox(height: 10),
                Text(l.sVoice),
                Text(l.sVoiceD, style: const TextStyle(color: C.dim, fontSize: 12)),
                Slider(value: prefs.voice, onChanged: (v) => prefs.voice = v),
                Text(l.sSfx),
                Slider(value: prefs.sfx, onChanged: (v) => prefs.sfx = v),
              ]),
            ),
          );
        },
      );
}
