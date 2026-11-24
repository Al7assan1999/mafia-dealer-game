import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/chat/chat_screen.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/state/room_conn.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

/// While minimized, starting something else asks first. True when nothing is held (or it was left).
Future<bool> leaveRoomFirst(BuildContext context) async {
  final a = ActiveRoom.instance;
  if (!a.minimized) return true;
  final l = L.of(context);
  if (!await ask(context, l.leaveFirstQ, l.leaveFirstD(a.code), l.leaveRoom)) return false;
  a.leave();
  return true;
}

/// The room bar on every screen while minimized (MaterialApp.builder puts it above the pages).
class RoomBarFrame extends StatelessWidget {
  const RoomBarFrame({super.key, required this.child, this.onLongPress});
  final Widget child;
  final void Function(BuildContext context)? onLongPress; // P4: the friends drawer with Invite ready
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: ActiveRoom.instance, builder: (context, _) {
        final a = ActiveRoom.instance, c = a.conn;
        if (c == null) return child;
        final l = L.of(context), ms = c.members, host = ms.where((m) => m['host'] == true).firstOrNull, n = ms.where((m) => m['online'] != false).length;
        final mine = c.isHost, lost = c.link == Link.down;
        return Column(children: [
          Semantics(container: true, child: Material(color: C.red, elevation: 6, shadowColor: Colors.black, child: SafeArea(bottom: false, child: InkWell(
            key: const Key('roomBar'), onTap: a.reopen, onLongPress: onLongPress == null ? null : () => onLongPress!(context),
            // [S13-2 / #18] as the old app's bar: a live dot, who and how many, a clear "Back to room →", and a dropped
            // connection said in the bar itself
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(children: [
              Container(key: const Key('roomBarDot'), width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle,
                  color: lost ? const Color(0xFFFFC857) : C.priText, boxShadow: lost ? null : [BoxShadow(color: C.priText.withValues(alpha: .6), blurRadius: 6)])),
              const SizedBox(width: 10),
              Expanded(child: Text(lost ? l.rbLost : mine ? l.roomBarHost(n) : l.roomBarIn((host?['display'] as String?) ?? '?', n),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.priText, fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .18), borderRadius: BorderRadius.circular(C.neon ? 14 : 3)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(l.rbBack, style: TextStyle(color: C.priText, fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_forward, color: C.priText, size: 16), // mirrors itself in Arabic
                ])),
            ])),
          )))),
          // [QA] S15: the pages get their own semantics container: a page's BlockSemantics dropped the bar for TalkBack
          Expanded(child: Semantics(container: true, child: MediaQuery.removePadding(context: context, removeTop: true, child: child))),
        ]);
      });
}

/// [R1] The minimized room's chat on Home, under the friends tab (it was on the red bar at the top, N7), with the unread
/// count. Shown signed out too (a guest minimized in a Wi-Fi room).
/// [S14-1 / his #1] The chat as a side tab, under the friends tab (Home: the minimized room's; the room: always).
class ChatTab extends StatelessWidget {
  const ChatTab({super.key, required this.conn, required this.onTap});
  final RoomConn conn;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: conn, builder: (context, _) => Material(
        color: C.card2, elevation: 6,
        shape: RoundedRectangleBorder(side: BorderSide(color: C.red),
            borderRadius: BorderRadiusDirectional.horizontal(start: Radius.circular(C.neon ? 18 : 6)).resolve(Directionality.of(context))),
        child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10), child: Semantics(label: L.of(context).chatT, child: Badge(
            isLabelVisible: conn.unreadTotal > 0, label: Text('${conn.unreadTotal}'), child: Icon(Icons.chat_bubble_outline, color: C.text, size: 22))))),
      ));
}

class RoomChatButton extends StatelessWidget {
  const RoomChatButton({super.key, required this.account});
  final Account account;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: ActiveRoom.instance, builder: (context, _) {
        final a = ActiveRoom.instance, c = a.conn;
        if (c == null || !a.minimized) return const SizedBox.shrink();
        return ChatTab(key: const Key('barChat'), conn: c,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(conn: c, account: account, out: false, safety: !a.lan))));
      });
}
