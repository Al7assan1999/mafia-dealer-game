import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mafia_dealer/features/feedback/feedback_screen.dart';
import 'package:mafia_dealer/features/home/home_footer.dart';
import 'package:flutter/services.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/friends/friends_drawer.dart';
import 'package:mafia_dealer/features/friends/friends_screen.dart';
import 'package:mafia_dealer/features/guide/guide_screen.dart';
import 'package:mafia_dealer/features/history/history_screen.dart';
import 'package:mafia_dealer/features/account/sign_in_screen.dart';
import 'package:mafia_dealer/features/home/account_bar.dart';
import 'package:mafia_dealer/features/home/best_line.dart';
import 'package:mafia_dealer/features/intro/intro_screen.dart';
import 'package:mafia_dealer/features/notifications/bell_sheet.dart';
import 'package:mafia_dealer/features/offline/game_screen.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/features/offline/setup_screen.dart';
import 'package:mafia_dealer/features/online/online_home.dart';
import 'package:mafia_dealer/features/room/room_bar.dart';
import 'package:mafia_dealer/features/room/room_screen.dart';
import 'package:mafia_dealer/features/settings/settings_sheet.dart';
import 'package:mafia_dealer/features/stats/stats_screen.dart';
import 'package:mafia_dealer/features/update/updater.dart';
import 'package:mafia_dealer/features/update/whats_new.dart';
import 'package:mafia_dealer/features/wifi/wifi_screen.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

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
    // the intro (S10-2): once on the first launch, later only with Settings → Show the intro at start; once per run
    if (!IntroScreen.ran && (!prefs.introSeen || prefs.introAtStart)) {
      IntroScreen.ran = true;
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) showIntro(context, prefs, first: !prefs.introSeen); });
    }
    // "Updated to vX" once, the first start of a newer build (S8-4 AC4)
    final u = updater?.takeUpdated();
    if (u != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final l = L.of(context);
        // [S14-4] as the old app: What's new opens by itself once, this version marked Installed; offline, the short line
        updater!.releases().then((r) { if (!mounted) return; r.isEmpty && u.notes.isEmpty ? toast(context, l.updUpdated(u.version)) : whatsNewSheet(context, updater!, fallback: u.notes); });
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

  // the old .row3 tile: a bold label, a count under it when there is one
  Widget _tile(BuildContext context, Key key, String label, int? count, Widget Function() page, {VoidCallback? before}) => Material(
        color: C.card, shape: RoundedRectangleBorder(side: BorderSide(color: C.line), borderRadius: BorderRadius.circular(C.neon ? 18 : 3)),
        child: InkWell(key: key, borderRadius: BorderRadius.circular(C.neon ? 18 : 3), onTap: () { before?.call(); Navigator.of(context).push(MaterialPageRoute(builder: (_) => page())); },
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: C.text, fontWeight: FontWeight.w700, fontSize: 14)),
            if (count != null) Text('$count', key: const Key('historyCount'), style: TextStyle(color: C.mute, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]))),
      );

  /// [his look note] the old app's mode card: an icon box, the title in the heading font, the line under it inside the card.
  Widget _mode(Key key, IconData icon, String title, String sub, VoidCallback onTap, {bool primary = false}) {
    final r = BorderRadius.circular(C.p.radius), fg = primary ? C.priText : C.text;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Container(
      decoration: BoxDecoration(color: primary ? (C.neon ? null : C.red) : C.card, gradient: primary && C.neon ? neonPrimary : null, borderRadius: r,
          border: primary ? null : Border.all(color: C.line),
          boxShadow: primary ? [C.neon ? const BoxShadow(color: Color(0x45FF2E63), blurRadius: 26, offset: Offset(0, 10)) : const BoxShadow(color: Colors.black, offset: Offset(3, 3))] : null),
      child: Material(type: MaterialType.transparency, child: InkWell(key: key, borderRadius: r, onTap: onTap, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: primary ? const Color(0x33000000) : C.card2, borderRadius: BorderRadius.circular(C.neon ? 12 : 3)),
            child: Icon(icon, color: fg, size: 24)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.replaceAll('‑', '-'), style: head.copyWith(fontSize: 19, height: 1.25, color: fg)), // the typewriter has no non-breaking hyphen
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 13.5, height: 1.4, color: fg.withValues(alpha: .78))),
        ])),
      ])))),
    ));
  }

  void _play(BuildContext context, OfflineGame g) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(game: g, prefs: prefs, audio: audio, account: account)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: prefs, builder: (context, _) => _build(context));

  // an invite into the room I'm minimized in just reopens it; another room asks to leave mine first (S9-1 AC5)
  Future<void> _room(BuildContext context, String code) async {
    IntroScreen.stop(); // S10-2 AC4
    final a = ActiveRoom.instance;
    if (a.minimized && a.code == code) return a.reopen();
    if (!await leaveRoomFirst(context) || !context.mounted) return;
    _open(context, code);
  }
  void _open(BuildContext context, String code) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomScreen(account: account, prefs: prefs, audio: audio, code: code)));

  /// A tapped notification: an invite opens its room (or says it expired); friends open Friends; the rest the bell.
  Future<void> _openPush(BuildContext context, Map<String, String> d) async {
    IntroScreen.stop(); // S10-2 AC4
    final kind = d['kind'], code = d['code'];
    if ((kind == 'invite' || kind == 'let_in') && code != null) {
      final open = await account.roomOpen(code);
      if (!context.mounted) return;
      if (open) return _room(context, code);
      toast(context, L.of(context).inviteExpired);
    } else if (kind == 'update') {
      await updater?.check(force: true); // the card on Home has Update
      return;
    } else if (kind == 'feedback_done' && account.signedIn) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => FeedbackScreen(account: account)));
      return; // [Quin Q3] not the bell on top of it
    } else if (kind == 'friend_request' || kind == 'friend_accept') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => FriendsScreen(account: account)));
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet(context: context, backgroundColor: C.card, isScrollControlled: true, useSafeArea: true, builder: (_) => BellSheet(account: account));
  }

  Widget _build(BuildContext context) {
    final l = L.of(context), saved = prefs.game != null;
    account.openRoom = (code) { // the bell opens invites with it; a let-in opens by itself (S13-4)
      final who = account.letIn.value;
      if (who != null) { account.letIn.value = null; toast(context, L.of(context).letYouIn(who)); }
      _room(context, code);
    };
    account.onPushOpen = (d) => _openPush(context, d);
    return PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final l = L.of(context);
      if (await ask(context, l.closeAppQ, '', l.close)) SystemNavigator.pop();
    }, child: Scaffold(
      // [QA] S9 #4: Home starts at the top (centred, the icon row moved with the screen height and the friends tab hid the gear)
      body: Stack(children: [Stage(center: false, children: [
        AccountBar(account: account,
            onSettings: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsSheet(prefs: prefs, updater: updater, account: account)))),
        const SizedBox(height: 36),
        const Center(child: HomeLogo()), // [S14-3] the old app's mark
        const SizedBox(height: 22),
        Big(l.appName, sub: l.tag, size: 38),
        const SizedBox(height: 24),
        if (updater != null) UpdateCard(updater: updater!),
        if (!prefs.guideSeen)
          ValueListenableBuilder(valueListenable: guideGlow, builder: (context, glow, child) => AnimatedContainer(
              key: Key(glow ? 'guideGlow' : 'guideOffer'), duration: const Duration(milliseconds: 600),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(C.p.radius + 2),
                  boxShadow: glow ? [BoxShadow(color: C.gold.withValues(alpha: .55), blurRadius: 18, spreadRadius: 1)] : const []),
              child: child), child: Sec(color: C.card2, child: Row(children: [
            Icon(Icons.menu_book_outlined, color: C.gold),
            const SizedBox(width: 10),
            Expanded(child: Text(l.newToMafia)),
            Flexible(child: TextButton(key: const Key('openGuide'), onPressed: () { prefs.guideSeen = true; Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuideScreen(prefs: prefs))); },
                child: Text(l.howToPlay, style: TextStyle(color: C.red2)))),
            IconButton(key: const Key('dismissGuide'), visualDensity: VisualDensity.compact, icon: Icon(Icons.close, size: 18, color: C.dim), onPressed: () => prefs.guideSeen = true),
          ]))),
        const SizedBox(height: 12),
        // [S14-3] as the old app: a gold "Resume game · Round N" and a small Discard link (it was a card)
        if (saved) ...[
          Btn('${l.resumeGame} · ${l.roundN(prefs.game?['day'] as int? ?? 1)}', key: const Key('resume'), gold: true, onTap: () {
            final g = OfflineGame.resume(prefs, audio);
            if (g != null) _play(context, g);
          }),
          Center(child: TextButton(key: const Key('discard'), onPressed: () async {
            if (await ask(context, l.discardQ, l.discardD, l.discard)) prefs.game = null;
          }, child: Text(l.discard, style: TextStyle(color: C.mute)))),
          const SizedBox(height: 6),
        ],
        _mode(const Key('newGame'), Icons.smartphone_outlined, l.newGame, l.newGameSub, primary: true, () async {
          if (!await leaveRoomFirst(context) || !context.mounted) return;
          if (saved && !await ask(context, l.discardQ, l.discardD, l.discard)) return;
          if (!context.mounted) return;
          prefs.game = null;
          final g = await Navigator.of(context).push<OfflineGame>(MaterialPageRoute(builder: (_) => SetupScreen(prefs: prefs, audio: audio, account: account)));
          if (g != null && context.mounted) _play(context, g);
        }),
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
            _mode(const Key('wifi'), Icons.wifi, l.wifi, l.wifiSub, () async => (await leaveRoomFirst(context)) && context.mounted ? Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WifiScreen(prefs: prefs, audio: audio, account: account))) : null),
            _mode(const Key('online'), Icons.public, l.online, l.onlineSub, () async => (await leaveRoomFirst(context)) && context.mounted ? Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OnlineHome(account: account, prefs: prefs, audio: audio))) : null),
            // [S14-3 / his #3] as the old app: Game History (its count), Player Stats, How to Play; then the best player
            IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _tile(context, const Key('history'), l.historyT, account.signedIn ? prefs.homeGames : null, () => HistoryScreen(account: account, prefs: prefs))),
              const SizedBox(width: 8),
              Expanded(child: _tile(context, const Key('stats'), l.homeStats, null, () => account.signedIn ? StatsScreen(account: account) : SignInScreen(account: account))),
              const SizedBox(width: 8),
              Expanded(child: _tile(context, const Key('howToPlay'), l.howToPlay, null, () => GuideScreen(prefs: prefs), before: () => prefs.guideSeen = true)),
            ])),
            BestLine(account: account, prefs: prefs),
            if (updater != null) HomeFooter(updater: updater!), // S13-5
          ]);
        }),
      ]),
      Positioned.fill(child: SafeArea(child: FriendsTab(account: account, prefs: prefs, audio: audio, extra: RoomChatButton(account: account)))), // S9-2, R1
      ]),
    ));
  }
}
