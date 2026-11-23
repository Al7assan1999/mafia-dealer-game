import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'account.dart';
import 'account_screens.dart';
import 'api.dart';
import 'audio.dart';
import 'game.dart';
import 'guide.dart';
import 'lan/wifi_screen.dart';
import 'game_screen.dart';
import 'l10n/app_localizations.dart';
import 'online.dart';
import 'prefs.dart';
import 'push.dart';
import 'setup.dart';
import 'stats.dart';
import 'update.dart';
import 'version.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await Prefs.load(), audio = Audio(prefs), account = Account(Api(), SecureTokens(), prefs);
  await audio.init();
  account.restore(); // silently, in the background: the app never waits for the network
  final updater = Updater(prefs);
  runApp(App(prefs: prefs, audio: audio, account: account, updater: updater));
  FcmPush.start().then((p) { if (p != null) { account.push = p; updater.push = p; } }); // push stays off on a build without Firebase
  updater.check();
}

class App extends StatefulWidget {
  const App({super.key, required this.prefs, required this.audio, required this.account, this.updater});
  final Prefs prefs;
  final Audio audio;
  final Account account;
  final Updater? updater; // in-app updates (null in widget tests that don't test them)
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
    _life = AppLifecycleListener(onResume: () { widget.account.foreground(true); widget.updater?.check(); }, onPause: () => widget.account.foreground(false));
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
          home: Home(prefs: prefs, audio: widget.audio, account: widget.account, updater: widget.updater),
        ),
      );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.prefs, required this.audio, required this.account, this.updater});
  final Prefs prefs;
  final Audio audio;
  final Account account;
  final Updater? updater;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Prefs get prefs => widget.prefs;
  Audio get audio => widget.audio;
  Account get account => widget.account;
  Updater? get updater => widget.updater;

  @override
  Widget build(BuildContext context) => _HomeBody(prefs: prefs, audio: audio, account: account, updater: updater);

  @override
  void initState() {
    super.initState();
    // "Updated to vX" once, the first start of a newer build (S8-4 AC4)
    final u = updater?.takeUpdated();
    if (u != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final l = L.of(context);
        u.notes.isEmpty ? toast(context, l.updUpdated(u.version)) : notesSheet(context, l.updUpdated(u.version), u.notes);
      });
    }
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.prefs, required this.audio, required this.account, this.updater});
  final Prefs prefs;
  final Audio audio;
  final Account account;
  final Updater? updater;

  void _play(BuildContext context, OfflineGame g) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(game: g, prefs: prefs, audio: audio, account: account)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: prefs, builder: (context, _) => _build(context));

  void _room(BuildContext context, String code) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomScreen(account: account, prefs: prefs, audio: audio, code: code)));

  /// A tapped notification: an invite opens its room (or says it expired); friends open Friends; the rest the bell.
  Future<void> _openPush(BuildContext context, Map<String, String> d) async {
    final kind = d['kind'], code = d['code'];
    if ((kind == 'invite' || kind == 'let_in') && code != null) {
      final open = await account.roomOpen(code);
      if (!context.mounted) return;
      if (open) return _room(context, code);
      toast(context, L.of(context).inviteExpired);
    } else if (kind == 'update') {
      await updater?.check(force: true); // the card on Home has Update
      return;
    } else if (kind == 'friend_request' || kind == 'friend_accept') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => FriendsScreen(account: account)));
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet(context: context, backgroundColor: C.card, isScrollControlled: true, builder: (_) => BellSheet(account: account));
  }

  Widget _build(BuildContext context) {
    final l = L.of(context), saved = prefs.game != null;
    account.openRoom = (code) => _room(context, code); // the bell opens invites with it
    account.onPushOpen = (d) => _openPush(context, d);
    return Scaffold(
      body: Stage(children: [
        Row(children: [
          Expanded(child: AccountBar(account: account)),
          IconButton(key: const Key('settings'), tooltip: l.settingsT, icon: const Icon(Icons.settings_outlined, color: C.mute),
              onPressed: () => showModalBottomSheet(context: context, backgroundColor: C.card, isScrollControlled: true, builder: (_) => SettingsSheet(prefs: prefs, updater: updater))),
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
        if (updater != null) UpdateCard(updater: updater!),
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
            if (prefs.lanHost?['code'] case final String c) Padding(padding: const EdgeInsets.only(bottom: 10), child: Btn(l.resumeHosting(c), key: const Key('resumeHosting'),
                icon: Icons.wifi_tethering, onTap: () async {
                  final code = await LanHost.start(prefs, restore: prefs.lanHost, title: l.hostingTitle, text: l.hostingText(c));
                  if (code != null && context.mounted) {
                    openLanRoom(context, prefs: prefs, audio: audio, account: account, address: '127.0.0.1', code: code, name: prefs.lanName, host: true);
                  }
                })),
            if (prefs.lanJoin case {'address': final String a, 'code': final String c}) Padding(padding: const EdgeInsets.only(bottom: 10), child: Btn(l.backToWifi(c),
                key: const Key('backToWifi'), icon: Icons.wifi, onTap: () => openLanRoom(context, prefs: prefs, audio: audio, account: account, address: a, code: c,
                    name: (prefs.lanJoin?['name'] as String?) ?? prefs.lanName))),
            Btn(l.wifi, key: const Key('wifi'), ghost: true, icon: Icons.wifi, onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WifiScreen(prefs: prefs, audio: audio, account: account)))),
            Padding(padding: const EdgeInsets.only(top: 8, bottom: 18), child: Text(l.wifiSub, textAlign: TextAlign.center, style: const TextStyle(color: C.dim))),
            Btn(l.online, key: const Key('online'), ghost: true, icon: Icons.public, onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OnlineHome(account: account, prefs: prefs, audio: audio)))),
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.onlineSub, textAlign: TextAlign.center, style: const TextStyle(color: C.dim))),
            if (prefs.guideSeen) Padding(padding: const EdgeInsets.only(top: 14), child: TextButton.icon(key: const Key('howToPlay'),
                icon: const Icon(Icons.menu_book_outlined, color: C.mute), label: Text(l.howToPlay, style: const TextStyle(color: C.mute)),
                onPressed: () { prefs.guideSeen = true; Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen())); })),
            if (account.signedIn) Padding(padding: const EdgeInsets.only(top: 4), child: TextButton.icon(key: const Key('stats'),
                icon: const Icon(Icons.leaderboard_outlined, color: C.mute), label: Text(l.statsT, style: const TextStyle(color: C.mute)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatsScreen(account: account))))),
            Padding(padding: const EdgeInsets.only(top: 4), child: TextButton.icon(key: const Key('history'), // Wi-Fi games are kept for guests too
                icon: const Icon(Icons.history, color: C.mute), label: Text(l.historyT, style: const TextStyle(color: C.mute)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryScreen(account: account, prefs: prefs))))),
          ]);
        }),
      ]),
    );
  }
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.prefs, this.updater});
  final Prefs prefs;
  final Updater? updater;
  @override
  State<SettingsSheet> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsSheet> {
  Prefs get prefs => widget.prefs;
  Updater? get updater => widget.updater;
  String? _checked; // the answer to "Check for updates", shown in the sheet ([QA] S8 #7)

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: prefs,
        builder: (context, _) {
          final l = L.of(context);
          return SafeArea(
            child: SingleChildScrollView( // [QA] S7: with the Notifications row it outgrew a 640 px phone's sheet
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
                ListTile(key: const Key('notifSettings'), contentPadding: EdgeInsets.zero, title: Text(l.sNotif),
                    subtitle: Text(l.sNotifD, style: const TextStyle(color: C.dim, fontSize: 12)),
                    trailing: const Icon(Icons.open_in_new, color: C.mute, size: 18), onTap: openNotificationSettings),
                if (updater != null && selfUpdate) ...[
                  SwitchListTile(key: const Key('updAlerts'), contentPadding: EdgeInsets.zero, value: prefs.updAlerts, onChanged: (v) => updater!.setAlerts(v),
                      title: Text(l.sAlerts), subtitle: Text(l.sAlertsD, style: const TextStyle(color: C.dim, fontSize: 12))),
                  ListTile(key: const Key('checkUpdates'), contentPadding: EdgeInsets.zero, title: Text(l.sCheck),
                      subtitle: _checked == null ? null : Text(_checked!, key: const Key('checkResult'), style: const TextStyle(color: C.gold, fontSize: 12)),
                      trailing: const Icon(Icons.refresh, color: C.mute, size: 18),
                      onTap: () async {
                        await updater!.check(force: true);
                        if (!context.mounted) return;
                        if (updater!.latest != null) { Navigator.of(context).pop(); return; } // the card on Home has Update
                        setState(() => _checked = l.sUpToDate);
                      }),
                ],
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.sVersion(appVersion, appBuild), key: const Key('version'), style: const TextStyle(color: C.dim, fontSize: 12))),
              ]),
            ),
          );
        },
      );
}
