import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mafia_dealer/state/room_conn.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

// ---------------------------------------------------------------- minimize (S9-1)
/// The room this phone stays in while it goes Home from the lobby: the connection outlives the room screen. The room bar
/// leads back; dealing the roles pulls the player back; a kick or a closed room is told on whatever screen is open.
class ActiveRoom extends ChangeNotifier {
  ActiveRoom._();
  static final instance = ActiveRoom._();
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  RoomConn? conn;
  String code = '';
  bool lanHost = false, lan = false;
  Widget Function(RoomConn c)? _reopen; // the same room screen again, on the same connection
  VoidCallback? _onLeave; // Wi-Fi host: stop the server when the room is left for good
  StreamSubscription<Map<String, Object?>>? _side;
  bool get minimized => conn != null;

  /// [alert] tells the player about a buzz or a ping while away (the room screen passes its own: vibration, sound, flash).
  void hold(RoomConn c, String code, Widget Function(RoomConn c) reopen, {bool lanHost = false, bool lan = false, VoidCallback? onLeave,
      void Function(Map<String, Object?> m)? alert}) {
    conn = c; this.code = code; this.lanHost = lanHost; this.lan = lan; _reopen = reopen; _onLeave = onLeave;
    c.addListener(_watch);
    // [R7] a buzz or a ping reaches me on Home too (the old app's minimized room did the same)
    _side = c.side.listen((m) {
      final ctx = navigatorKey.currentContext;
      if (m['t'] != 'buzz' && m['t'] != 'ping') return;
      if (ctx == null || !ctx.mounted) return;
      final l = L.of(ctx), who = c.members.where((x) => x['uid'] == m['from']).firstOrNull?['display'] as String?;
      alert?.call(m);
      // [1.1.1 hotfix] a new buzz replaces the last one (they used to queue, 4 s each), and goes in 2.5 s
      messengerKey.currentState?..hideCurrentSnackBar()..showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500),
          content: Text(m['t'] == 'buzz' ? l.buzzed(who ?? '?') : l.pingedYou)));
    });
    notifyListeners();
  }

  void _watch() {
    final c = conn;
    if (c == null) return;
    final ctx = navigatorKey.currentContext;
    if (c.bye != null) { // kicked or closed while away: say so where the player is
      final l = ctx == null ? null : L.of(ctx);
      final msg = l == null ? null : c.bye == 'kicked' ? l.eKicked : l.roomClosed;
      _drop(dispose: true);
      if (msg != null) messengerKey.currentState?.showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    if (c.view != null) { // the roles are dealt: back to the room
      HapticFeedback.heavyImpact();
      reopen();
      final l = navigatorKey.currentContext == null ? null : L.of(navigatorKey.currentContext!);
      if (l != null) messengerKey.currentState?.showSnackBar(SnackBar(content: Text(l.rolesDealt)));
    }
    notifyListeners(); // members, unread chat
  }

  /// Back to the room screen (the room bar, a deal, an invite into this same room).
  void reopen() {
    final c = conn, b = _reopen;
    if (c == null || b == null) return;
    _drop(dispose: false);
    // [S13-2 / #17] the room always sits right on Home: whatever was opened on top (the chat, a profile) closes first,
    // so the room's Home icon lands on Home
    navigatorKey.currentState?..popUntil((r) => r.isFirst)..push(MaterialPageRoute(builder: (_) => b(c)));
  }

  /// Leaves the room for good (before starting something else).
  void leave() {
    final c = conn;
    if (c == null) return;
    if (c.bye == null) c.send({'t': lanHost ? 'close' : 'leave'});
    final onLeave = _onLeave;
    _drop(dispose: true);
    onLeave?.call();
  }

  void _drop({required bool dispose}) {
    final c = conn;
    c?.removeListener(_watch);
    _side?.cancel(); _side = null;
    conn = null; _reopen = null; _onLeave = null;
    if (dispose) Future.delayed(const Duration(milliseconds: 300), () => c?.dispose()); // the goodbye goes out first
    notifyListeners();
  }
}

/// The online lobby I'm in right now: the room screen open, or the minimized one (null in a game, a Wi-Fi room, or none).
RoomConn? onlineLobby() {
  final c = openRoomConn ?? (ActiveRoom.instance.lan ? null : ActiveRoom.instance.conn);
  return c != null && c.room != null && c.view == null && c.bye == null ? c : null;
}
RoomConn? openRoomConn; // the online room screen on top, while it's mounted
