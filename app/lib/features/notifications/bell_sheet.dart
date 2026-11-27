import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/avatar.dart';
import 'package:mafia_dealer/features/friends/friends_screen.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/state/models.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

// ---------------------------------------------------------------- the bell
class BellSheet extends StatefulWidget {
  const BellSheet({super.key, required this.account});
  final Account account;
  @override
  State<BellSheet> createState() => _BellState();
}

String _result(L l, String r) => switch (r) {
      'joined' => l.rJoined, 'let_in' => l.rLetIn, 'accepted' => l.rAccepted, 'declined' => l.rDeclined, 'dismissed' => l.rDismissed, _ => l.rExpired };

class _BellState extends State<BellSheet> {
  // [N8] what was unread when the bell opened stays marked while it's open; after a moment on screen it counts as read
  Set<String> _unread = {};
  Timer? _seen;
  @override
  void initState() {
    super.initState();
    widget.account.loadNotes().then((_) {
      if (!mounted) return;
      setState(() => _unread = {for (final n in widget.account.notes) if (!n.read) n.id});
      _seen = Timer(const Duration(seconds: 2), () => widget.account.markRead(_unread.toList()));
    }).catchError((_) {});
  }
  @override
  void dispose() { _seen?.cancel(); super.dispose(); }
  Future<void> _readAll() async { await widget.account.readAll(); if (mounted) setState(() => _unread = {}); }
  bool _isNew(Note n) => _unread.contains(n.id);

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.account, builder: (context, _) {
        final l = L.of(context), a = widget.account;
        final notes = a.notes;
        return SafeArea(child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
          child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(l.notifT, style: head.copyWith(fontSize: 22))),
              if (_unread.isNotEmpty) TextButton(key: const Key('markAllRead'), onPressed: _readAll, child: Text(l.markAllRead, style: TextStyle(color: C.red2))),
              if (notes.isNotEmpty) TextButton(key: const Key('clearNotes'), onPressed: () => a.deleteNote(null).catchError((_) {}), child: Text(l.nClear, style: TextStyle(color: C.mute))),
            ]),
            if (notes.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text(l.nNone, style: TextStyle(color: C.mute))),
            Flexible(child: ListView(shrinkWrap: true, children: [
              for (final n in notes)
                if (n.wifi != null) _WifiNote(account: a, note: n) else
                ListTile(
                  key: Key('note_${n.id}'), contentPadding: EdgeInsets.zero,
                  leading: Badge(isLabelVisible: _isNew(n), smallSize: 9, backgroundColor: C.red2, child: AvatarView.of(a.api, n.from, size: 36)),
                  title: Text(n.from.display, key: _isNew(n) ? Key('unread_${n.id}') : null, style: TextStyle(fontWeight: _isNew(n) ? FontWeight.w700 : FontWeight.w400)),
                  subtitle: Text(switch (n.kind) {
                    'friend_request' => l.nReq, 'friend_accept' => l.nAcc, 'invite' => l.nInvite(n.code ?? ''),
                    'let_in' => l.nLetIn(n.code ?? ''),
                    'title_lost' => l.nTitleLost(switch (n.j['title']) { 'best' => l.tBest, 'mafia' => l.tMafia, 'det' => l.tDet, 'doc' => l.tDoc, _ => l.tFirst }),
                    _ => l.nJoinReq,
                  }, style: TextStyle(color: C.mute)),
                  // S9-5 AC2: an answered item stays 24 h, read-only, with its result
                  trailing: n.result != null
                      ? Text(_result(l, n.result!), key: Key('result_${n.id}'), style: TextStyle(color: n.result == 'expired' || n.result == 'dismissed' || n.result == 'declined' ? C.dim : C.green, fontSize: 12))
                      : n.kind == 'friend_request' && a.incoming.any((p) => p.id == n.from.id)
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(key: Key('accept_${n.from.handle}'), onPressed: () async {
                            try { await a.accept(n.from.id); await a.loadNotes(); } catch (e) { if (context.mounted) toastErr(context, errText(l, e)); }
                          }, child: Text(l.fAccept, style: TextStyle(color: C.green))),
                          IconButton(key: Key('decline_${n.from.handle}'), tooltip: l.fDecline, icon: Icon(Icons.close, color: C.dim), onPressed: () async {
                            try { await a.decline(n.from.id); await a.loadNotes(); } catch (e) { if (context.mounted) toastErr(context, errText(l, e)); }
                          }),
                        ])
                      : n.kind == 'join_request' && a.roomCode != null
                      ? TextButton(key: Key('letIn_${n.from.handle}'), onPressed: () async {
                          try { await a.invite(n.from.id, a.roomCode!); await a.loadNotes(); } catch (e) { if (context.mounted) toastErr(context, errText(l, e)); }
                        }, child: Text(l.letIn, style: TextStyle(color: C.green)))
                      : IconButton(icon: Icon(Icons.close, color: C.dim), onPressed: () => a.deleteNote(n.id).catchError((_) {})),
                  onTap: () {
                    if (_isNew(n)) { setState(() => _unread.remove(n.id)); a.markRead([n.id]); }
                    if (n.result != null) return; // read-only
                    if ((n.kind == 'invite' || n.kind == 'let_in') && n.code != null) a.handled(n.id, 'joined');
                    Navigator.of(context).pop();
                    if ((n.kind == 'invite' || n.kind == 'let_in') && n.code != null && a.openRoom != null) return a.openRoom!(n.code!);
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FriendsScreen(account: a)));
                  },
                ),
            ])),
          ])),
        ));
      });
}

/// A Wi-Fi game in the bell: asked to confirm it (Confirm / Not me), or the result of my own request.
class _WifiNote extends StatefulWidget {
  const _WifiNote({required this.account, required this.note});
  final Account account;
  final Note note;
  @override
  State<_WifiNote> createState() => _WifiNoteState();
}

class _WifiNoteState extends State<_WifiNote> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final l = L.of(context), n = widget.note, w = n.wifi!, a = widget.account;
    // [QA] U1: day and year in Western digits, like every other number in the app (Arabic's date format uses ٢٣)
    final d = DateTime.fromMillisecondsSinceEpoch(w['playedAt'] as int), date = '${d.day} ${DateFormat.MMMM(Localizations.localeOf(context).languageCode).format(d)} ${d.year}';
    final winner = winText(l, winnerIn(w)), role = w['role2'] ?? w['role']; // [S21] winner2: the real result // [S20] role2: the real role (role: one a 1.2 app knows)
    if (n.kind == 'wifi_result') {
      final ok = w['status'] == 'approved';
      return ListTile(key: Key('note_${n.id}'), contentPadding: EdgeInsets.zero,
        leading: Icon(ok ? Icons.verified_outlined : Icons.block, color: ok ? C.green : C.dim, size: 32),
        title: Text(l.nWifiDone(date, switch (w['status']) { 'approved' => l.wApproved, 'declined' => l.wDeclined, _ => l.wExpired }),
            style: TextStyle(fontWeight: n.read ? FontWeight.w400 : FontWeight.w700)),
        trailing: IconButton(icon: Icon(Icons.close, color: C.dim), onPressed: () => a.deleteNote(n.id).catchError((_) {})));
    }
    Future<void> answer(bool yes) async {
      setState(() => busy = true);
      try { await a.answerWifi(w['request'] as String, yes); } catch (e) { if (context.mounted) toastErr(context, errText(l, e)); }
      if (mounted) setState(() => busy = false);
    }
    return Padding(key: Key('note_${n.id}'), padding: const EdgeInsets.symmetric(vertical: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AvatarView.of(a.api, n.from, size: 36),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n.from.display, style: TextStyle(fontWeight: n.read ? FontWeight.w400 : FontWeight.w700)),
        Text(l.nWifiAsk(date, w['players'] as int, winner) + (roleOf(role) == null ? '' : ' ${l.nWifiYou(roleName(l, roleOf(role)!))}'), style: TextStyle(color: C.mute)),
        const SizedBox(height: 6),
        Row(children: [
          FilledButton(key: Key('wifiYes_${w['request']}'), style: FilledButton.styleFrom(backgroundColor: C.red), onPressed: busy ? null : () => answer(true), child: Text(l.wConfirm)),
          const SizedBox(width: 10),
          OutlinedButton(key: Key('wifiNo_${w['request']}'), onPressed: busy ? null : () => answer(false), child: Text(l.wNotMe, style: TextStyle(color: C.text))),
        ]),
      ])),
    ]));
  }
}

/// A player's profile: their card and their verified games (all of them, not only mine).
