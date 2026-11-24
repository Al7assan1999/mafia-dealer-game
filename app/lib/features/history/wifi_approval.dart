import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

/// A kept Wi-Fi game's way into online history (S7-2): the button for the host, the guest line, or the request's
/// status. `server` is the server's view of the request (History loads it); else the phone's own record of it.
class WifiApproval extends StatefulWidget {
  const WifiApproval({super.key, required this.account, required this.prefs, required this.gameKey, this.server, this.game, this.compact = false});
  final Account account;
  final Prefs prefs;
  final String gameKey;
  final Map<String, Object?>? server, game;
  final bool compact;
  @override
  State<WifiApproval> createState() => _WifiApprovalState();
}

class _WifiApprovalState extends State<WifiApproval> {
  bool busy = false;

  static String reasonText(L l, String? r) => switch (r) {
        'replay' => l.wrReplay, 'seats' => l.wrSeats, 'players' => l.wrPlayers, 'short' => l.wrShort, 'old' => l.wrOld, 'dup' => l.wrDup, _ => r ?? '?' };
  static String statusText(L l, Map<String, Object?> req, int players) => switch (req['status']) {
        'pending' => l.wPending((req['waiting'] as int?) ?? players - 1, (req['total'] as int?) ?? players),
        'approved' => l.wApproved, 'declined' => l.wDeclined, 'expired' => l.wExpired, _ => l.wRejected(reasonText(l, req['reason'] as String?)) };

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Listenable.merge([widget.prefs, widget.account]), builder: (context, _) {
    final l = L.of(context);
    final g = widget.game ?? widget.prefs.wifiGames.where((x) => x['id'] == widget.gameKey).firstOrNull;
    if (g == null) return const SizedBox.shrink();
    final players = ((g['names'] as List?) ?? const []).length;
    final local = g['req'] == null ? null : Map<String, Object?>.from(g['req'] as Map);
    // the server knows better (others' answers), except right after a rejection it never keeps for History
    final req = widget.server ?? local;
    final pad = EdgeInsets.only(top: widget.compact ? 4 : 0, bottom: widget.compact ? 0 : 10);
    if (req != null) {
      final ok = req['status'] == 'approved', waiting = req['status'] == 'pending';
      return Padding(padding: pad, child: Row(mainAxisAlignment: widget.compact ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
        Icon(ok ? Icons.verified_outlined : waiting ? Icons.hourglass_top : Icons.block, size: 16, color: ok ? C.green : waiting ? C.gold : C.dim),
        const SizedBox(width: 6),
        Flexible(child: Text(statusText(l, req, players), key: const Key('wifiStatus'), style: TextStyle(color: ok ? C.green : C.mute, fontSize: 13))),
      ]));
    }
    if (g['host'] != true) return const SizedBox.shrink();
    if (Account.hadGuest(g)) {
      return Padding(padding: pad, child: Text(l.guestStays, key: const Key('guestStays'), textAlign: widget.compact ? TextAlign.start : TextAlign.center, style: TextStyle(color: C.dim, fontSize: 13)));
    }
    if (!widget.account.canAskWifi(g)) return const SizedBox.shrink();
    Future<void> send() async {
      setState(() => busy = true);
      try { await widget.account.askWifi(g); }
      catch (e) { if (context.mounted) toast(context, e is ApiError && e.code == 'slow_down' ? l.wrLimit : errText(l, e)); }
      if (mounted) setState(() => busy = false);
    }
    if (widget.compact) {
      return Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const Key('addOnline'), onPressed: busy ? null : send,
          icon: Icon(Icons.cloud_upload_outlined, size: 18, color: C.red2), label: Text(l.addOnline, style: TextStyle(color: C.red2))));
    }
    return Padding(padding: pad, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Btn(l.addOnline, key: const Key('addOnline'), ghost: true, icon: Icons.cloud_upload_outlined, onTap: busy ? null : send),
      Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.addOnlineD, textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 12))),
    ]));
  });
}
