import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/avatar.dart';
import 'package:mafia_dealer/features/notifications/bell_sheet.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

/// [N5] An invite, a request to join, "let you in" or a friend request pops up on top while the app is open (the old
/// app's banner): the person, what they want and the one action, for 6 seconds. It stays in the bell either way.
class NoteBanner extends StatefulWidget {
  const NoteBanner({super.key, required this.account});
  final Account account;
  @override
  State<NoteBanner> createState() => _NoteBannerState();
}

class _NoteBannerState extends State<NoteBanner> {
  Timer? _hide;
  @override
  void initState() { super.initState(); widget.account.banner.addListener(_arm); }
  @override
  void dispose() { widget.account.banner.removeListener(_arm); _hide?.cancel(); super.dispose(); }
  void _arm() { _hide?.cancel(); if (widget.account.banner.value != null) _hide = Timer(const Duration(seconds: 6), _close); if (mounted) setState(() {}); }
  void _close() => widget.account.banner.value = null;

  @override
  Widget build(BuildContext context) {
    final n = widget.account.banner.value, a = widget.account;
    if (n == null || n.wifi != null && n.kind != 'wifi_confirm') return const SizedBox.shrink();
    final l = L.of(context);
    final text = switch (n.kind) {
      'invite' => l.nInvite(n.code ?? ''), 'let_in' => l.nLetIn(n.code ?? ''), 'join_request' => l.nJoinReq, 'friend_request' => l.nReq,
      'friend_accept' => l.nAcc,
      'title_lost' => l.nTitleLost(switch (n.j['title']) { 'best' => l.tBest, 'mafia' => l.tMafia, 'det' => l.tDet, 'doc' => l.tDoc, _ => l.tFirst }),
      _ => l.notifT };
    Future<void> act() async {
      _close();
      final nav = ActiveRoom.navigatorKey.currentContext;
      switch (n.kind) {
        case 'invite' || 'let_in' when n.code != null:
          await a.handled(n.id, 'joined');
          a.openRoom?.call(n.code!);
        case 'join_request':
          final room = onlineLobby();
          if (room != null) await a.invite(n.from.id, room.code).catchError((_) {});
        case 'friend_request':
          await a.accept(n.from.id).catchError((_) {});
        default:
          if (nav != null && nav.mounted) showModalBottomSheet(context: nav, backgroundColor: C.card, isScrollControlled: true, useSafeArea: true, builder: (_) => BellSheet(account: a));
      }
    }
    final label = switch (n.kind) { 'invite' || 'let_in' => l.bJoin, 'join_request' => l.letIn, 'friend_request' => l.fAccept, _ => l.bOpen };
    // [S12-5] below the top bar (it covered Friends, the bell and Settings for 6 s), and swiped away up or sideways
    return Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(10, 68, 10, 10), child: Dismissible(
      key: ValueKey('banner_${n.id}'), direction: DismissDirection.up, onDismissed: (_) => _close(), child: Dismissible(
      key: ValueKey('bannerX_${n.id}'), direction: DismissDirection.horizontal, onDismissed: (_) => _close(), child: Material(
      key: const Key('noteBanner'), color: C.card2, elevation: 8,
      shape: RoundedRectangleBorder(side: BorderSide(color: C.red), borderRadius: BorderRadius.circular(C.neon ? 16 : 6)),
      child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 4, 8), child: Row(children: [
        AvatarView.of(a.api, n.from, size: 36),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(n.from.display, style: TextStyle(color: C.text, fontWeight: FontWeight.w700)),
          Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 13)),
        ])),
        TextButton(key: const Key('bannerAct'), onPressed: act, child: Text(label, style: TextStyle(color: C.red2, fontWeight: FontWeight.w700))),
        IconButton(key: const Key('bannerClose'), icon: Icon(Icons.close, color: C.dim, size: 18), onPressed: _close),
      ])),
    ))))));
  }
}

/// A friend's status line: Offline / Online / In a room · 3 players / In a game · 5 players (P3: the count).
