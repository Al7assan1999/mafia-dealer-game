// [S13-4 / his note 12] Find people to add by typing part of a name or an @username (from 2 letters), not only the exact
// @username. The results show who they are and where you stand (Add / Requested / Friends / Accept).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/avatar.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/state/models.dart';

class FriendSearchResults extends StatefulWidget {
  const FriendSearchResults({super.key, required this.account, required this.query});
  final Account account;
  final String query;
  @override
  State<FriendSearchResults> createState() => _SearchState();
}

class _SearchState extends State<FriendSearchResults> {
  List<Person>? found;
  String? error;
  Timer? _wait;
  final _asked = <String>{};

  @override
  void initState() { super.initState(); _schedule(); }
  @override
  void didUpdateWidget(FriendSearchResults old) { super.didUpdateWidget(old); if (old.query != widget.query) _schedule(); }
  @override
  void dispose() { _wait?.cancel(); super.dispose(); }

  /// One request a moment after the typing stops, not one per letter.
  void _schedule() {
    _wait?.cancel();
    final q = widget.query.trim().replaceFirst('@', '');
    if (q.length < 2) { setState(() { found = null; error = null; }); return; }
    _wait = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await widget.account.searchPeople(q);
        if (mounted && widget.query.trim().replaceFirst('@', '') == q) setState(() { found = r; error = null; });
      } catch (e) { if (mounted) setState(() => error = errText(L.of(context), e)); }
    });
  }

  Future<void> _add(Person p) async {
    final l = L.of(context);
    try {
      final rel = await widget.account.request(p.handle!);
      if (mounted) setState(() => _asked.add(p.id));
      if (mounted) toast(context, rel == 'friends' ? l.fNowFriends(atHandle(p.handle)) : l.fReqSent(atHandle(p.handle)));
    } catch (e) { if (mounted) toastErr(context, errText(l, e)); }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), q = widget.query.trim().replaceFirst('@', ''), list = found, a = widget.account;
    if (q.length < 2) return Padding(padding: const EdgeInsets.all(20), child: Text(l.searchMin, textAlign: TextAlign.center, style: TextStyle(color: C.mute)));
    if (error != null) return Padding(padding: const EdgeInsets.all(20), child: Text(error!, textAlign: TextAlign.center, style: TextStyle(color: C.red2)));
    if (list == null) return Padding(padding: const EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: C.red2)));
    if (list.isEmpty) return Padding(padding: const EdgeInsets.all(20), child: Text(l.searchNone(q), key: const Key('searchNone'), textAlign: TextAlign.center, style: TextStyle(color: C.mute)));
    return ListView(key: const Key('searchResults'), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
      for (final p in list)
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(key: Key('found_${p.handle}'), children: [
          AvatarView.of(a.api, p, size: 40),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.display, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(atHandle(p.handle), style: TextStyle(color: C.mute, fontSize: 12)),
          ])),
          switch (_asked.contains(p.id) ? 'requested' : p.rel) {
            'friends' => Text(l.friendsT, style: TextStyle(color: C.green, fontSize: 12)),
            'requested' => Text(l.pRequested, key: Key('foundAsked_${p.handle}'), style: TextStyle(color: C.gold, fontSize: 12)),
            'incoming' => TextButton(key: Key('foundAccept_${p.handle}'), onPressed: () => a.accept(p.id).then((_) { if (mounted) setState(() => _asked.add(p.id)); }, onError: (_) {}),
                child: Text(l.fAccept, style: TextStyle(color: C.green))),
            _ => TextButton(key: Key('foundAdd_${p.handle}'), onPressed: () => _add(p), child: Text(l.fAddBtn, style: TextStyle(color: C.red2))),
          },
        ])),
    ]);
  }
}
