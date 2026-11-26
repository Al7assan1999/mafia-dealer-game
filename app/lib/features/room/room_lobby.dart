part of 'room_screen.dart';

extension _LobbyViews on _RoomScreenState {
  // ---------------------------------------------------------------- lobby
  Widget _lobby(L l) {
    final room = c.room!, host = c.isHost, ms = c.members;
    final rules = defaultRules.merge(Map<String, Object?>.from(room['rules'] as Map));
    final counts = Counts((room['counts'] as Map)['mafia'] as int, 1, (room['counts'] as Map)['detective'] as int);
    final mode = modes.contains(room['mode']) ? room['mode'] as String : 'classic'; // a server before 1.0.0 sends none
    final bg = room['bodyguard'] == true; // [S18] the Sniper and Jester modes' optional Bodyguard
    final v = validateSetup([for (var i = 0; i < ms.length; i++) 'p$i'], counts, mode, bg, rules);
    // [S17-4, his ruling] a phone older than 1.0.0 can't be dealt in, Classic too (the server refuses the deal as well);
    // every phone counts, mine included, as on the server
    final old = ms.where((m) => !(m['v'] is int && (m['v'] as int) >= modesBuild)).toList();
    // [S20] Avenger and Shadows: every phone on 1.3.0 (the server refuses the deal too)
    final old13 = newMode(mode) ? ms.where((m) => !(m['v'] is int && (m['v'] as int) >= roles13Build)).toList() : const [];
    void setup(Counts cc, Rules rr, [Mode? mm, bool? bb]) => c.send({'t': 'setup', 'rules': rr.toJson(), 'counts': {'mafia': cc.mafia, 'detective': cc.detective}, 'buzzMax': room['buzzMax'] ?? 3,
      if (room['kick'] != null) 'kick': room['kick'], 'mode': mm ?? mode, 'bodyguard': bb ?? bg});
    return Stage(center: false, bottom: [
      if (host) ...[
        Text([l.playersCount(ms.length), modeName(l, mode), '${v.counts.mafia} ${l.mafia}', l.doctor, if (v.counts.detective > 0) l.detective,
              if (v.counts.sniper > 0) l.sniper, if (v.counts.jester > 0) l.jester, if (v.counts.bodyguard > 0) l.bodyguard,
              if (v.counts.hunter > 0) l.hunter, if (v.counts.mayor > 0) l.mayor, if (v.counts.watcher > 0) l.watcher].join(' · '),
            key: const Key('dealSummary'), textAlign: TextAlign.center, style: TextStyle(color: C.mute)),
        if (old.isNotEmpty) Text(l.eOldApp, key: const Key('oldAppNote'), textAlign: TextAlign.center, style: TextStyle(color: C.red2))
        else if (old13.isNotEmpty) Text('${l.eOldApp13}: ${old13.map((m) => m['display']).join(', ')}', key: const Key('oldApp13'), textAlign: TextAlign.center, style: TextStyle(color: C.red2)),
        if (v.error == 'modeFew') Text(l.eModeFew(modeMin[mode]!), textAlign: TextAlign.center, style: TextStyle(color: C.red2)),
        for (final m in ms.where((m) => m['online'] == false))
          Text(l.offlineDealt(m['display'] as String), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD9A441))),
        if (ms.length < minPlayers) Text(l.eNoMembers, textAlign: TextAlign.center, style: TextStyle(color: C.red2)),
        Btn(l.deal, key: const Key('deal'), icon: Icons.style_outlined, onTap: v.error == null && old.isEmpty && old13.isEmpty ? _h(() => c.send({'t': 'deal'})) : null),
        Row(children: [
          if (!widget.lan) ...[
            Expanded(child: Btn(l.inviteFriends, key: const Key('inviteFriends'), ghost: true, onTap: () => _inviteSheet(l))),
            const SizedBox(width: 10),
          ],
          Expanded(child: Btn(l.closeRoom, key: const Key('closeRoom'), ghost: true, onTap: () async {
            if (await ask(context, l.closeRoomQ, l.closeRoomD, l.closeRoom)) c.send({'t': 'close'});
          })),
        ]),
      ] else ...[
        Text(l.waitHost, textAlign: TextAlign.center, style: TextStyle(color: C.mute)),
        const SizedBox(height: 10),
        // [R7] the old app's "Buzz the host" while waiting; muted at the host's limit
        if (c.members.any((m) => m['uid'] == c.myUid && m['muted'] == true))
          Text(l.buzzMutedMe, key: const Key('buzzMuted'), textAlign: TextAlign.center, style: TextStyle(color: C.dim))
        else
          Btn(l.buzz, key: const Key('buzzHost'), icon: Icons.campaign_outlined, onTap: _h(() { c.send({'t': 'buzz'}); _flash(l.buzzSent); })),
      ],
    ], children: [
      Sec(child: Column(children: [
        Text(widget.code, key: const Key('code'), style: head.copyWith(fontSize: 44, letterSpacing: 10, color: C.gold)),
        if (_myAddress != null) Text(l.hostAddress(_myAddress!), key: const Key('myAddress'), style: TextStyle(color: C.mute)), // [QA] U2
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(key: const Key('shareCode'), icon: const Icon(Icons.share_outlined), label: Text(l.share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: l.shareRoomTxt(widget.code)))),
          TextButton.icon(key: const Key('copyCode'), icon: const Icon(Icons.copy), label: Text(l.copy), onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.code));
            toast(context, l.copied);
          }),
        ]),
      ])),
      // [1.1.1 hotfix, his note] the cards use the whole width again (S15 kept 24 dp clear for the side tabs): the tabs
      // float over them and drag up and down out of the way
      // [R7] the old app's "Ping everyone" on the player list's title row
      Sec(title: l.membersN(ms.length), action: host && ms.length > 1 ? TextButton.icon(key: const Key('pingAll'), style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: Icon(Icons.notifications_active_outlined, size: 18, color: C.red2), label: Text(l.ping, style: TextStyle(color: C.red2)),
            onPressed: _h(() { c.send({'t': 'ping'}); _flash(l.pingSent); })) : null,
          child: Column(children: [for (final m in ms) _member(l, m, host)])),
      // [S20] a mode with a Mafia range starts at its default
      ModePicker(players: ms.length, mode: mode, onChanged: host ? (mm) => setup(Counts(mafiaRange(mm, ms.length, rules)?.def ?? counts.mafia, 1, counts.detective), rules, mm) : null,
          bodyguard: bg, onBodyguard: host ? (bb) => setup(counts, rules, null, bb) : null),
      DeckEditor(players: ms.length, counts: v.counts, mode: mode, rules: rules, onChanged: host ? (cc) => setup(cc, rules) : null),
      RulesEditor(rules: rules, onChanged: host ? (rr) => setup(counts, rr) : null),
    ]);
  }

  Widget _member(L l, Map<String, Object?> m, bool host) {
    final me = m['uid'] == c.myUid, av = Map<String, Object?>.from(m['avatar'] as Map);
    // N2: in an online room every member is an account: a tap opens their profile
    return InkWell(key: Key('member_${m['cn']}'), onTap: widget.lan ? null : () => openProfile(context, widget.account,
        Person({'id': m['uid'], 'handle': m['handle'], 'display': m['display'], 'avatar': av, 'fav': '', 'rel': me ? 'me' : 'none'})), child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        AvatarView(api: widget.account.api, id: m['uid'] as String, preset: av['preset'] as int?, photo: av['photo'] as int?, size: 36, online: m['online'] == true),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text('${m['display']}${me ? ' (${l.you})' : ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
            if (m['host'] == true) Padding(padding: EdgeInsetsDirectional.only(start: 6), child: Icon(Icons.workspace_premium, color: C.gold, size: 18)),
          ]),
          Text([if (m['handle'] != null) atHandle(m['handle'] as String), if (m['ready'] == true) l.readyTag, if (m['muted'] == true) l.mutedTag].join(' · '),
              style: TextStyle(color: C.mute, fontSize: 12)),
          if (!me && m['v'] is int && (m['v'] as int) >= modesBuild && (m['v'] as int) < roomBuild)
            Text(l.oldVersion, key: Key('oldVersion_${m['cn']}'), style: TextStyle(color: C.gold, fontSize: 12)),
          if (!(m['v'] is int && (m['v'] as int) >= modesBuild))
            Text(l.eModeOld, key: Key('modeOld_${m['cn']}'), style: TextStyle(color: C.red2, fontSize: 12)),
        ])),
        if (!me)
          SafetyMenu(
            account: widget.account, userId: m['uid'] as String, name: m['display'] as String, safety: !widget.lan,
            extra: [
              if (host) PopupMenuItem(value: 'kick', child: Text(l.kick)),
              if (host && m['muted'] == true) PopupMenuItem(value: 'unmute', child: Text(l.unmute)),
            ],
            onExtra: (x) async {
              if (x == 'unmute') return c.send({'t': 'unmute', 'uid': m['uid']});
              if (await ask(context, l.kickQ(m['display'] as String), l.kickD, l.kick)) c.send({'t': 'kick', 'uid': m['uid']});
            },
          ),
      ]),
    ));
  }

  Future<void> _inviteSheet(L l) async {
    final a = widget.account;
    await a.loadFriends().catchError((_) {});
    if (!mounted) return;
    final sent = <String>{};
    await showModalBottomSheet(context: context, backgroundColor: C.card, builder: (_) => StatefulBuilder(builder: (ctx, set) {
      final fs = [...a.friends]..sort((x, y) => (y.online ? 1 : 0) - (x.online ? 1 : 0));
      final inRoom = c.members.map((m) => m['uid']).toSet();
      return SafeArea(child: ListView(padding: const EdgeInsets.all(16), shrinkWrap: true, children: [
        Text(l.inviteFriends, style: head.copyWith(fontSize: 20)),
        if (fs.isEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(l.fNone, style: TextStyle(color: C.mute))),
        for (final f in fs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AvatarView.of(a.api, f, size: 36, online: f.online),
            title: Text(f.display),
            subtitle: Text(atHandle(f.handle), style: TextStyle(color: C.mute)),
            trailing: inRoom.contains(f.id) ? null : TextButton(
              key: Key('invite_${f.handle}'),
              onPressed: sent.contains(f.id) ? null : () async {
                try { await a.invite(f.id, widget.code); set(() => sent.add(f.id)); } catch (e) { if (ctx.mounted) toast(ctx, errText(l, e)); }
              },
              child: Text(sent.contains(f.id) ? l.invited : l.invite, style: TextStyle(color: C.red2)),
            ),
          ),
      ]));
    }));
  }

  // ---------------------------------------------------------------- the game
}
