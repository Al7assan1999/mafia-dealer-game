import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'account.dart';
import 'account_screens.dart';
import 'api.dart';
import 'audio.dart';
import 'drawer.dart';
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
        builder: (context, _) { C.p = prefs.theme == 'neon' ? neonPalette : noirPalette; return MaterialApp(
          title: 'Mafia Dealer',
          debugShowCheckedModeBanner: false,
          navigatorKey: ActiveRoom.navigatorKey,
          scaffoldMessengerKey: ActiveRoom.messengerKey,
          // the room bar while minimized; a long-press opens the friends drawer with Invite ready (P4)
          builder: (context, child) => RoomBarFrame(child: child!, onLongPress: (_) {
            final ctx = ActiveRoom.navigatorKey.currentContext;
            if (ctx != null) openFriendsDrawer(ctx, account: widget.account, prefs: prefs, audio: widget.audio);
          }),
          theme: noir(),
          locale: Locale(prefs.lang),
          supportedLocales: L.supportedLocales,
          localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: Home(prefs: prefs, audio: widget.audio, account: widget.account, updater: widget.updater),
        ); },
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

  Widget _tile(BuildContext context, Key key, IconData icon, String label, Widget Function() page) => Material(
        color: C.card, shape: RoundedRectangleBorder(side: BorderSide(color: C.line), borderRadius: BorderRadius.circular(C.p.radius)),
        child: InkWell(key: key, borderRadius: BorderRadius.circular(C.p.radius), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page())),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Column(children: [
            Icon(icon, color: C.gold), const SizedBox(height: 4), Text(label, style: TextStyle(color: C.text, fontWeight: FontWeight.w700)),
          ]))),
      );

  void _play(BuildContext context, OfflineGame g) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(game: g, prefs: prefs, audio: audio, account: account)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: prefs, builder: (context, _) => _build(context));

  // an invite into the room I'm minimized in just reopens it; another room asks to leave mine first (S9-1 AC5)
  Future<void> _room(BuildContext context, String code) async {
    final a = ActiveRoom.instance;
    if (a.minimized && a.code == code) return a.reopen();
    if (!await leaveRoomFirst(context) || !context.mounted) return;
    _open(context, code);
  }
  void _open(BuildContext context, String code) =>
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
    return PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final l = L.of(context);
      if (await ask(context, l.closeAppQ, '', l.close)) SystemNavigator.pop();
    }, child: Scaffold(
      // [QA] S9 #4: Home starts at the top (centred, the icon row moved with the screen height and the friends tab hid the gear)
      body: Stack(children: [Stage(center: false, children: [
        Row(children: [
          Expanded(child: AccountBar(account: account)),
          IconButton(key: const Key('settings'), tooltip: l.settingsT, icon: Icon(Icons.settings_outlined, color: C.mute),
              onPressed: () => showModalBottomSheet(context: context, backgroundColor: C.card, isScrollControlled: true, builder: (_) => SettingsSheet(prefs: prefs, updater: updater))),
        ]),
        const SizedBox(height: 24),
        Center(
          child: Transform.rotate(
            angle: -.1,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: C.red, width: 2), borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.theater_comedy_outlined, color: C.red, size: 48),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Big(l.appName, sub: l.tag, size: 38),
        const SizedBox(height: 24),
        if (updater != null) UpdateCard(updater: updater!),
        if (!prefs.guideSeen)
          Sec(color: C.card2, child: Row(children: [
            Icon(Icons.menu_book_outlined, color: C.gold),
            const SizedBox(width: 10),
            Expanded(child: Text(l.newToMafia)),
            TextButton(key: const Key('openGuide'), onPressed: () { prefs.guideSeen = true; Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen())); },
                child: Text(l.howToPlay, style: TextStyle(color: C.red2))),
            IconButton(key: const Key('dismissGuide'), icon: Icon(Icons.close, size: 18, color: C.dim), onPressed: () => prefs.guideSeen = true),
          ])),
        const SizedBox(height: 12),
        if (saved)
          Sec(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l.resumeQ, style: TextStyle(color: C.mute)),
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
          if (!await leaveRoomFirst(context) || !context.mounted) return;
          if (saved && !await ask(context, l.discardQ, l.discardD, l.discard)) return;
          if (!context.mounted) return;
          prefs.game = null;
          final g = await Navigator.of(context).push<OfflineGame>(MaterialPageRoute(builder: (_) => SetupScreen(prefs: prefs, audio: audio, account: account)));
          if (g != null && context.mounted) _play(context, g);
        }),
        Padding(padding: const EdgeInsets.only(top: 8, bottom: 18), child: Text(l.newGameSub, textAlign: TextAlign.center, style: TextStyle(color: C.dim))),
        ListenableBuilder(listenable: account, builder: (context, _) {
          final room = account.roomCode;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (room != null && !ActiveRoom.instance.minimized) Padding(padding: const EdgeInsets.only(bottom: 10),
                child: Btn(l.backToRoom(room), key: const Key('backToRoom'), ghost: true, icon: Icons.meeting_room_outlined, onTap: () => _room(context, room))),
            if (prefs.lanHost?['code'] case final String c) Padding(padding: const EdgeInsets.only(bottom: 10), child: Btn(l.resumeHosting(c), key: const Key('resumeHosting'), ghost: true,
                icon: Icons.wifi_tethering, onTap: () async {
                  final code = await LanHost.start(prefs, restore: prefs.lanHost, title: l.hostingTitle, text: l.hostingText(c));
                  if (code != null && context.mounted) {
                    openLanRoom(context, prefs: prefs, audio: audio, account: account, address: '127.0.0.1', code: code, name: prefs.lanName, host: true);
                  }
                })),
            if (prefs.lanJoin case {'address': final String a, 'code': final String c}) Padding(padding: const EdgeInsets.only(bottom: 10), child: Btn(l.backToWifi(c),
                key: const Key('backToWifi'), ghost: true, icon: Icons.wifi, onTap: () => openLanRoom(context, prefs: prefs, audio: audio, account: account, address: a, code: c,
                    name: (prefs.lanJoin?['name'] as String?) ?? prefs.lanName))),
            Btn(l.wifi, key: const Key('wifi'), ghost: true, icon: Icons.wifi, onTap: () async => (await leaveRoomFirst(context)) && context.mounted ? Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WifiScreen(prefs: prefs, audio: audio, account: account))) : null),
            Padding(padding: const EdgeInsets.only(top: 8, bottom: 18), child: Text(l.wifiSub, textAlign: TextAlign.center, style: TextStyle(color: C.dim))),
            Btn(l.online, key: const Key('online'), ghost: true, icon: Icons.public, onTap: () async => (await leaveRoomFirst(context)) && context.mounted ? Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OnlineHome(account: account, prefs: prefs, audio: audio))) : null),
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.onlineSub, textAlign: TextAlign.center, style: TextStyle(color: C.dim))),
            if (prefs.guideSeen) Padding(padding: const EdgeInsets.only(top: 14), child: TextButton.icon(key: const Key('howToPlay'),
                icon: Icon(Icons.menu_book_outlined, color: C.mute), label: Text(l.howToPlay, style: TextStyle(color: C.mute)),
                onPressed: () { prefs.guideSeen = true; Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen())); })),
            // P1: Stats and History as two tiles (History is open to guests: their Wi-Fi games)
            Padding(padding: const EdgeInsets.only(top: 18), child: Row(children: [
              if (account.signedIn) ...[
                Expanded(child: _tile(context, const Key('stats'), Icons.leaderboard_outlined, l.statsT, () => StatsScreen(account: account))),
                const SizedBox(width: 10),
              ],
              Expanded(child: _tile(context, const Key('history'), Icons.history, l.historyT, () => HistoryScreen(account: account, prefs: prefs))),
            ])),
          ]);
        }),
      ]),
      Positioned.fill(child: SafeArea(child: FriendsTab(account: account, prefs: prefs, audio: audio))), // S9-2
      ]),
    ));
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
                  OutlinedButton(key: const Key('lang'), onPressed: () => prefs.lang = prefs.lang == 'en' ? 'ar' : 'en', child: Text(l.langSwitch, style: TextStyle(color: C.text))),
                ]),
                const SizedBox(height: 10),
                Text(l.sVoice),
                Text(l.sVoiceD, style: TextStyle(color: C.dim, fontSize: 12)),
                Slider(value: prefs.voice, onChanged: (v) => prefs.voice = v),
                Text(l.sSfx),
                Slider(value: prefs.sfx, onChanged: (v) => prefs.sfx = v),
                const SizedBox(height: 6),
                Text(l.sLook, style: head.copyWith(fontSize: 16)),
                const SizedBox(height: 8),
                Row(children: [
                  for (final (k, name, pal) in [('noir', l.sNoir, noirPalette), ('neon', l.sNeon, neonPalette)]) ...[
                    Expanded(child: _ThemeCard(key: Key('theme_$k'), name: name, p: pal, selected: prefs.theme == k, onTap: () => prefs.theme = k)),
                    if (k == 'noir') const SizedBox(width: 10),
                  ],
                ]),
                const SizedBox(height: 14),
                Text(l.sHost, style: head.copyWith(fontSize: 16)),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.sBuzz), Text(l.sBuzzD, style: TextStyle(color: C.dim, fontSize: 12)),
                  ])),
                  IconButton(key: const Key('buzzLess'), icon: Icon(Icons.remove_circle_outline, color: C.mute), onPressed: prefs.hostBuzzMax > 0 ? () => prefs.hostBuzzMax = prefs.hostBuzzMax - 1 : null),
                  Text('${prefs.hostBuzzMax}', key: const Key('buzzMax'), style: head.copyWith(fontSize: 18)),
                  IconButton(key: const Key('buzzMore'), icon: Icon(Icons.add_circle_outline, color: C.mute), onPressed: prefs.hostBuzzMax < 20 ? () => prefs.hostBuzzMax = prefs.hostBuzzMax + 1 : null),
                ]),
                // [QA] S9 #2: label above, the switch full width (side by side it overflowed in Neon / Arabic)
                Text(l.sKick),
                const SizedBox(height: 6),
                SizedBox(width: double.infinity, child: SegmentedButton<String>(key: const Key('kickMode'), showSelectedIcon: false,
                      segments: [ButtonSegment(value: 'lobby', label: Text(l.sKickLobby)), ButtonSegment(value: 'any', label: Text(l.sKickAny))],
                      selected: {prefs.hostKick}, onSelectionChanged: (s) => prefs.hostKick = s.first,
                      style: SegmentedButton.styleFrom(selectedBackgroundColor: C.red, selectedForegroundColor: C.priText, side: BorderSide(color: C.line2)))),
                const SizedBox(height: 6),
                ListTile(key: const Key('notifSettings'), contentPadding: EdgeInsets.zero, title: Text(l.sNotif),
                    subtitle: Text(l.sNotifD, style: TextStyle(color: C.dim, fontSize: 12)),
                    trailing: Icon(Icons.open_in_new, color: C.mute, size: 18), onTap: openNotificationSettings),
                if (updater != null && selfUpdate) ...[
                  SwitchListTile(key: const Key('updAlerts'), contentPadding: EdgeInsets.zero, value: prefs.updAlerts, onChanged: (v) => updater!.setAlerts(v),
                      title: Text(l.sAlerts), subtitle: Text(l.sAlertsD, style: TextStyle(color: C.dim, fontSize: 12))),
                  ListTile(key: const Key('checkUpdates'), contentPadding: EdgeInsets.zero, title: Text(l.sCheck),
                      subtitle: _checked == null ? null : Text(_checked!, key: const Key('checkResult'), style: TextStyle(color: C.gold, fontSize: 12)),
                      trailing: Icon(Icons.refresh, color: C.mute, size: 18),
                      onTap: () async {
                        await updater!.check(force: true);
                        if (!context.mounted) return;
                        if (updater!.latest != null) { Navigator.of(context).pop(); return; } // the card on Home has Update
                        setState(() => _checked = l.sUpToDate);
                      }),
                ],
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.sVersion(appVersion, appBuild), key: const Key('version'), style: TextStyle(color: C.dim, fontSize: 12))),
              ]),
            ),
          );
        },
      );
}

/// A small preview of a look (P3): its background, a primary button and a heading in its font.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({super.key, required this.name, required this.p, required this.selected, required this.onTap});
  final String name;
  final Palette p;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(p.radius),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(p.radius),
              gradient: p.neon ? const RadialGradient(center: Alignment(-.8, -1), radius: 1.2, colors: [Color(0x55FF2E63), Color(0xFF0B0A10)]) : null,
              border: Border.all(color: selected ? p.red : p.line2, width: selected ? 2 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(name, style: TextStyle(fontFamily: p.head, fontFamilyFallback: p.headFallback, color: p.text, fontSize: 18, fontWeight: p.headWeight,
                fontVariations: p.neon ? const [FontVariation('wght', 700)] : null)),
            const SizedBox(height: 8),
            Container(height: 22, decoration: BoxDecoration(color: p.neon ? null : p.red, gradient: p.neon ? neonPrimary : null, borderRadius: BorderRadius.circular(p.neon ? 11 : 3),
                boxShadow: p.neon ? null : const [BoxShadow(color: Colors.black, offset: Offset(2, 2))])),
            const SizedBox(height: 6),
            Row(children: [for (final r in p.roles.values) Expanded(child: Container(height: 6, margin: const EdgeInsets.symmetric(horizontal: 1), color: r))]),
            if (selected) Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.check_circle, color: p.red, size: 18)),
          ]),
        ),
      );
}
