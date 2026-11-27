part of 'room_screen.dart';

extension _EndViews on _RoomScreenState {
  void _mark(bool valid) {
    c.send({'t': 'mark', 'valid': valid});
    toast(context, valid ? L.of(context).markedValid : L.of(context).markedInvalid);
  }

  Widget _end(L l, Map<String, Object?> view) {
    if (!revealed) return _suspense(l, l.gameOver, C.glory, Icons.emoji_events_outlined);
    final rc = Map<String, Object?>.from(view['recap'] as Map), winner = Winner.values.asNameMap()[rc['winner']] ?? Winner.citizens;
    final roles = (rc['roles'] as List).map((x) => roleOf(x) ?? Role.citizen).toList(), alive = (rc['alive'] as List).cast<bool>();
    final st = rc['stats'] as Map;
    final stats = Stats(first: st['first'] as int?, kills: (st['kills'] as List).cast<int>(), outs: (st['outs'] as List).cast<int>(),
        saves: (st['saves'] as List).cast<int>(), caught: [for (final p in (st['caught'] as List)) ((p as List)[0] as int, p[1] as int)],
        guards: [for (final p in (st['guards'] as List? ?? const [])) ((p as List)[0] as int, p[1] as int)],
        hunts: [for (final p in (st['hunts'] as List? ?? const [])) ((p as List)[0] as int, p[1] as int)],
        lovers: st['lovers'] is List ? ((st['lovers'] as List)[0] as int, (st['lovers'] as List)[1] as int) : null);
    final best = mvp(winner, roles, alive, stats), valid = c.room?['valid'];
    return Stage(color: winStage(winner), center: false, bottom: [
      if (c.isHost) ...[
        if (c.room?['gameId'] != null) Row(children: [
          // [1.0.1 hotfix] the choice shows a tick and says what it means (a tap on the one already chosen looked dead)
          Expanded(child: Btn(l.valid, key: const Key('markValid'), ghost: valid != true, icon: valid == true ? Icons.check : null, onTap: _h(() => _mark(true)))),
          const SizedBox(width: 10),
          Expanded(child: Btn(l.invalid, key: const Key('markInvalid'), ghost: valid != false, icon: valid == false ? Icons.check : null, onTap: _h(() => _mark(false)))),
        ]),
        // Wi-Fi: an Invalid game isn't offered to online history
        if (widget.lan && _wifiKey != null && valid != false) WifiApproval(account: widget.account, prefs: widget.prefs, gameKey: _wifiKey!),
        Btn('${l.playAgain} · ${l.sameNew}', key: const Key('playAgain'), icon: Icons.replay, onTap: _h(() => c.send({'t': 'deal'}))),
        Btn(l.toLobby, key: const Key('toLobby'), ghost: true, onTap: _h(() => c.send({'t': 'lobby'}))),
      ] else
        Text(l.waitHost, textAlign: TextAlign.center, style: TextStyle(color: C.dim)),
      // [S19 P2] online games only (a Wi-Fi game has no id on the server)
      if (!widget.lan && widget.account.signedIn && c.room?['gameId'] is String && view['seat'] is int) // [Quin Q7] a seated player
        TextButton.icon(key: const Key('reportGame'), icon: Icon(Icons.bug_report_outlined, size: 18, color: C.mute), label: Text(l.fbReportGame, style: TextStyle(color: C.mute)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FeedbackScreen(account: widget.account, gameId: c.room!['gameId'] as String)))),
    ], children: [
      // [S15-4] the old app's recap card
      RecapCard(winner: winner, days: rc['day'] as int, sheikh: rc['sheikh'] as int?, framer: rc['framer'] as int?, silencer: rc['silencer'] as int?, took: {for (final x in stats.guards) x.$1},
          players: [for (var i = 0; i < roles.length; i++) (name: _name(i), role: roles[i], alive: alive[i])],
          best: best == null ? null : (name: _name(best.seat), role: roles[best.seat], why: mvpWhy(l, best.why, best.n))),
    ]);
  }
}
