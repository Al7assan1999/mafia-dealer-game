import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mafia_dealer/features/friends/friend_search.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/avatar.dart';
import 'package:mafia_dealer/features/account/sign_in_screen.dart';
import 'package:mafia_dealer/features/safety/safety.dart';
import 'package:mafia_dealer/features/stats/player_screen.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/state/models.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

// ---------------------------------------------------------------- friends
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.account});
  final Account account;
  @override
  State<FriendsScreen> createState() => _FriendsState();
}

class _FriendsState extends State<FriendsScreen> {
  late final a = widget.account;
  final add = TextEditingController();
  bool busy = false;

  @override
  void initState() { super.initState(); if (a.signedIn) a.loadFriends().catchError((_) {}); }

  Future<void> _do(Future<void> Function() f) async {
    if (busy) return;
    setState(() => busy = true);
    final l = L.of(context);
    try { await f(); } catch (e) { if (mounted) toastErr(context, errText(l, e)); }
    if (mounted) setState(() => busy = false);
  }

  String _status(L l, Person p) => friendStatus(l, p);

  // [N2] the whole row (avatar included) opens the friend's profile
  Widget _row(Person p, List<Widget> actions, {String? sub}) => InkWell(
        key: Key('friendStats_${p.handle}'),
        onTap: () => openProfile(context, a, p),
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          AvatarView.of(a.api, p, size: 40, online: sub != null ? p.online : null),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.display, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text([if (p.handle != null) atHandle(p.handle), ?sub].join(' · '), style: TextStyle(color: C.mute, fontSize: 12)),
            ])),
          ...actions,
        ]),
      ));

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    if (!a.signedIn) {
      return Scaffold(appBar: AppBar(backgroundColor: C.bg, title: Text(l.friendsT, style: head.copyWith(fontSize: 20))),
          body: Stage(children: [Big(l.friendsT, sub: l.fWhy), const SizedBox(height: 18), Btn(l.aIn, onTap: () =>
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SignInScreen(account: a))))]));
    }
    return ListenableBuilder(listenable: a, builder: (context, _) => DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: C.bg,
              title: Text(l.friendsT, style: head.copyWith(fontSize: 20)),
              actions: [
                if (a.handle != null)
                  IconButton(key: const Key('share'), tooltip: l.fShareMe, icon: const Icon(Icons.share_outlined),
                      onPressed: () => SharePlus.instance.share(ShareParams(text: l.fShareTxt(a.handle!)))),
              ],
              bottom: TabBar(indicatorColor: C.red, labelColor: C.text, unselectedLabelColor: C.mute, tabs: [
                Tab(text: '${l.fTabF} (${a.friends.length})'),
                Tab(key: const Key('tabRequests'), text: '${l.fTabR} (${a.incoming.length})'),
                Tab(key: const Key('tabSent'), text: '${l.fTabS} (${a.outgoing.length})'),
              ]),
            ),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  // [S13-4] a search: part of a name or of an @username; the exact @username still adds directly
                  Expanded(child: TextField(key: const Key('addHandle'), controller: add, onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(hintText: l.searchHint, prefixIcon: Icon(Icons.search, color: C.mute)))),
                  const SizedBox(width: 8),
                  FilledButton(key: const Key('addFriend'), style: FilledButton.styleFrom(backgroundColor: C.red), onPressed: busy ? null : () {
                    final h = add.text.trim();
                    if (!handleRx.hasMatch(h)) return toast(context, l.eHandle);
                    _do(() async {
                      final rel = await a.request(h);
                      add.clear();
                      if (mounted) setState(() {});
                      if (context.mounted) toast(context, rel == 'friends' ? l.fNowFriends('@${h.replaceFirst('@', '')}') : l.fReqSent('@${h.replaceFirst('@', '')}'));
                    });
                  }, child: Text(l.fAddBtn)),
                ]),
              ),
              if (a.offline) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.eOffline, style: TextStyle(color: C.red2))),
              if (add.text.trim().isNotEmpty) Expanded(child: FriendSearchResults(account: a, query: add.text)) else
              Expanded(child: TabBarView(children: [
                _list(l.fNone, [for (final p in a.friends) _row(p, [
                  if (onlineLobby() case final room? when room.members.any((m) => m['uid'] == p.id))
                    Text(l.inYourRoom, style: TextStyle(color: C.green, fontSize: 12))
                  else if (onlineLobby() case final room?)
                    TextButton(key: Key('fInvite_${p.handle}'), onPressed: () => _do(() async { await a.invite(p.id, room.code); if (context.mounted) toast(context, l.invited); }),
                        child: Text(l.invite, style: TextStyle(color: C.red2)))
                  else if (p.j['op'] == true && a.roomCode == null && ActiveRoom.instance.conn == null)
                    TextButton(key: Key('askJoin_${p.handle}'), onPressed: () => _do(() async { await a.askToJoin(p.id); if (context.mounted) toast(context, l.asked); }),
                        child: Text(l.askJoin, style: TextStyle(color: C.red2))),
                  SafetyMenu(account: a, userId: p.id, name: p.display, extra: [PopupMenuItem(value: 'remove', child: Text(l.fRemove))],
                      onExtra: (_) async { if (await ask(context, l.fRemoveQ(p.display), l.fRemoveD, l.fRemove)) _do(() => a.unfriend(p.id)); }),
                ], sub: _status(l, p))]),
                _list(l.fNoReq, [for (final p in a.incoming) _row(p, [
                  TextButton(key: Key('accept_${p.handle}'), onPressed: () => _do(() => a.accept(p.id)), child: Text(l.fAccept, style: TextStyle(color: C.green))),
                  TextButton(onPressed: () => _do(() => a.decline(p.id)), child: Text(l.fDecline, style: TextStyle(color: C.mute))),
                ])]),
                _list(l.fNoSent, [for (final p in a.outgoing) _row(p, [
                  TextButton(onPressed: () => _do(() => a.decline(p.id)), child: Text(l.fCancelReq, style: TextStyle(color: C.mute))),
                ])]),
              ])),
            ]),
          ),
        ));
  }

  Widget _list(String empty, List<Widget> rows) => RefreshIndicator(
        onRefresh: () => a.loadFriends().catchError((_) {}),
        child: ListView(padding: const EdgeInsets.all(16), children: rows.isEmpty ? [Text(empty, style: TextStyle(color: C.mute))] : rows),
      );
}

/// A player's profile: their card and their verified games (all of them, not only mine).
void openProfile(BuildContext context, Account a, Person p) => Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PlayerScreen(account: a, playerKey: 'u:${p.id}', person: p)));

/// [N5] An invite, a request to join, "let you in" or a friend request pops up on top while the app is open (the old
/// app's banner): the person, what they want and the one action, for 6 seconds. It stays in the bell either way.

/// A friend's status line: Offline / Online / In a room · 3 players / In a game · 5 players (P3: the count).
String friendStatus(L l, Person f) => !f.online ? l.fOffline
    : f.status == 'game' ? (f.roomSize > 0 ? l.fInGameN(f.roomSize) : l.fInGame)
    : f.status == 'lobby' ? (f.roomSize > 0 ? l.fInRoomN(f.roomSize) : l.fInRoom) : l.fOnline;
