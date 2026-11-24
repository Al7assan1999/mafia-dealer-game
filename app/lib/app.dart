import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/friends/friends_drawer.dart';
import 'package:mafia_dealer/features/home/home_screen.dart';
import 'package:mafia_dealer/features/notifications/note_banner.dart';
import 'package:mafia_dealer/features/room/buzz.dart';
import 'package:mafia_dealer/features/room/room_bar.dart';
import 'package:mafia_dealer/features/update/updater.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

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
          // [his look note] Android's "Bold text" made every line bold; the old app (a web view) ignored it, and he wants
          // its look. ponytail: ignores that accessibility setting app-wide; follow it again if a player asks.
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(boldText: false), child: Stack(children: [
            RoomBarFrame(child: child!, onLongPress: (_) {
              final ctx = ActiveRoom.navigatorKey.currentContext;
              if (ctx != null) openFriendsDrawer(ctx, account: widget.account, prefs: prefs, audio: widget.audio);
            }),
            NoteBanner(account: widget.account), // N5: an invite or a request pops up while the app is open
            const Positioned.fill(child: BuzzFlash()), // R7
          ])),
          theme: noir(),
          locale: Locale(prefs.lang),
          supportedLocales: L.supportedLocales,
          localizationsDelegates: const [L.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: Home(prefs: prefs, audio: widget.audio, account: widget.account, updater: widget.updater),
        ); },
      );
}
