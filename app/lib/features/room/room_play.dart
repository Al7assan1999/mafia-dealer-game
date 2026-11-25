part of 'room_screen.dart';

extension _PlayViews on _RoomScreenState {
  // [S15-6] "Round 1 · 6/6 alive" under the online game screens too
  String? _foot(L l) {
    final r = (v?['roster'] as List?)?.cast<Map>();
    return r == null || r.isEmpty ? null : l.roundAlive(v?['day'] as int? ?? 1, r.where((x) => x['alive'] == true).length, r.length);
  }
  List<Widget> _hostBar(L l, Map<String, Object?> view, List<Widget> extra) {
    if (!c.isHost) return const [];
    final p = view['progress'] as Map?, offline = c.members.any((m) => m['seat'] != null && m['online'] == false);
    final ph = view['phase'];
    return [
      ...extra,
      if ((ph == 'night' || ph == 'vote') && offline && p != null && (p['done'] as int) < (p['total'] as int))
        Btn(l.continueAnyway, key: const Key('continue'), ghost: true, onTap: _h(() => c.send({'t': 'continue'}))),
    ];
  }

  Widget _progress(L l, Map<String, Object?> view) {
    final p = view['progress'] as Map?;
    return p == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12),
        child: Text(l.progressN(p['done'] as int, p['total'] as int), key: const Key('progress'), textAlign: TextAlign.center, style: TextStyle(color: C.mute)));
  }

  Widget _deal(L l, Map<String, Object?> view) {
    final role = roleOf(view['role']);
    final meReady = c.members.any((m) => m['uid'] == c.myUid && m['ready'] == true), ms = c.members;
    // [1.0.1 hotfix] the host's Start is not on the role card (it was taken for "next" and skipped everyone's card):
    // it shows once the host is ready, and asks first
    final start = [if (c.isHost) Btn(l.startNow, key: const Key('start'), ghost: true, onTap: _h(() async {
      if (await ask(context, l.startNowQ, l.startNowD, l.startNow)) c.send({'t': 'start'});
    }))];
    if (role == null) return Stage(card: true, foot: _foot(L.of(context)), children: [Big(l.waitHost)]);
    if (meReady) {
      return Stage(card: true, foot: _foot(L.of(context)), bottom: start, children: [
        Icon(roleIcon(role), color: roleColor(role), size: 56), const SizedBox(height: 12),
        Big(l.readyN(ms.where((m) => m['ready'] == true).length, ms.where((m) => m['seat'] != null).length)),
      ]);
    }
    final me = view['seat'] as int, sh = view['sheikh'] as int?;
    return RoleCard(name: _name(me), role: role, mates: [for (final j in (view['mates'] as List)) _name(j as int)],
        isSheikh: sh == me, sheikh: sh != null && sh != me ? _name(sh) : null,
        done: l.readyBtn, onDone: () => c.send({'t': 'ready', 'deal': c.room!['deal']}));
  }

  Widget _option(String label, Object value, {List<String> tags = const [], bool disabled = false, Color? accent}) =>
      PickRow(key: Key('opt_$value'), label: label, seat: value is int ? value : null, on: _pick == value, tags: tags, accent: accent,
          onTap: disabled ? null : () => _choose(value));

  Widget _night(L l, Map<String, Object?> view) {
    final no = Map<String, Object?>.from(view['night'] as Map), key = no['key'] as String, role = roleOf(view['role'])!;
    // [S18] a Detective who has checked everyone; a Sniper on night 1 (his bullet is ready from night 2)
    final (title, desc) = key == 'none' && role == Role.detective ? (l.allChecked, l.allCheckedD) : nightText(l, key);
    final night1 = role == Role.sniper && (key == 'citizen' || key == 'none') && view['day'] == 1; // [Quin Q4] decoy off: 'none'
    final sh = view['sheikh'] as int?;
    final none = key == 'none', skip = no['skip'] as Map?, secs = _secondsLeft();
    return Stage(card: true, foot: _foot(L.of(context)), color: C.night, center: false, bottom: [
      Btn(l.confirm, key: const Key('confirm'), onTap: none || _pick != null ? () => _send({'t': 'night', 'choice': none ? null : _pick, 'day': view['day']}) : null),
      ..._hostBar(l, view, const []),
    ], children: [
      Row(children: [
        Icon(roleIcon(role), color: roleColor(role)), const SizedBox(width: 8),
        Expanded(child: Text(seatRole(l, role, sh == view['seat']), overflow: TextOverflow.ellipsis, style: head.copyWith(color: roleColor(role), fontSize: 18))),
        const SizedBox(width: 8), Text(l.night(view['day'] as int), style: TextStyle(color: C.mute)),
      ]),
      const SizedBox(height: 14),
      Text(title, style: head.copyWith(fontSize: 26)),
      Text(desc, style: TextStyle(color: C.mute)),
      if (night1) Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.sniperNight1, key: const Key('sniperNight1'), style: TextStyle(color: roleColor(Role.sniper)))),
      if ((view['mates'] as List).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text(l.mates([for (final j in view['mates'] as List) _name(j as int)].join(', ')), style: TextStyle(color: C.red2))),
      // [Ben, S17 review] once the Godfather is out the note says who settles a tie now
      if (key == 'mafia' && sh != null && (view['mates'] as List).isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(((view['roster'] as List)[sh] as Map)['alive'] == true ? l.tieSheikh : l.tieLowest,
            key: const Key('tieSheikh'), style: TextStyle(color: C.mute, fontSize: 13))),
      if (secs != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.nightTimeLeft(secs), key: const Key('nightClock'), style: TextStyle(color: C.red2))),
      const SizedBox(height: 16),
      if (!none)
        for (final o in (no['opts'] as List).cast<Map>())
          _option(_name(o['seat'] as int), o['seat'] as int, disabled: o['disabled'] == true,
              accent: o['teammate'] == true || o['check'] == true ? C.red2 : o['check'] == false ? C.green : null, tags: [
            if (o['self'] == true) l.you,
            if (o['teammate'] == true) l.teammate,
            if (o['check'] is bool) o['check'] == true ? l.mafia : l.notMafia, // [S18-1] checked before: the result, can't be picked again
            if ((o['mateVotes'] as int? ?? 0) > 0) '${l.mateVote} ×${o['mateVotes']}',
            if (o['sheikh'] == true) l.sheikhPick,
            if (o['lastTarget'] == true) l.lastTgt,
            if (o['lastNight'] == true) key == 'bodyguard' ? l.guardedLast : l.lastNight,
          ]),
      if (skip != null && key == 'sniper') _option(l.keepBullet, 'skip', tags: [l.keepBulletD])
      else if (skip != null) _option(l.skipKill, 'skip', tags: [l.skipLeft, if ((skip['mateVotes'] as int? ?? 0) > 0) '${l.mateVote} ×${skip['mateVotes']}',
        if (skip['sheikh'] == true) l.sheikhPick]),
      if (none) _checks(view),
    ]);
  }

  /// [S18 P1] the Detective's results so far (his own phone)
  Widget _checks(Map<String, Object?> view) =>
      ChecksList(checks: [for (final c in (view['checks'] as List? ?? const []).cast<Map>()) (name: _name(c['seat'] as int), mafia: c['mafia'] == true)]);

  Widget _waiting(L l, Map<String, Object?> view, String text, Color color) {
    final check = view['check'] as Map?, secs = view['phase'] == 'night' ? _secondsLeft() : null;
    return Stage(card: true, foot: _foot(L.of(context)), color: color, bottom: _hostBar(l, view, const []), children: [
      Icon(Icons.lock_outline, color: C.mute, size: 48), const SizedBox(height: 14),
      Big(text),
      _progress(l, view),
      if (secs != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.nightTimeLeft(secs), textAlign: TextAlign.center, style: TextStyle(color: C.red2))),
      if (check != null) Padding(padding: const EdgeInsets.only(top: 22), child: Sec(color: C.card2,
          child: Text(l.checkResult(_name(check['seat'] as int), check['mafia'] == true ? l.mafia : l.notMafia), key: const Key('checkResult'),
              textAlign: TextAlign.center, style: head.copyWith(fontSize: 22, color: check['mafia'] == true ? C.red2 : C.green)))),
      if (view['board'] != null) _board(l, view),
    ]);
  }

  Widget _board(L l, Map<String, Object?> view) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Sec(title: l.tableVote, child: Column(children: [
          for (final b in (view['board'] as List).cast<Map>())
            Row(children: [
              Expanded(child: Text(_name(b['seat'] as int))),
              Text(b['v'] == null ? '…' : b['v'] == 'none' ? l.noOne : b['v'] == 'abstain' ? '—' : _name(b['v'] as int), style: TextStyle(color: C.mute)),
            ]),
        ])),
      );

  Widget _dead(L l, Map<String, Object?> view) {
    final roles = view['roles'] as List?;
    return Stage(card: true, foot: _foot(L.of(context)), color: C.blood, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
      Icon(Icons.visibility_outlined, color: C.mute, size: 48), const SizedBox(height: 12),
      Big(l.youAreOut, sub: l.youAreOutD),
      _progress(l, view),
      if (roles != null) Padding(padding: const EdgeInsets.only(top: 18), child: Sec(title: l.roles, child: Column(children: [
        for (var i = 0; i < roles.length; i++)
          if (roleOf(roles[i]) case final r?)
            Row(children: [Expanded(child: Text(_name(i))), Text(roleName(l, r), style: TextStyle(color: roleColor(r)))]),
      ]))),
    ]);
  }

  /// The host's buttons for the phase the table is in (also shown when the host is out).
  List<Widget> _phaseButtons(L l, Map<String, Object?> view) => switch (view['phase']) {
        'morning' => [if (revealed) Btn(l.startDay(view['day'] as int), key: const Key('startDay'), onTap: _h(() => c.send({'t': 'startDay'})))],
        'day' => [
            Btn(l.secretVoteOnline, key: const Key('secretVote'), onTap: _h(() => c.send({'t': 'startVote', 'open': false}))),
            Text(l.secretVoteOnlineD, textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 12)),
            Btn(l.tableVoteOnline, key: const Key('tableVote'), ghost: true, onTap: _h(() => c.send({'t': 'startVote', 'open': true}))),
            Text(l.tableVoteOnlineD, textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 12)),
          ],
        'verdict' => [if (revealed) Btn(l.nextNight((view['day'] as int) + 1), key: const Key('nextNight'), onTap: _h(() => c.send({'t': 'nextNight'})))],
        _ => const [],
      };

  Widget _suspense(L l, String text, Color color, IconData icon) => Stage(card: true, foot: _foot(L.of(context)), color: color, bottom: [
        Btn(l.skipWait, key: const Key('revealNow'), ghost: true, onTap: _reveal),
      ], children: [
        Icon(icon, color: C.gold, size: 60), const SizedBox(height: 16), Big(text), const SizedBox(height: 18),
        Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: C.mute))),
      ]);

  Widget _morning(L l, Map<String, Object?> view) {
    if (!revealed) return _suspense(l, l.sunrise, C.day, Icons.wb_sunny_outlined);
    final r = Map<String, Object?>.from(view['result'] as Map? ?? const {'k': 'nobody'});
    return Stage(card: true, foot: _foot(L.of(context)), color: r['k'] == 'killed' ? C.blood : C.day, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
      Tag(l.morningOf(view['day'] as int)),
      const SizedBox(height: 24),
      if (r['k'] == 'killed') ...[
        // a mode with a Sniper never says who killed whom (the engine names the dead in seat order)
        Text(r['also'] != null ? l.diedIs : c.room?['mode'] == 'sniper' || c.room?['mode'] == 'all' ? l.diedOne : l.victimIs,
            textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16)),
        for (final x in [r, if (r['also'] case final Map a) a]) ...[
          Big(_name(x['seat'] as int), size: 42, color: C.red2),
          if (roleOf(x['role']) case final xr?) Text(l.wasRole(seatRole(l, xr, x['sheikh'] == true)), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ],
      ] else if (r['k'] == 'saved') ...[
        Text(l.savedIs, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16)),
        Big(_name(r['seat'] as int), size: 42, color: C.green),
      ] else
        Big(l.nobody, color: C.green),
      if (!c.isHost) Padding(padding: const EdgeInsets.only(top: 20), child: Text(l.waitHost, textAlign: TextAlign.center, style: TextStyle(color: C.dim))),
    ]);
  }

  Widget _day(L l, Map<String, Object?> view) {
    final t = view['timer'] as Map?, left = _secondsLeft() ?? 0, running = t?['end'] != null;
    return Stage(card: true, foot: _foot(L.of(context)), color: C.day, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
      Sec(title: l.discussion, child: Column(children: [
        Text(left == 0 && running ? l.timeUp : '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}', key: const Key('clock'),
            style: head.copyWith(fontSize: 52, color: left == 0 ? C.red2 : C.text)),
        if (c.isHost) ...[
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(key: const Key('timerGo'), onPressed: _h(() => c.send({'t': 'timer', 'op': running ? 'pause' : 'start'})), child: Text(running ? l.pause : l.start, style: TextStyle(color: C.text))),
            OutlinedButton(key: const Key('timerAdd'), onPressed: _h(() => c.send({'t': 'timer', 'op': 'add', 'sec': 60})), child: Text(l.plusMin, style: TextStyle(color: C.text))),
            OutlinedButton(key: const Key('timerReset'), onPressed: _h(() => c.send({'t': 'timer', 'op': 'reset'})), child: Text(l.reset, style: TextStyle(color: C.text))),
          ]),
        ],
      ])),
      _roster(l, view),
      _checks(view),
      if (!c.isHost) Text(l.waitHost, textAlign: TextAlign.center, style: TextStyle(color: C.dim)),
    ]);
  }

  /// Who is still in, in seat order (the day is about who's left).
  Widget _roster(L l, Map<String, Object?> view) => Sec(title: l.alivePlayers, child: Wrap(spacing: 8, runSpacing: 6, children: [
        for (final r in (view['roster'] as List).cast<Map>())
          Chip(
            label: Text(r['alive'] == true ? r['name'] as String : '${r['name']} · ${l.outTag}',
                style: TextStyle(color: r['alive'] == true ? C.text : C.dim, decoration: r['alive'] == true ? null : TextDecoration.lineThrough)),
            backgroundColor: r['alive'] == true ? C.card2 : C.bg, side: BorderSide(color: C.line),
          ),
      ]));

  Widget _vote(L l, Map<String, Object?> view) {
    final me = view['seat'] as int;
    return Stage(card: true, foot: _foot(L.of(context)), center: false, bottom: [
      Btn(l.castVote, key: const Key('castVote'), onTap: _pick == null ? null : () => _send({'t': 'vote', 'choice': _pick, 'id': view['voteId']})),
      ..._hostBar(l, view, const []),
    ], children: [
      Text(l.votePick, style: head.copyWith(fontSize: 26)),
      const SizedBox(height: 14),
      for (final o in (view['voteOpts'] as List).cast<Map>()) if (o['seat'] != me) _option(_name(o['seat'] as int), o['seat'] as int),
      _option(l.noOne, 'none'),
      if (view['board'] != null) _board(l, view),
    ]);
  }

  Widget _verdict(L l, Map<String, Object?> view) {
    if (!revealed) return _suspense(l, l.deciding, C.day, Icons.gavel);
    final r = Map<String, Object?>.from(view['result'] as Map? ?? const {'k': 'skipped'}), role = roleOf(r['role']), tally = r['tally'] as List?;
    return Stage(card: true, foot: _foot(L.of(context)), color: r['k'] == 'out' ? C.blood : C.day, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
      if (r['k'] == 'out') ...[
        Text(l.outIs, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16)),
        Big(_name(r['seat'] as int), size: 42, color: C.red2),
        if (role != null) Text(l.wasRole(seatRole(l, role, r['sheikh'] == true)), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
      ] else
        Big(r['k'] == 'tie' ? l.tie : l.skipped),
      if (tally != null && tally.isNotEmpty) ...[
        const SizedBox(height: 22),
        Sec(child: Column(children: [
          for (final t in tally.cast<Map>())
            Row(children: [Expanded(child: Text(t['k'] == 'none' ? l.noOne : _name(t['k'] as int))), Text(l.votesN(t['n'] as int), style: TextStyle(color: C.mute))]),
        ])),
      ],
    ]);
  }

}
