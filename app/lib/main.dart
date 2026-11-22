import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'account.dart';
import 'account_screens.dart';
import 'api.dart';
import 'audio.dart';
import 'game.dart';
import 'guide.dart';
import 'game_screen.dart';
import 'l10n/app_localizations.dart';
import 'online.dart';
import 'prefs.dart';
import 'setup.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await Prefs.load(), audio = Audio(prefs), account = Account(Api(), SecureTokens(), prefs);
  await audio.init();
  account.restore(); // silently, in the background: the app never waits for the network
  runApp(App(prefs: prefs, audio: audio, account: account));
}

class App extends StatefulWidget {
  const App({super.key, required this.prefs, required this.audio, required this.account});
  final Prefs prefs;
  final Audio audio;
  final Account account;
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  // the hub socket only while the app is on screen
  late final AppLifecycleListener _life;
  Prefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: () => widget.account.foreground(true), onPause: () => widget.account.foreground(false));
  }
  @override
  void dispose() { _life.dispose(); super.dispose(); }

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
          home: Home(prefs: prefs, audio: widget.audio, account: widget.account),
        ),
      );
}

class Home extends StatelessWidget {
  const Home({super.key, required this.prefs, required this.audio, required this.account});
  final Prefs prefs;
  final Audio audio;
  final Account account;

  void _play(BuildContext context, OfflineGame g) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(game: g, prefs: prefs, audio: audio, account: account)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: prefs, builder: (context, _) => _build(context));

  void _room(BuildContext context, String code) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomScreen(account: account, prefs: prefs, audio: audio, code: code)));

  Widget _build(BuildContext context) {
    final l = L.of(context), saved = prefs.game != null;
    account.openRoom = (code) => _room(context, code); // the bell opens invites with it
    return Scaffold(
      body: Stage(children: [
        Row(children: [
          Expanded(child: AccountBar(account: account)),
          IconButton(key: const Key('settings'), tooltip: l.settingsT, icon: const Icon(Icons.settings_outlined, color: C.mute),
              onPressed: () => showModalBottomSheet(context: context, backgroundColor: C.card, builder: (_) => SettingsSheet(prefs: prefs))),
        ]),
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
        const SizedBox(height: 24),
        if (!prefs.guideSeen)
          Sec(color: C.card2, child: Row(children: [
            const Icon(Icons.menu_book_outlined, color: C.gold),
            const SizedBox(width: 10),
            Expanded(child: Text(l.newToMafia)),
            TextButton(key: const Key('openGuide'), onPressed: () { prefs.guideSeen = true; Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen())); },
                child: Text(l.howToPlay, style: const TextStyle(color: C.red2))),
            IconButton(key: const Key('dismissGuide'), icon: const Icon(Icons.close, size: 18, color: C.dim), onPressed: () => prefs.guideSeen = true),
          ])),
        const SizedBox(height: 12),
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
          final g = await Navigator.of(context).push<OfflineGame>(MaterialPageRoute(builder: (_) => SetupScreen(prefs: prefs, audio: audio, account: account)));
          if (g != null && context.mounted) _play(context, g);
        }),
        Padding(padding: const EdgeInsets.only(top: 8, bottom: 18), child: Text(l.newGameSub, textAlign: TextAlign.center, style: const TextStyle(color: C.dim))),
        ListenableBuilder(listenable: account, builder: (context, _) {
          final room = account.roomCode;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (room != null) Padding(padding: const EdgeInsets.only(bottom: 10),
                child: Btn(l.backToRoom(room), key: const Key('backToRoom'), icon: Icons.meeting_room_outlined, onTap: () => _room(context, room))),
            Btn(l.online, key: const Key('online'), ghost: true, icon: Icons.public, onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OnlineHome(account: account, prefs: prefs, audio: audio)))),
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.onlineSub, textAlign: TextAlign.center, style: const TextStyle(color: C.dim))),
            Padding(padding: const EdgeInsets.only(top: 14), child: TextButton.icon(key: const Key('howToPlay'),
                icon: const Icon(Icons.menu_book_outlined, color: C.mute), label: Text(l.howToPlay, style: const TextStyle(color: C.mute)),
                onPressed: () { prefs.guideSeen = true; Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen())); })),
            if (account.signedIn) Padding(padding: const EdgeInsets.only(top: 4), child: TextButton.icon(key: const Key('history'),
                icon: const Icon(Icons.history, color: C.mute), label: Text(l.historyT, style: const TextStyle(color: C.mute)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryScreen(account: account))))),
          ]);
        }),
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
