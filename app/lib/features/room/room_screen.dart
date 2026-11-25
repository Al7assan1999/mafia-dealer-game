import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mafia_dealer/features/offline/rules_card.dart';
import 'package:flutter/services.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/features/account/avatar.dart';
import 'package:mafia_dealer/features/chat/chat_screen.dart';
import 'package:mafia_dealer/features/friends/friends_drawer.dart';
import 'package:mafia_dealer/features/friends/friends_screen.dart';
import 'package:mafia_dealer/features/history/wifi_approval.dart';
import 'package:mafia_dealer/features/offline/recap_card.dart';
import 'package:mafia_dealer/features/offline/role_card.dart';
import 'package:mafia_dealer/features/offline/setup_screen.dart';
import 'package:mafia_dealer/features/room/buzz.dart';
import 'package:mafia_dealer/features/safety/safety.dart';
import 'package:mafia_dealer/features/wifi/lan.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/state/models.dart';
import 'package:mafia_dealer/state/room_conn.dart';
import 'package:mafia_dealer/features/room/room_bar.dart' show ChatTab;
import 'package:mafia_dealer/l10n/app_localizations.dart';

part 'room_lobby.dart';
part 'room_play.dart';
part 'room_end.dart';

String roomErr(L l, String? code) => switch (code) {
      'no_room' => l.eNoRoom, 'started' => l.eStarted, 'room_full' => l.eRoomFull, 'kicked' => l.eKicked,
      'forbidden' => l.eForbidden, 'not_open' => l.eNotOpen, 'offline' => l.eOffline, 'lobby_only' => l.eLobbyOnly,
      'old_app' => l.eOldApp, _ => l.eOther,
    };


// ---------------------------------------------------------------- the room
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.account, required this.prefs, required this.audio, required this.code, this.connect,
      this.api, this.lan = false, this.lanHost = false, this.relocate, this.onClose, this.existing, this.inviteOnJoin});
  final RoomConn? existing; // back from minimized: the same connection (S9-1)
  final String? inviteOnJoin; // Invite from Home (S9-5): invite this friend once the room is open
  final Api? api; // Wi-Fi: the host phone's server
  final bool lan, lanHost; // a Wi-Fi room / this phone hosts it
  final Future<Api?> Function()? relocate; // Wi-Fi: find the host again if its address changed
  final VoidCallback? onClose; // Wi-Fi host: stop the server when leaving
  final Account account;
  final Prefs prefs;
  final Audio audio;
  final String code;
  final Connector? connect; // tests pass a scripted server
  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  late final RoomConn c = widget.existing ?? RoomConn(widget.api ?? widget.account.api, widget.code, connect: widget.connect ?? ioConnect, relocate: widget.relocate);
  bool _minimized = false, _invited = false;
  StreamSubscription<dynamic>? _n, _s;
  Timer? _tick, _arm;
  bool revealed = true; // the morning / verdict / end result is held until my narrator says the name
  bool _timeUpSaid = false;
  String? _myAddress; // Wi-Fi host: where players join (shown under the code)
  String? _wifiKey; // the Wi-Fi game just kept on this phone (its end screen offers it to online history)
  Object? _pick;
  Audio get audio => widget.audio;
  RoomConn get conn => c; // for the tests

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Wi-Fi is one room: only the host's phone narrates unless someone switches theirs on
    audio.muted = widget.lan ? !widget.lanHost : !widget.prefs.narrate;
    _n = c.narration.listen(_narrate);
    _s = c.side.listen(_onSide);
    c.addListener(_changed);
    if (widget.existing == null) c.start();
    if (!widget.lan) openRoomConn = c;
    if (widget.lanHost) localAddresses().then((a) { if (mounted && a.isNotEmpty) setState(() => _myAddress = a.first); });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { _checkTimeUp(); if (mounted) setState(() {}); });
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _n?.cancel(); _s?.cancel(); _tick?.cancel(); _arm?.cancel();
    c.removeListener(_changed);
    if (identical(openRoomConn, c)) openRoomConn = null;
    if (!_minimized) c.dispose(); // minimized: ActiveRoom keeps the connection
    audio.stop();
    audio.muted = false;
    WakelockPlus.disable().catchError((_) {});
    if (!widget.lan) widget.account.reloadMe();
    if (!_minimized) widget.onClose?.call();
    super.dispose();
  }

  /// S9-1: go Home and stay in the room (lobby only).
  void _minimize() {
    _minimized = true;
    final w = widget;
    ActiveRoom.instance.hold(c, w.code, (conn) => RoomScreen(account: w.account, prefs: w.prefs, audio: w.audio, code: w.code, connect: w.connect,
        api: w.api, lan: w.lan, lanHost: w.lanHost, relocate: w.relocate, onClose: w.onClose, existing: conn), lanHost: w.lanHost, lan: w.lan, onLeave: w.onClose, alert: (_) => buzzFx(w.audio));
    Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) => c.foreground(s == AppLifecycleState.resumed);

  Map<String, Object?>? get v => c.view;
  List<String> get names => [for (final r in (v?['roster'] as List? ?? const [])) (r as Map)['name'] as String];
  String _name(int seat) => seat >= 0 && seat < names.length ? names[seat] : '?';

  bool _defaults = false;
  void _changed() {
    final err = c.error;
    if (err != null && mounted && c.room != null) { toastErr(context, roomErr(L.of(context), err)); c.error = null; }
    final room = c.room;
    if (room != null && c.isHost && !_defaults) {
      _defaults = true;
      // S9-4: a room I host starts with my Settings (buzz limit, kick rule), once, while nobody has been dealt in yet
      final p = widget.prefs;
      if (room['deal'] == 0 && (room['buzzMax'] != p.hostBuzzMax || room['kick'] != p.hostKick)) {
        c.send({'t': 'setup', 'rules': room['rules'], 'counts': {'mafia': (room['counts'] as Map)['mafia'], 'detective': (room['counts'] as Map)['detective']},
          'buzzMax': p.hostBuzzMax, 'kick': p.hostKick, if (room['mode'] != null) 'mode': room['mode']});
      }
    }
    if (room != null && c.isHost && widget.inviteOnJoin != null && !_invited) {
      _invited = true; // S9-5: Invite from Home, once the room exists
      Future.delayed(const Duration(milliseconds: 600), () => widget.account.invite(widget.inviteOnJoin!, widget.code).catchError((_) {}));
    }
    if (mounted) setState(() {});
  }

  void _onSide(Map<String, Object?> m) {
    if (!mounted) return;
    final l = L.of(context);
    if (m['t'] == 'buzz') {
      final who = c.members.where((x) => x['uid'] == m['from']).firstOrNull;
      toast(context, l.buzzed((who?['display'] as String?) ?? '?'));
      buzzFx(audio); // R7
    } else if (m['t'] == 'record' && widget.lan) {
      // a Wi-Fi game ended: this phone keeps it (History → Wi-Fi)
      final seats = (m['seats'] as List).cast<String>();
      final key = '${m['code']}-${m['at']}';
      widget.prefs.addWifiGame({'id': key, 'record': m['record'], 'names': m['names'], 'mySeat': seats.indexOf(c.myUid ?? ''), 'at': m['at'], 'code': m['code'],
        'accounts': m['accounts'], 'host': m['host'] != null && m['host'] == c.myUid});
      setState(() => _wifiKey = key);
    } else if (m['t'] == 'mention') {
      toast(context, l.mentionedYou(c.members.where((x) => x['cn'] == m['from']).firstOrNull?['display'] as String? ?? '?'));
      HapticFeedback.mediumImpact();
    } else if (m['t'] == 'ping') {
      toast(context, l.pingedYou);
      buzzFx(audio); // R7
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
        final also = r?['also'] as Map?;
        audio.morning(r?['k'] == 'killed' ? nm(r?['seat']) : null, r?['k'] == 'killed' ? roleOf(r?['role']) : null,
            r?['k'] == 'saved' ? nm(r?['seat']) : null, _armReveal, nm(also?['seat']), roleOf(also?['role']));
      case 'verdict':
        setState(() => revealed = false);
        audio.verdict(r?['k'] == 'out' ? nm(r?['seat']) : null, r?['k'] == 'out' ? roleOf(r?['role']) : null, (r?['k'] as String?) ?? 'skipped', _armReveal);
      case 'end':
        setState(() => revealed = false);
        final win = n.events.lastWhere((e) => e['t'] == 'win', orElse: () => const {}), lead = win['lead'] as Map?;
        final roles = (view['roles'] as List? ?? const []).cast<String>();
        final clips = lead == null ? <String?>[] : audio.lead(lead['k'] as String, _name(lead['seat'] as int), roleOf(roles[lead['seat'] as int]));
        final mafia = [for (var i = 0; i < roles.length; i++) if (roles[i] == 'mafia') _name(i)];
        if (view['winner'] == 'mafia') {
          audio.mafiaWin(mafia, clips, _armReveal);
        } else if (view['winner'] == 'jester') {
          audio.jesterWin(clips, _armReveal);
        } else {
          audio.citizensWin(mafia, clips, _armReveal);
        }
    }
  }

  int? _secondsLeft() {
    final t = v?['timer'] as Map?;
    if (t == null) return null;
    if (t['left'] != null) return t['left'] as int;
    return ((((t['end'] as int) - c.serverNow) / 1000).ceil()).clamp(0, 99999); // the server's clock, not this phone's
  }

  void _checkTimeUp() {
    if (v?['phase'] == 'day' && (v?['timer'] as Map?)?['end'] != null && _secondsLeft() == 0 && !_timeUpSaid) {
      _timeUpSaid = true;
      audio.timeUp();
    }
  }

  void _send(Map<String, Object?> m) { c.send(m); setState(() => _pick = null); }

  /// The host's (and room) actions only while connected: a tap during a drop would fire later, into a moved-on phase.
  VoidCallback? _h(VoidCallback f) => c.open ? f : null;

  Future<void> _leave() async {
    final l = L.of(context);
    if (c.bye != null || await ask(context, l.leaveRoomQ, l.leaveRoomD, l.leaveRoom)) {
      if (c.bye == null) c.send({'t': widget.lanHost ? 'close' : 'leave'}); // the Wi-Fi host leaving ends the room
      if (widget.lan && !widget.lanHost) widget.prefs.lanJoin = null;
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
          // [QA] S12: in Neon's wider font "Room 438689" was cut to "Room 4386…"; it shrinks to fit instead
          title: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(l.roomCode(widget.code), style: head.copyWith(fontSize: 20))),
          actions: [
            if (c.bye == null) IconButton(key: const Key('narrate'), tooltip: l.narrateHere,
                icon: Icon(!audio.muted ? Icons.volume_up_outlined : Icons.volume_off_outlined, color: C.mute),
                onPressed: () => setState(() {
                  audio.muted = !audio.muted;
                  if (!widget.lan) widget.prefs.narrate = !audio.muted; // online: remembered; Wi-Fi: this room only
                  if (audio.muted) audio.stop();
                })),
            if (c.view != null && !c.isHost) IconButton(key: const Key('buzz'), tooltip: l.buzz, icon: Icon(Icons.campaign_outlined, color: C.mute), onPressed: _h(() { c.send({'t': 'buzz'}); toast(context, l.buzzSent); })),
            if (c.view != null && c.isHost) IconButton(key: const Key('ping'), tooltip: l.ping, icon: Icon(Icons.notifications_active_outlined, color: C.mute), onPressed: _h(() { c.send({'t': 'ping'}); toast(context, l.pingSent); })),
            if (c.room != null && c.view == null && c.bye == null)
              IconButton(key: const Key('minimize'), tooltip: l.minimize, icon: Icon(Icons.home_outlined, color: C.mute), onPressed: _minimize),
            if (c.bye == null) IconButton(key: const Key('leave'), tooltip: l.leaveRoom, icon: Icon(Icons.logout, color: C.mute), onPressed: _leave),
          ],
        ),
        body: Column(children: [
          _bar(l),
          Expanded(child: Stack(children: [
            Positioned.fill(child: KeyedSubtree(key: ValueKey('${v?['phase']}/${v?['ph']}/${v?['day']}/$revealed'), child: _screen(l))),
            // S9-2: the friends tab in an online lobby (never in a game, never in a Wi-Fi room)
            // [S12-6] never over the room-code card (it starts below it); gone once the room is closed
            // [S14-1 / his #1] the chat is a side tab under the friends tab, in the lobby and the game (online and Wi-Fi)
            if (c.room != null && c.bye == null) Positioned.fill(child: FriendsTab(account: widget.account, prefs: widget.prefs, audio: audio, room: c, above: v == null ? 200 : 160, // in a game: under the screen's header
                friends: !widget.lan && v == null,
                extra: ChatTab(key: const Key('chat'), conn: c, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(conn: c, account: widget.account,
                    out: c.room?['status'] == 'game' && v?['alive'] == false, safety: !widget.lan)))))),
          ])),
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
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: C.priText, fontWeight: FontWeight.w700)));
  }

  Widget _screen(L l) {
    if (c.bye != null) {
      return Stage(bottom: [Btn(l.home, onTap: () => Navigator.of(context).pop())], children: [
        Big(c.bye == 'kicked' ? l.eKicked : c.bye == 'closed' ? l.roomClosed : l.leaveRoom),
      ]);
    }
    if (c.room == null) {
      return Stage(bottom: [if (c.error != null) Btn(l.home, onTap: () => Navigator.of(context).pop())], children: [
        if (c.error != null) Big(roomErr(l, c.error), color: C.red2) else Center(child: CircularProgressIndicator(color: C.red2)),
      ]);
    }
    final view = v;
    if (view == null) return _lobby(l);
    final ph = view['ph'] as String?, phase = view['phase'] as String;
    // [S17-4] a role a later version deals: this app can't play it, and says so instead of breaking
    final unknown = [view['role'], ...(view['roles'] as List? ?? const []), ...((view['recap'] as Map?)?['roles'] as List? ?? const [])]
        .any((r) => r is String && r.isNotEmpty && roleOf(r) == null);
    if (unknown) return Stage(bottom: [Btn(l.home, onTap: () => Navigator.of(context).pop())], children: [Big(l.updateToPlay, color: C.gold)]);
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

  /// the option picked on a night or vote screen (the views live in the part files)
  void _choose(Object value) => setState(() => _pick = value);
}
