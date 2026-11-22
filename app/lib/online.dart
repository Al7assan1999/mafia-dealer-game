// Online play: create or join a room, the lobby, the game on my own phone (the server judges; I see only my view),
// the host's controls, per-phone narration with its suspense reveal, the connection bar, and my online history.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'account.dart';
import 'account_screens.dart';
import 'audio.dart';
import 'game_screen.dart' show RoleCard;
import 'l10n/app_localizations.dart';
import 'prefs.dart';
import 'room.dart';
import 'setup.dart';
import 'ui.dart';

String roomErr(L l, String? code) => switch (code) {
      'no_room' => l.eNoRoom, 'started' => l.eStarted, 'room_full' => l.eRoomFull, 'kicked' => l.eKicked,
      'forbidden' => l.eForbidden, 'not_open' => l.eNotOpen, 'offline' => l.eOffline, _ => l.eOther,
    };

Role? _role(Object? r) => r is String && r.isNotEmpty ? Role.values.byName(r) : null;

// ---------------------------------------------------------------- create / join
class OnlineHome extends StatefulWidget {
  const OnlineHome({super.key, required this.account, required this.prefs, required this.audio});
  final Account account;
  final Prefs prefs;
  final Audio audio;
  @override
  State<OnlineHome> createState() => _OnlineHomeState();
}

class _OnlineHomeState extends State<OnlineHome> {
  final code = TextEditingController();
  bool busy = false;
  String? error;

  void _open(String c) => Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => RoomScreen(account: widget.account, prefs: widget.prefs, audio: widget.audio, code: c)));

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), a = widget.account;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.online, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, children: [
        Text(l.onlineSub, style: const TextStyle(color: C.mute)),
        const SizedBox(height: 18),
        if (!a.signedIn) ...[
          Text(l.onlineNeedsAccount),
          const SizedBox(height: 12),
          Btn(l.aIn, onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SignInScreen(account: a)))),
        ] else ...[
          Btn(l.createRoom, key: const Key('createRoom'), icon: Icons.add_home_outlined, onTap: busy ? null : () async {
            setState(() { busy = true; error = null; });
            try { _open(await a.createRoom()); } catch (e) { if (mounted) setState(() => error = errText(l, e)); }
            if (mounted) setState(() => busy = false);
          }),
          const SizedBox(height: 22),
          Text(l.joinCode, style: head.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(key: const Key('roomCode'), controller: code, maxLength: 6, keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(hintText: l.codeHint, counterText: ''),
                style: head.copyWith(fontSize: 22, letterSpacing: 6))),
            const SizedBox(width: 10),
            FilledButton(key: const Key('joinRoom'), style: FilledButton.styleFrom(backgroundColor: C.red),
                onPressed: () { if (code.text.length == 6) _open(code.text); }, child: Text(l.join)),
          ]),
        ],
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, key: const Key('error'), style: const TextStyle(color: C.red2))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- the room
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.account, required this.prefs, required this.audio, required this.code, this.connect});
  final Account account;
  final Prefs prefs;
  final Audio audio;
  final String code;
  final Connector? connect; // tests pass a scripted server
  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  late final RoomConn c = RoomConn(widget.account.api, widget.code, connect: widget.connect ?? ioConnect);
  StreamSubscription<dynamic>? _n, _s;
  Timer? _tick, _arm;
  bool revealed = true; // the morning / verdict / end result is held until my narrator says the name
  bool _timeUpSaid = false;
  Object? _pick;
  Audio get audio => widget.audio;
  RoomConn get conn => c; // for the tests

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    audio.muted = !widget.prefs.narrate;
    _n = c.narration.listen(_narrate);
    _s = c.side.listen(_onSide);
    c.addListener(_changed);
    c.start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { _checkTimeUp(); if (mounted) setState(() {}); });
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _n?.cancel(); _s?.cancel(); _tick?.cancel(); _arm?.cancel();
    c.removeListener(_changed);
    c.dispose();
    audio.stop();
    audio.muted = false;
    WakelockPlus.disable().catchError((_) {});
    widget.account.reloadMe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) => c.foreground(s == AppLifecycleState.resumed);

  Map<String, Object?>? get v => c.view;
  List<String> get names => [for (final r in (v?['roster'] as List? ?? const [])) (r as Map)['name'] as String];
  String _name(int seat) => seat >= 0 && seat < names.length ? names[seat] : '?';

  void _changed() {
    final err = c.error;
    if (err != null && mounted && c.room != null) { toast(context, roomErr(L.of(context), err)); c.error = null; }
    if (mounted) setState(() {});
  }

  void _onSide(Map<String, Object?> m) {
    if (!mounted) return;
    final l = L.of(context);
    if (m['t'] == 'buzz') {
      final who = c.members.where((x) => x['uid'] == m['from']).firstOrNull;
      toast(context, l.buzzed((who?['display'] as String?) ?? '?'));
      HapticFeedback.heavyImpact();
    } else if (m['t'] == 'ping') {
      toast(context, l.pinged);
      HapticFeedback.mediumImpact();
    }
  }

  // ---------------------------------------------------------------- narration and the suspense reveal
  void _armReveal(double sec) {
    _arm?.cancel();
    _arm = Timer(Duration(milliseconds: (sec.clamp(0, 30) * 1000).round()), _reveal);
  }

  void _reveal() {
    _arm?.cancel();
    if (revealed || !mounted) return;
    final r = v?['result'] as Map?, ph = v?['phase'];
    final bad = (ph == 'morning' && r?['k'] == 'killed') || (ph == 'verdict' && r?['k'] == 'out') || (ph == 'end' && v?['winner'] == 'mafia');
    setState(() => revealed = true);
    if (ph != 'end') audio.hit(bad);
  }

  /// Narrates what just happened. After a reconnect only the latest phase, and only if the game is still in it.
  void _narrate(({List<Map<String, Object?>> events, Map<String, Object?>? view}) n) {
    final view = n.view;
    if (view == null || c.missed) return;
    final ph = n.events.lastWhere((e) => e['t'] == 'phase', orElse: () => const {})['phase'];
    if (ph == null || ph != view['phase']) return;
    final r = view['result'] as Map?, rules = (c.room?['rules'] as Map?) ?? const {};
    String? nm(Object? seat) => seat is int ? _name(seat) : null;
    String? roleOf(Object? x) => rules['reveal'] == true ? x as String? : null;
    switch (ph) {
      case 'deal': audio.welcome();
      case 'night': audio.night();
      case 'day': _timeUpSaid = false; audio.day();
      case 'morning':
        setState(() => revealed = false);
        audio.morning(r?['k'] == 'killed' ? nm(r?['seat']) : null, r?['k'] == 'killed' ? roleOf(r?['role']) : null,
            r?['k'] == 'saved' ? nm(r?['seat']) : null, _armReveal);
      case 'verdict':
        setState(() => revealed = false);
        audio.verdict(r?['k'] == 'out' ? nm(r?['seat']) : null, r?['k'] == 'out' ? roleOf(r?['role']) : null, (r?['k'] as String?) ?? 'skipped', _armReveal);
      case 'end':
        setState(() => revealed = false);
        final win = n.events.lastWhere((e) => e['t'] == 'win', orElse: () => const {}), lead = win['lead'] as Map?;
        final roles = (view['roles'] as List? ?? const []).cast<String>();
        final clips = lead == null ? <String?>[] : audio.lead(lead['k'] as String, _name(lead['seat'] as int), roleOf(roles[lead['seat'] as int]));
        final mafia = [for (var i = 0; i < roles.length; i++) if (roles[i] == 'mafia') _name(i)];
        view['winner'] == 'mafia' ? audio.mafiaWin(mafia, clips, _armReveal) : audio.citizensWin(mafia, clips, _armReveal);
    }
  }

  int? _secondsLeft() {
    final t = v?['timer'] as Map?;
    if (t == null) return null;
    if (t['left'] != null) return t['left'] as int;
    return ((((t['end'] as int) - DateTime.now().millisecondsSinceEpoch) / 1000).ceil()).clamp(0, 99999);
  }

  void _checkTimeUp() {
    if (v?['phase'] == 'day' && (v?['timer'] as Map?)?['end'] != null && _secondsLeft() == 0 && !_timeUpSaid) {
      _timeUpSaid = true;
      audio.timeUp();
    }
  }

  void _send(Map<String, Object?> m) { c.send(m); setState(() => _pick = null); }

  Future<void> _leave() async {
    final l = L.of(context);
    if (c.bye != null || await ask(context, l.leaveRoomQ, l.leaveRoomD, l.leaveRoom)) {
      if (c.bye == null) c.send({'t': 'leave'});
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------- screens
  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _leave(); },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: C.bg,
          title: Text(l.roomCode(widget.code), style: head.copyWith(fontSize: 20)),
          actions: [
            IconButton(key: const Key('narrate'), tooltip: l.narrateHere,
                icon: Icon(widget.prefs.narrate ? Icons.volume_up_outlined : Icons.volume_off_outlined, color: C.mute),
                onPressed: () => setState(() { widget.prefs.narrate = !widget.prefs.narrate; audio.muted = !widget.prefs.narrate; if (audio.muted) audio.stop(); })),
            if (c.view != null && !c.isHost) IconButton(key: const Key('buzz'), tooltip: l.buzz, icon: const Icon(Icons.campaign_outlined, color: C.mute), onPressed: () => c.send({'t': 'buzz'})),
            if (c.view != null && c.isHost) IconButton(key: const Key('ping'), tooltip: l.ping, icon: const Icon(Icons.notifications_active_outlined, color: C.mute), onPressed: () => c.send({'t': 'ping'})),
            IconButton(key: const Key('leave'), tooltip: l.leaveRoom, icon: const Icon(Icons.logout, color: C.mute), onPressed: _leave),
          ],
        ),
        body: Column(children: [
          _bar(l),
          Expanded(child: KeyedSubtree(key: ValueKey('${v?['phase']}/${v?['ph']}/${v?['day']}/$revealed'), child: _screen(l))),
        ]),
      ),
    );
  }

  /// The connection bar (only when something is wrong, and green for 2 s when it's fixed).
  Widget _bar(L l) {
    String? text;
    Color color = C.red;
    if (c.link == Link.down) {
      text = l.connLost;
    } else if (c.link == Link.weak) {
      text = l.connWeak; color = const Color(0xFFB07A1F);
    } else if (c.link == Link.back) {
      text = l.connBack; color = const Color(0xFF3F7A4B);
    } else if (c.room?['status'] == 'game') {
      final gone = c.members.where((m) => m['seat'] != null && m['online'] == false).firstOrNull;
      if (gone != null) { text = l.connOther(gone['display'] as String); color = const Color(0xFFB07A1F); }
    }
    if (text == null) return const SizedBox.shrink();
    return Container(key: const Key('connBar'), width: double.infinity, color: color, padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.priText, fontWeight: FontWeight.w700)));
  }

  Widget _screen(L l) {
    if (c.bye != null) {
      return Stage(bottom: [Btn(l.home, onTap: () => Navigator.of(context).pop())], children: [
        Big(c.bye == 'kicked' ? l.eKicked : c.bye == 'closed' ? l.roomClosed : l.leaveRoom),
      ]);
    }
    if (c.room == null) {
      return Stage(bottom: [if (c.error != null) Btn(l.home, onTap: () => Navigator.of(context).pop())], children: [
        if (c.error != null) Big(roomErr(l, c.error), color: C.red2) else const Center(child: CircularProgressIndicator(color: C.red2)),
      ]);
    }
    final view = v;
    if (view == null) return _lobby(l);
    final ph = view['ph'] as String?, phase = view['phase'] as String;
    if (phase == 'deal') return _deal(l, view);
    if (phase == 'end') return _end(l, view);
    if (ph == 'night') return _night(l, view);
    if (ph == 'vote') return _vote(l, view);
    if (ph == 'dead') return _dead(l, view);
    return switch (phase) {
      'night' => _waiting(l, view, l.lockedWait, C.night),
      'vote' => _waiting(l, view, l.votedWait, C.day),
      'morning' => _morning(l, view),
      'day' => _day(l, view),
      'verdict' => _verdict(l, view),
      _ => Stage(children: [Big(l.waitHost)]),
    };
  }

  // ---------------------------------------------------------------- lobby
  Widget _lobby(L l) {
    final room = c.room!, host = c.isHost, ms = c.members;
    final rules = defaultRules.merge(Map<String, Object?>.from(room['rules'] as Map));
    final counts = Counts((room['counts'] as Map)['mafia'] as int, 1, (room['counts'] as Map)['detective'] as int);
    final v = validateSetup([for (var i = 0; i < ms.length; i++) 'p$i'], counts);
    void setup(Counts cc, Rules rr) => c.send({'t': 'setup', 'rules': rr.toJson(), 'counts': {'mafia': cc.mafia, 'detective': cc.detective}, 'buzzMax': room['buzzMax'] ?? 3});
    return Stage(center: false, bottom: [
      if (host) ...[
        if (ms.length < minPlayers) Text(l.eNoMembers, textAlign: TextAlign.center, style: const TextStyle(color: C.red2)),
        Btn(l.deal, key: const Key('deal'), icon: Icons.style_outlined, onTap: v.error == null ? () => c.send({'t': 'deal'}) : null),
        Row(children: [
          Expanded(child: Btn(l.inviteFriends, key: const Key('inviteFriends'), ghost: true, onTap: () => _inviteSheet(l))),
          const SizedBox(width: 10),
          Expanded(child: Btn(l.closeRoom, key: const Key('closeRoom'), ghost: true, onTap: () async {
            if (await ask(context, l.closeRoomQ, l.closeRoomD, l.closeRoom)) c.send({'t': 'close'});
          })),
        ]),
      ] else
        Text(l.waitHost, textAlign: TextAlign.center, style: const TextStyle(color: C.mute)),
    ], children: [
      Sec(child: Column(children: [
        Text(widget.code, key: const Key('code'), style: head.copyWith(fontSize: 44, letterSpacing: 10, color: C.gold)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(key: const Key('shareCode'), icon: const Icon(Icons.share_outlined), label: Text(l.share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: l.shareRoomTxt(widget.code)))),
          TextButton.icon(key: const Key('copyCode'), icon: const Icon(Icons.copy), label: Text(l.copy), onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.code));
            toast(context, l.copied);
          }),
        ]),
      ])),
      Sec(title: l.membersN(ms.length), child: Column(children: [for (final m in ms) _member(l, m, host)])),
      DeckEditor(players: ms.length, counts: v.counts, onChanged: host ? (cc) => setup(cc, rules) : null),
      RulesEditor(rules: rules, onChanged: host ? (rr) => setup(counts, rr) : null),
    ]);
  }

  Widget _member(L l, Map<String, Object?> m, bool host) {
    final me = m['uid'] == c.myUid, av = Map<String, Object?>.from(m['avatar'] as Map);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        AvatarView(api: widget.account.api, id: m['uid'] as String, preset: av['preset'] as int?, photo: av['photo'] as int?, size: 36, online: m['online'] == true),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text('${m['display']}${me ? ' (${l.you})' : ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
            if (m['host'] == true) const Padding(padding: EdgeInsetsDirectional.only(start: 6), child: Icon(Icons.workspace_premium, color: C.gold, size: 18)),
          ]),
          Text([if (m['handle'] != null) '@${m['handle']}', if (m['ready'] == true) l.readyTag, if (m['muted'] == true) l.mutedTag].join(' · '),
              style: const TextStyle(color: C.mute, fontSize: 12)),
        ])),
        if (host && !me)
          PopupMenuButton<String>(
            key: Key('menu_${m['handle']}'),
            icon: const Icon(Icons.more_vert, color: C.dim),
            onSelected: (x) async {
              if (x == 'unmute') return c.send({'t': 'unmute', 'uid': m['uid']});
              if (await ask(context, l.kickQ(m['display'] as String), l.kickD, l.kick)) c.send({'t': 'kick', 'uid': m['uid']});
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'kick', child: Text(l.kick)),
              if (m['muted'] == true) PopupMenuItem(value: 'unmute', child: Text(l.unmute)),
            ],
          ),
      ]),
    );
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
        if (fs.isEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(l.fNone, style: const TextStyle(color: C.mute))),
        for (final f in fs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AvatarView.of(a.api, f, size: 36, online: f.online),
            title: Text(f.display),
            subtitle: Text('@${f.handle ?? ''}', style: const TextStyle(color: C.mute)),
            trailing: inRoom.contains(f.id) ? null : TextButton(
              key: Key('invite_${f.handle}'),
              onPressed: sent.contains(f.id) ? null : () async {
                try { await a.invite(f.id, widget.code); set(() => sent.add(f.id)); } catch (e) { if (ctx.mounted) toast(ctx, errText(l, e)); }
              },
              child: Text(sent.contains(f.id) ? l.invited : l.invite, style: const TextStyle(color: C.red2)),
            ),
          ),
      ]));
    }));
  }

  // ---------------------------------------------------------------- the game
  List<Widget> _hostBar(L l, Map<String, Object?> view, List<Widget> extra) {
    if (!c.isHost) return const [];
    final p = view['progress'] as Map?, offline = c.members.any((m) => m['seat'] != null && m['online'] == false);
    final ph = view['phase'];
    return [
      ...extra,
      if ((ph == 'night' || ph == 'vote') && offline && p != null && (p['done'] as int) < (p['total'] as int))
        Btn(l.continueAnyway, key: const Key('continue'), ghost: true, onTap: () => c.send({'t': 'continue'})),
    ];
  }

  Widget _progress(L l, Map<String, Object?> view) {
    final p = view['progress'] as Map?;
    return p == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12),
        child: Text(l.progressN(p['done'] as int, p['total'] as int), key: const Key('progress'), textAlign: TextAlign.center, style: const TextStyle(color: C.mute)));
  }

  Widget _deal(L l, Map<String, Object?> view) {
    final role = _role(view['role']);
    final meReady = c.members.any((m) => m['uid'] == c.myUid && m['ready'] == true), ms = c.members;
    final start = [if (c.isHost) Btn(l.startNow, key: const Key('start'), ghost: true, onTap: () => c.send({'t': 'start'}))];
    if (role == null) return Stage(children: [Big(l.waitHost)]);
    if (meReady) {
      return Stage(bottom: start, children: [
        Icon(roleIcon(role), color: roleColor(role), size: 56), const SizedBox(height: 12),
        Big(l.readyN(ms.where((m) => m['ready'] == true).length, ms.where((m) => m['seat'] != null).length)),
      ]);
    }
    return RoleCard(name: _name(view['seat'] as int), role: role, mates: [for (final j in (view['mates'] as List)) _name(j as int)],
        done: l.readyBtn, onDone: () => c.send({'t': 'ready', 'deal': c.room!['deal']}), extra: start);
  }

  Widget _option(String label, Object value, {List<String> tags = const [], bool disabled = false, Color? accent}) {
    final on = _pick == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: disabled ? .4 : 1,
        child: InkWell(
          key: Key('opt_$value'),
          onTap: disabled ? null : () => setState(() => _pick = value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: on ? const Color(0xFF3A1512) : C.card, border: Border.all(color: on ? C.red : C.line, width: on ? 2 : 1), borderRadius: BorderRadius.circular(4)),
            child: Row(children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: accent ?? C.text))),
              for (final t in tags) Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: Text(t, style: const TextStyle(color: C.mute, fontSize: 12))),
              if (on) const Padding(padding: EdgeInsetsDirectional.only(start: 8), child: Icon(Icons.check, color: C.red2)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _night(L l, Map<String, Object?> view) {
    final no = Map<String, Object?>.from(view['night'] as Map), key = no['key'] as String, role = _role(view['role'])!;
    final (title, desc) = switch (key) {
      'mafia' => (l.aMafia, l.aMafiaD), 'doctor' => (l.aDoctor, l.aDoctorD), 'detective' => (l.aDetective, l.aDetectiveD),
      'citizen' => (l.aCitizen, l.aCitizenD), _ => (l.aNone, l.aNoneD),
    };
    final none = key == 'none', skip = no['skip'] as Map?, secs = _secondsLeft();
    return Stage(color: C.night, center: false, bottom: [
      Btn(l.confirm, key: const Key('confirm'), onTap: none || _pick != null ? () => _send({'t': 'night', 'choice': none ? null : _pick, 'day': view['day']}) : null),
      ..._hostBar(l, view, const []),
    ], children: [
      Row(children: [
        Icon(roleIcon(role), color: roleColor(role)), const SizedBox(width: 8),
        Text(roleName(l, role), style: head.copyWith(color: roleColor(role), fontSize: 18)),
        const Spacer(), Text(l.night(view['day'] as int), style: const TextStyle(color: C.mute)),
      ]),
      const SizedBox(height: 14),
      Text(title, style: head.copyWith(fontSize: 26)),
      Text(desc, style: const TextStyle(color: C.mute)),
      if ((view['mates'] as List).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text(l.mates([for (final j in view['mates'] as List) _name(j as int)].join(', ')), style: const TextStyle(color: C.red2))),
      if (secs != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.nightTimeLeft(secs), key: const Key('nightClock'), style: const TextStyle(color: C.red2))),
      const SizedBox(height: 16),
      if (!none)
        for (final o in (no['opts'] as List).cast<Map>())
          _option(_name(o['seat'] as int), o['seat'] as int, disabled: o['disabled'] == true, accent: o['teammate'] == true ? C.red2 : null, tags: [
            if (o['self'] == true) l.you,
            if (o['teammate'] == true) l.teammate,
            if ((o['mateVotes'] as int? ?? 0) > 0) '${l.mateVote} ×${o['mateVotes']}',
            if (o['lastTarget'] == true) l.lastTgt,
            if (o['lastNight'] == true) l.lastNight,
          ]),
      if (skip != null) _option(l.skipKill, 'skip', tags: [l.skipLeft, if ((skip['mateVotes'] as int? ?? 0) > 0) '${l.mateVote} ×${skip['mateVotes']}']),
    ]);
  }

  Widget _waiting(L l, Map<String, Object?> view, String text, Color color) {
    final check = view['check'] as Map?, secs = view['phase'] == 'night' ? _secondsLeft() : null;
    return Stage(color: color, bottom: _hostBar(l, view, const []), children: [
      const Icon(Icons.lock_outline, color: C.mute, size: 48), const SizedBox(height: 14),
      Big(text),
      _progress(l, view),
      if (secs != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.nightTimeLeft(secs), textAlign: TextAlign.center, style: const TextStyle(color: C.red2))),
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
              Text(b['v'] == null ? '…' : b['v'] == 'none' ? l.noOne : b['v'] == 'abstain' ? '—' : _name(b['v'] as int), style: const TextStyle(color: C.mute)),
            ]),
        ])),
      );

  Widget _dead(L l, Map<String, Object?> view) {
    final roles = view['roles'] as List?;
    return Stage(color: C.blood, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
      const Icon(Icons.visibility_outlined, color: C.mute, size: 48), const SizedBox(height: 12),
      Big(l.youAreOut, sub: l.youAreOutD),
      _progress(l, view),
      if (roles != null) Padding(padding: const EdgeInsets.only(top: 18), child: Sec(title: l.roles, child: Column(children: [
        for (var i = 0; i < roles.length; i++)
          Row(children: [Expanded(child: Text(_name(i))), Text(roleName(l, _role(roles[i])!), style: TextStyle(color: roleColor(_role(roles[i])!)))]),
      ]))),
    ]);
  }

  /// The host's buttons for the phase the table is in (also shown when the host is out).
  List<Widget> _phaseButtons(L l, Map<String, Object?> view) => switch (view['phase']) {
        'morning' => [if (revealed) Btn(l.startDay(view['day'] as int), key: const Key('startDay'), onTap: () => c.send({'t': 'startDay'}))],
        'day' => [
            Btn(l.startBallot, key: const Key('secretVote'), onTap: () => c.send({'t': 'startVote', 'open': false})),
            Btn(l.tableVote, key: const Key('tableVote'), ghost: true, onTap: () => c.send({'t': 'startVote', 'open': true})),
          ],
        'verdict' => [if (revealed) Btn(l.nextNight((view['day'] as int) + 1), key: const Key('nextNight'), onTap: () => c.send({'t': 'nextNight'}))],
        _ => const [],
      };

  Widget _suspense(L l, String text, Color color, IconData icon) => Stage(color: color, bottom: [
        Btn(l.skipWait, key: const Key('revealNow'), ghost: true, onTap: _reveal),
      ], children: [
        Icon(icon, color: C.gold, size: 60), const SizedBox(height: 16), Big(text), const SizedBox(height: 18),
        const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: C.mute))),
      ]);

  Widget _morning(L l, Map<String, Object?> view) {
    if (!revealed) return _suspense(l, l.sunrise, C.day, Icons.wb_sunny_outlined);
    final r = Map<String, Object?>.from(view['result'] as Map? ?? const {'k': 'nobody'}), role = _role(r['role']);
    return Stage(color: r['k'] == 'killed' ? C.blood : C.day, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
      Text(l.morningOf(view['day'] as int).toUpperCase(), textAlign: TextAlign.center, style: head.copyWith(color: C.mute, letterSpacing: 3)),
      const SizedBox(height: 24),
      if (r['k'] == 'killed') ...[
        Text(l.victimIs, textAlign: TextAlign.center, style: const TextStyle(color: C.mute, fontSize: 16)),
        Big(_name(r['seat'] as int), size: 42, color: C.red2),
        if (role != null) Text(l.wasRole(roleName(l, role)), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
      ] else if (r['k'] == 'saved') ...[
        Text(l.savedIs, textAlign: TextAlign.center, style: const TextStyle(color: C.mute, fontSize: 16)),
        Big(_name(r['seat'] as int), size: 42, color: C.green),
      ] else
        Big(l.nobody, color: C.green),
      if (!c.isHost) Padding(padding: const EdgeInsets.only(top: 20), child: Text(l.waitHost, textAlign: TextAlign.center, style: const TextStyle(color: C.dim))),
    ]);
  }

  Widget _day(L l, Map<String, Object?> view) {
    final t = view['timer'] as Map?, left = _secondsLeft() ?? 0, running = t?['end'] != null;
    return Stage(color: C.day, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
      Sec(title: l.discussion, child: Column(children: [
        Text(left == 0 && running ? l.timeUp : '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}', key: const Key('clock'),
            style: head.copyWith(fontSize: 52, color: left == 0 ? C.red2 : C.text)),
        if (c.isHost) ...[
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            OutlinedButton(key: const Key('timerGo'), onPressed: () => c.send({'t': 'timer', 'op': running ? 'pause' : 'start'}), child: Text(running ? l.pause : l.start, style: const TextStyle(color: C.text))),
            OutlinedButton(key: const Key('timerAdd'), onPressed: () => c.send({'t': 'timer', 'op': 'add', 'sec': 60}), child: Text(l.plusMin, style: const TextStyle(color: C.text))),
            OutlinedButton(key: const Key('timerReset'), onPressed: () => c.send({'t': 'timer', 'op': 'reset'}), child: Text(l.reset, style: const TextStyle(color: C.text))),
          ]),
        ],
      ])),
      if (!c.isHost) Text(l.waitHost, textAlign: TextAlign.center, style: const TextStyle(color: C.dim)),
    ]);
  }

  Widget _vote(L l, Map<String, Object?> view) {
    final me = view['seat'] as int;
    return Stage(center: false, bottom: [
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
    final r = Map<String, Object?>.from(view['result'] as Map? ?? const {'k': 'skipped'}), role = _role(r['role']), tally = r['tally'] as List?;
    return Stage(color: r['k'] == 'out' ? C.blood : C.day, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
      if (r['k'] == 'out') ...[
        Text(l.outIs, textAlign: TextAlign.center, style: const TextStyle(color: C.mute, fontSize: 16)),
        Big(_name(r['seat'] as int), size: 42, color: C.red2),
        if (role != null) Text(l.wasRole(roleName(l, role)), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
      ] else
        Big(r['k'] == 'tie' ? l.tie : l.skipped),
      if (tally != null && tally.isNotEmpty) ...[
        const SizedBox(height: 22),
        Sec(child: Column(children: [
          for (final t in tally.cast<Map>())
            Row(children: [Expanded(child: Text(t['k'] == 'none' ? l.noOne : _name(t['k'] as int))), Text('${t['n']} ${l.votes}', style: const TextStyle(color: C.mute))]),
        ])),
      ],
    ]);
  }

  Widget _end(L l, Map<String, Object?> view) {
    if (!revealed) return _suspense(l, l.gameOver, C.glory, Icons.emoji_events_outlined);
    final rc = Map<String, Object?>.from(view['recap'] as Map), mafia = rc['winner'] == 'mafia';
    final roles = (rc['roles'] as List).map((x) => Role.values.byName(x as String)).toList(), alive = (rc['alive'] as List).cast<bool>();
    final st = rc['stats'] as Map;
    final stats = Stats(first: st['first'] as int?, kills: (st['kills'] as List).cast<int>(), outs: (st['outs'] as List).cast<int>(),
        saves: (st['saves'] as List).cast<int>(), caught: [for (final p in (st['caught'] as List)) ((p as List)[0] as int, p[1] as int)]);
    final best = mvp(mafia ? Winner.mafia : Winner.citizens, roles, alive, stats), valid = c.room?['valid'];
    return Stage(color: mafia ? C.blood : C.glory, center: false, bottom: [
      if (c.isHost) ...[
        if (c.room?['gameId'] != null) Row(children: [
          Expanded(child: Btn(l.valid, key: const Key('markValid'), ghost: valid != true, onTap: () => c.send({'t': 'mark', 'valid': true}))),
          const SizedBox(width: 10),
          Expanded(child: Btn(l.invalid, key: const Key('markInvalid'), ghost: valid != false, onTap: () => c.send({'t': 'mark', 'valid': false}))),
        ]),
        Btn('${l.playAgain} · ${l.sameNew}', key: const Key('playAgain'), icon: Icons.replay, onTap: () => c.send({'t': 'deal'})),
        Btn(l.toLobby, key: const Key('toLobby'), ghost: true, onTap: () => c.send({'t': 'lobby'})),
      ] else
        Text(l.waitHost, textAlign: TextAlign.center, style: const TextStyle(color: C.dim)),
    ], children: [
      const SizedBox(height: 12),
      Big(mafia ? l.winMafia : l.winCitizens, sub: mafia ? l.winMafiaD : l.winCitizensD, color: mafia ? C.red2 : C.gold, size: 36),
      Padding(padding: const EdgeInsets.only(top: 6, bottom: 18), child: Text(l.rcSub(roles.length, rc['day'] as int), textAlign: TextAlign.center, style: const TextStyle(color: C.dim))),
      if (best != null)
        Sec(title: l.mvpT, child: Row(children: [
          Icon(roleIcon(roles[best.seat]), color: roleColor(roles[best.seat])), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name(best.seat), style: head.copyWith(fontSize: 20)),
            Text(switch (best.why) { 'mafia' => l.mvpMafia, 'mafia2' => l.mvpMafia2, 'det' => l.mvpDet(best.n ?? 1), 'doc' => l.mvpDoc(best.n ?? 1), _ => l.mvpSurv },
                style: const TextStyle(color: C.mute)),
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

// ---------------------------------------------------------------- history
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.account});
  final Account account;
  @override
  State<HistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends State<HistoryScreen> {
  List<Map<String, Object?>>? games;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final g = await widget.account.games(); if (mounted) setState(() => games = g); } catch (e) { if (mounted) setState(() => error = errText(L.of(context), e)); }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.historyT, style: head.copyWith(fontSize: 20))),
      body: error != null ? Center(child: Text(error!, style: const TextStyle(color: C.red2)))
          : games == null ? const Center(child: CircularProgressIndicator(color: C.red2))
          : games!.isEmpty ? Center(child: Text(l.noHistory, style: const TextStyle(color: C.mute)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              for (final g in games!)
                Card(color: C.card, child: ListTile(
                  key: Key('game_${g['id']}'),
                  leading: Icon(g['winner'] == 'mafia' ? Icons.dangerous_outlined : Icons.emoji_events_outlined, color: g['winner'] == 'mafia' ? C.red2 : C.gold),
                  title: Text(g['winner'] == 'mafia' ? l.winMafia : l.winCitizens),
                  subtitle: Text('${l.youPlayed(roleName(l, Role.values.byName(g['role'] as String)))} · ${l.rcSub(g['players'] as int, g['days'] as int)}'
                      '${g['valid'] == true ? '' : ' · ${l.invalid}'}', style: const TextStyle(color: C.mute)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _GameDetail(account: widget.account, id: g['id'] as String))),
                )),
            ]),
    );
  }
}

class _GameDetail extends StatefulWidget {
  const _GameDetail({required this.account, required this.id});
  final Account account;
  final String id;
  @override
  State<_GameDetail> createState() => _GameDetailState();
}

class _GameDetailState extends State<_GameDetail> {
  Map<String, Object?>? g;
  @override
  void initState() { super.initState(); widget.account.game(widget.id).then((x) { if (mounted) setState(() => g = x); }).catchError((_) {}); }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), game = g;
    if (game == null) return Scaffold(appBar: AppBar(backgroundColor: C.bg), body: const Center(child: CircularProgressIndicator(color: C.red2)));
    final ps = (game['players'] as List).cast<Map>(), name = {for (final p in ps) p['seat'] as int: p['name'] as String};
    String line(Map e) => switch (e['t']) {
          'night' => l.hNight(e['day'] as int) + switch ((e['mafia'] as Map)['k']) {
              'kill' => l.hKill(name[(e['mafia'] as Map)['seat']] ?? '?'), 'saved' => l.hSaved(name[(e['mafia'] as Map)['seat']] ?? '?'),
              'skip' => l.hSkip, _ => l.hNoMafia },
          'day' => l.hDay(e['day'] as int) + (e['out'] != null ? l.hOut(name[e['out']] ?? '?') : l.hNone),
          'removed' => l.hRemoved(name[e['seat']] ?? '?'),
          _ => '',
        };
    final mafia = game['winner'] == 'mafia';
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(mafia ? l.winMafia : l.winCitizens, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, bottom: [
        if (game['host'] == true) Row(children: [
          Expanded(child: Btn(l.valid, ghost: game['valid'] != true, onTap: () async { await widget.account.markGame(widget.id, true).catchError((_) {}); setState(() => game['valid'] = true); })),
          const SizedBox(width: 10),
          Expanded(child: Btn(l.invalid, ghost: game['valid'] != false, onTap: () async { await widget.account.markGame(widget.id, false).catchError((_) {}); setState(() => game['valid'] = false); })),
        ]),
      ], children: [
        Sec(title: l.roles, child: Column(children: [
          for (final p in ps)
            Row(children: [
              Icon(roleIcon(Role.values.byName(p['role'] as String)), size: 18, color: roleColor(Role.values.byName(p['role'] as String))), const SizedBox(width: 8),
              Expanded(child: Text(p['name'] as String, style: TextStyle(decoration: p['alive'] == true ? null : TextDecoration.lineThrough))),
              Text(roleName(l, Role.values.byName(p['role'] as String))),
            ]),
        ])),
        Sec(title: l.history, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final e in (game['log'] as List).cast<Map>()) if (line(e).isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(line(e), style: const TextStyle(color: C.mute))),
        ])),
      ]),
    );
  }
}
