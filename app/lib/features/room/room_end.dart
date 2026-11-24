part of 'room_screen.dart';

extension _EndViews on _RoomScreenState {
  Widget _end(L l, Map<String, Object?> view) {
    if (!revealed) return _suspense(l, l.gameOver, C.glory, Icons.emoji_events_outlined);
    final rc = Map<String, Object?>.from(view['recap'] as Map), mafia = rc['winner'] == 'mafia';
    final roles = (rc['roles'] as List).map((x) => Role.values.byName(x as String)).toList(), alive = (rc['alive'] as List).cast<bool>();
    final st = rc['stats'] as Map;
    final stats = Stats(first: st['first'] as int?, kills: (st['kills'] as List).cast<int>(), outs: (st['outs'] as List).cast<int>(),
        saves: (st['saves'] as List).cast<int>(), caught: [for (final p in (st['caught'] as List)) ((p as List)[0] as int, p[1] as int)]);
    final best = mvp(mafia ? Winner.mafia : Winner.citizens, roles, alive, stats), valid = c.room?['valid'];
    return Stage(card: true, color: mafia ? C.blood : C.glory, center: false, bottom: [
      if (c.isHost) ...[
        if (c.room?['gameId'] != null) Row(children: [
          Expanded(child: Btn(l.valid, key: const Key('markValid'), ghost: valid != true, onTap: _h(() => c.send({'t': 'mark', 'valid': true})))),
          const SizedBox(width: 10),
          Expanded(child: Btn(l.invalid, key: const Key('markInvalid'), ghost: valid != false, onTap: _h(() => c.send({'t': 'mark', 'valid': false})))),
        ]),
        if (widget.lan && _wifiKey != null) WifiApproval(account: widget.account, prefs: widget.prefs, gameKey: _wifiKey!),
        Btn('${l.playAgain} · ${l.sameNew}', key: const Key('playAgain'), icon: Icons.replay, onTap: _h(() => c.send({'t': 'deal'}))),
        Btn(l.toLobby, key: const Key('toLobby'), ghost: true, onTap: _h(() => c.send({'t': 'lobby'}))),
      ] else
        Text(l.waitHost, textAlign: TextAlign.center, style: TextStyle(color: C.dim)),
    ], children: [
      const SizedBox(height: 12),
      Big(mafia ? l.winMafia : l.winCitizens, sub: mafia ? l.winMafiaD : l.winCitizensD, color: mafia ? C.red2 : C.gold, size: 36),
      Padding(padding: const EdgeInsets.only(top: 6, bottom: 18), child: Text(l.rcSub(roles.length, rc['day'] as int), textAlign: TextAlign.center, style: TextStyle(color: C.dim))),
      if (best != null)
        Sec(title: l.mvpT, child: Row(children: [
          Icon(roleIcon(roles[best.seat]), color: roleColor(roles[best.seat])), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name(best.seat), style: head.copyWith(fontSize: 20)),
            Text(switch (best.why) { 'mafia' => l.mvpMafia, 'mafia2' => l.mvpMafia2, 'det' => l.mvpDet(best.n ?? 1), 'doc' => l.mvpDoc(best.n ?? 1), _ => l.mvpSurv },
                style: TextStyle(color: C.mute)),
          ])),
        ])),
      Sec(title: l.roles, child: Column(children: [
        for (var i = 0; i < roles.length; i++)
          Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
            Icon(roleIcon(roles[i]), size: 18, color: roleColor(roles[i])), const SizedBox(width: 8),
            Expanded(child: Text(_name(i), style: TextStyle(decoration: alive[i] ? null : TextDecoration.lineThrough, color: alive[i] ? C.text : C.mute))),
            Text(roleName(l, roles[i]), style: TextStyle(color: roleColor(roles[i]))),
          ])),
      ])),
    ]);
  }
}
