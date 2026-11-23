// The friends drawer (S9-2), as in the old app: a tab on the screen edge (right; left in Arabic) with online friends'
// avatars, the online count and a red dot for requests. Drag it up or down (the spot is kept); tap or swipe it to slide
// the drawer out: requests first, then friends (online first) with what you can do: Invite (into my online lobby, or
// from Home: a new room), In your room, Ask to join. "+" opens the Friends screen.
import 'package:flutter/material.dart';

import 'account.dart';
import 'account_screens.dart';
import 'audio.dart';
import 'l10n/app_localizations.dart';
import 'online.dart';
import 'prefs.dart';
import 'room.dart';
import 'ui.dart';

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key, required this.account, required this.prefs, required this.audio, this.room, this.extra, this.above = 56});
  final double above; // the tab never goes higher (Home: the icon row; a lobby: the room-code card)
  final Account account;
  final Prefs prefs;
  final Audio audio;
  final RoomConn? room; // the online lobby on screen (null on Home: the minimized room, if any, is used)
  final Widget? extra; // [R1] the minimized room's chat button, under the tab (shown signed out too)
  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  late double y = widget.prefs.drawerY;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.account, builder: (context, _) {
        final a = widget.account;
        if (!a.signedIn && widget.extra == null) return const SizedBox.shrink();
        final online = a.friends.where((f) => f.online).toList(), reqs = a.incoming.length;
        return LayoutBuilder(builder: (context, box) {
          // [QA] S9 #3: never over the top icon row; by default right under it, clear of the first Home button (the old v2.9.2 fix)
          final above = widget.above;
          final top = above + (box.maxHeight - above - 160) * y.clamp(0, 1);
          return Stack(children: [
            PositionedDirectional(end: 0, top: top, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (a.signedIn) GestureDetector(
                key: const Key('friendsTab'),
                onTap: () => openFriendsDrawer(context, account: a, prefs: widget.prefs, audio: widget.audio, room: widget.room),
                onHorizontalDragEnd: (d) {
                  final towardCenter = Directionality.of(context) == TextDirection.ltr ? (d.primaryVelocity ?? 0) < -100 : (d.primaryVelocity ?? 0) > 100;
                  if (towardCenter) openFriendsDrawer(context, account: a, prefs: widget.prefs, audio: widget.audio, room: widget.room);
                },
                onVerticalDragUpdate: (d) => setState(() => y = (y + d.delta.dy / (box.maxHeight - above - 160)).clamp(0, 1)),
                onVerticalDragEnd: (_) => widget.prefs.drawerY = y,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(color: C.card2, border: Border.all(color: C.line2),
                      borderRadius: BorderRadiusDirectional.horizontal(start: Radius.circular(C.neon ? 18 : 6)).resolve(Directionality.of(context)),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)]),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Badge(isLabelVisible: reqs > 0, smallSize: 9, backgroundColor: C.red2, child: Icon(Icons.people_alt_outlined, color: C.text, size: 22)),
                    for (final f in online.take(3)) Padding(padding: const EdgeInsets.only(top: 6), child: AvatarView.of(a.api, f, size: 28, online: true)),
                    if (online.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${online.length}', key: const Key('onlineCount'), style: TextStyle(color: C.green, fontSize: 12, fontWeight: FontWeight.w700))),
                  ]),
                ),
              ),
              if (widget.extra != null) Padding(padding: EdgeInsets.only(top: a.signedIn ? 8 : 0), child: widget.extra!),
            ])),
          ]);
        });
      });
}

/// Slides the drawer out from the tab's edge.
Future<void> openFriendsDrawer(BuildContext context, {required Account account, required Prefs prefs, required Audio audio, RoomConn? room}) =>
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: 'friends', barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) => _Drawer(account: account, prefs: prefs, audio: audio, room: room),
      transitionBuilder: (ctx, anim, _, child) {
        final ltr = Directionality.of(ctx) == TextDirection.ltr;
        return SlideTransition(position: Tween(begin: Offset(ltr ? 1 : -1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)), child: child);
      },
    );

class _Drawer extends StatefulWidget {
  const _Drawer({required this.account, required this.prefs, required this.audio, this.room});
  final Account account;
  final Prefs prefs;
  final Audio audio;
  final RoomConn? room;
  @override
  State<_Drawer> createState() => _DrawerState();
}

class _DrawerState extends State<_Drawer> {
  final _sent = <String, DateTime>{}; // Invited / Asked for 5 s, then "again" (the old app's rule)

  RoomConn? get _room => widget.room ?? onlineLobby();
  /// [N6] my online lobby, from the room actually on screen (or minimized), not from the server's view that lags behind
  String? get _lobby => onlineLobby()?.code ?? (widget.room != null && widget.room!.view == null ? widget.room!.code : null);

  Future<void> _do(String id, Future<void> Function() f) async {
    final l = L.of(context);
    try { await f(); if (mounted) setState(() => _sent[id] = DateTime.now()); } catch (e) { if (mounted) toastErr(context, errText(l, e)); }
  }
  bool _recent(String id) => _sent[id] != null && DateTime.now().difference(_sent[id]!) < const Duration(seconds: 5);

  /// Invite from Home (S9-5 AC3): a new online room, opened, with the friend invited once it exists.
  Future<void> _inviteNew(Person f) async {
    final l = L.of(context), nav = Navigator.of(context);
    try {
      final code = await widget.account.createRoom();
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => RoomScreen(account: widget.account, prefs: widget.prefs, audio: widget.audio, code: code, inviteOnJoin: f.id)));
    } catch (e) { if (mounted) toastErr(context, errText(l, e)); }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.account, builder: (context, _) {
        final l = L.of(context), a = widget.account, lobby = _lobby, inRoom = {for (final m in _room?.members ?? const []) m['uid']};
        final friends = [...a.friends]..sort((x, y) => (y.online ? 1 : 0) - (x.online ? 1 : 0));
        final noRoom = _room == null && a.roomCode == null && ActiveRoom.instance.conn == null;
        Widget action(Person f) {
          if (lobby != null && inRoom.contains(f.id)) return Text(l.inYourRoom, key: Key('inRoom_${f.handle}'), style: TextStyle(color: C.green, fontSize: 12));
          if (lobby != null) return TextButton(key: Key('dInvite_${f.handle}'), onPressed: () => _do(f.id, () => a.invite(f.id, lobby)), child: Text(_recent(f.id) ? l.invited : l.invite));
          if (noRoom && f.online && f.status == 'lobby' && f.j['op'] == true) { // only when I'm in no room (N6)
            return TextButton(key: Key('dAsk_${f.handle}'), onPressed: () => _do(f.id, () => a.askToJoin(f.id)), child: Text(_recent(f.id) ? l.asked : l.askJoin));
          }
          if (noRoom && f.online) return TextButton(key: Key('dInviteNew_${f.handle}'), onPressed: () => _inviteNew(f), child: Text(l.invite));
          return const SizedBox.shrink();
        }
        final w = MediaQuery.sizeOf(context).width;
        return Align(alignment: AlignmentDirectional.centerEnd, child: GestureDetector(
          onHorizontalDragEnd: (d) { // a swipe back toward the edge closes it
            final out = Directionality.of(context) == TextDirection.ltr ? (d.primaryVelocity ?? 0) > 100 : (d.primaryVelocity ?? 0) < -100;
            if (out) Navigator.of(context).pop();
          },
          child: Material(key: const Key('friendsDrawer'), color: C.card, child: SafeArea(child: SizedBox(width: w * .85 > 360 ? 360 : w * .85, child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 4), child: Row(children: [
              Expanded(child: Text(l.friendsT, style: head.copyWith(fontSize: 22))),
              IconButton(key: const Key('drawerAdd'), icon: Icon(Icons.person_add_alt, color: C.text), onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => FriendsScreen(account: a)));
              }),
            ])),
            Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final r in a.incoming)
                Card(color: C.card2, child: ListTile(key: Key('dReq_${r.handle}'),
                  leading: AvatarView.of(a.api, r, size: 36), title: Text(r.display), subtitle: Text(l.nReq, style: TextStyle(color: C.mute, fontSize: 12)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(key: Key('dAccept_${r.handle}'), icon: Icon(Icons.check, color: C.green), onPressed: () => a.accept(r.id).catchError((_) {})),
                    IconButton(key: Key('dDecline_${r.handle}'), icon: Icon(Icons.close, color: C.dim), onPressed: () => a.decline(r.id).catchError((_) {})),
                  ]))),
              if (friends.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(l.fAdd, textAlign: TextAlign.center, style: TextStyle(color: C.mute))),
              for (final f in friends)
                ListTile(key: Key('dFriend_${f.handle}'), contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  onTap: () { Navigator.of(context).pop(); openProfile(context, a, f); }, // N2
                  leading: AvatarView.of(a.api, f, size: 36, online: f.online),
                  title: Text(f.display, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(friendStatus(l, f), // P3
                      style: TextStyle(color: !f.online ? C.dim : f.status == 'game' ? C.red2 : f.status == 'lobby' ? C.gold : C.green, fontSize: 12)),
                  trailing: action(f)),
            ])),
          ]))))),
        );
      });
}
