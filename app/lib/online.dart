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
import 'api.dart';
import 'chat.dart';
import 'drawer.dart';
import 'lan/lan.dart' show localAddresses;
import 'safety.dart';
import 'audio.dart';
import 'game_screen.dart' show RoleCard;
import 'l10n/app_localizations.dart';
import 'prefs.dart';
import 'room.dart';
import 'setup.dart';
import 'stats.dart';
import 'version.dart';
import 'ui.dart';

String roomErr(L l, String? code) => switch (code) {
      'no_room' => l.eNoRoom, 'started' => l.eStarted, 'room_full' => l.eRoomFull, 'kicked' => l.eKicked,
      'forbidden' => l.eForbidden, 'not_open' => l.eNotOpen, 'offline' => l.eOffline, 'lobby_only' => l.eLobbyOnly, _ => l.eOther,
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
  void initState() { super.initState(); code.addListener(() { if (mounted) setState(() => error = null); }); }
  @override
  void dispose() { code.dispose(); super.dispose(); }

  /// [S12-2] A code with no open room is answered here, not by opening an empty room screen.
  Future<void> _join() async {
    final l = L.of(context), c = code.text;
    setState(() { busy = true; error = null; });
    try {
      await widget.account.api.get('/v1/rooms/$c');
      if (mounted) _open(c);
    } catch (e) {
      if (mounted) setState(() => error = e is ApiError && e.code == 'no_room' ? l.eNoRoom : errText(l, e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), a = widget.account;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.online, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, children: [
        Text(l.onlineSub, style: TextStyle(color: C.mute)),
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
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(hintText: l.codeHint, counterText: '', helperText: code.text.isNotEmpty && code.text.length < 6 ? l.code6 : null),
                style: head.copyWith(fontSize: 22, letterSpacing: 6))),
            const SizedBox(width: 10),
            FilledButton(key: const Key('joinRoom'), style: FilledButton.styleFrom(backgroundColor: C.red),
                onPressed: code.text.length == 6 && !busy ? _join : null, child: Text(l.join)), // S12-2: off until 6 digits
          ]),
        ],
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, key: const Key('error'), style: TextStyle(color: C.red2))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- buzz and ping (R7)
/// Bumped by every buzz / ping that arrives: [BuzzFlash] flashes the screen red.
final buzzFlash = ValueNotifier<int>(0);
/// A buzz or a ping arriving, as the old app's buzzFx: a double vibration, the hit sound (even with narration off on this
/// phone) and a red flash.
void buzzFx(Audio? audio) {
  const MethodChannel('mafia/keep').invokeMethod('vibrate').catchError((_) { HapticFeedback.heavyImpact(); return null; });
  audio?.sfx('hit_good', 0, true);
  buzzFlash.value++;
}

/// The red flash over every screen (MaterialApp.builder).
class BuzzFlash extends StatelessWidget {
  const BuzzFlash({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(child: ValueListenableBuilder(valueListenable: buzzFlash, builder: (context, n, _) => n == 0
      ? const SizedBox.shrink()
      : TweenAnimationBuilder<double>(key: ValueKey(n), tween: Tween(begin: .35, end: 0), duration: const Duration(milliseconds: 450),
          builder: (context, o, _) => ColoredBox(color: C.red.withValues(alpha: o), child: const SizedBox.expand()))));
}

// ---------------------------------------------------------------- minimize (S9-1)
/// The room this phone stays in while it goes Home from the lobby: the connection outlives the room screen. The room bar
/// leads back; dealing the roles pulls the player back; a kick or a closed room is told on whatever screen is open.
class ActiveRoom extends ChangeNotifier {
  ActiveRoom._();
  static final instance = ActiveRoom._();
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  RoomConn? conn;
  String code = '';
  bool lanHost = false, lan = false;
  RoomScreen Function(RoomConn c)? _reopen; // the same room screen again, on the same connection
  VoidCallback? _onLeave; // Wi-Fi host: stop the server when the room is left for good
  StreamSubscription<Map<String, Object?>>? _side;
  bool get minimized => conn != null;

  void hold(RoomConn c, String code, RoomScreen Function(RoomConn c) reopen, {bool lanHost = false, bool lan = false, VoidCallback? onLeave, Audio? audio}) {
    conn = c; this.code = code; this.lanHost = lanHost; this.lan = lan; _reopen = reopen; _onLeave = onLeave;
    c.addListener(_watch);
    // [R7] a buzz or a ping reaches me on Home too (the old app's minimized room did the same)
    _side = c.side.listen((m) {
      final ctx = navigatorKey.currentContext;
      if (m['t'] != 'buzz' && m['t'] != 'ping') return;
      if (ctx == null || !ctx.mounted) return;
      final l = L.of(ctx), who = c.members.where((x) => x['uid'] == m['from']).firstOrNull?['display'] as String?;
      buzzFx(audio);
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text(m['t'] == 'buzz' ? l.buzzed(who ?? '?') : l.pingedYou)));
    });
    notifyListeners();
  }

  void _watch() {
    final c = conn;
    if (c == null) return;
    final ctx = navigatorKey.currentContext;
    if (c.bye != null) { // kicked or closed while away: say so where the player is
      final l = ctx == null ? null : L.of(ctx);
      final msg = l == null ? null : c.bye == 'kicked' ? l.eKicked : l.roomClosed;
      _drop(dispose: true);
      if (msg != null) messengerKey.currentState?.showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    if (c.view != null) { // the roles are dealt: back to the room
      HapticFeedback.heavyImpact();
      reopen();
      final l = navigatorKey.currentContext == null ? null : L.of(navigatorKey.currentContext!);
      if (l != null) messengerKey.currentState?.showSnackBar(SnackBar(content: Text(l.rolesDealt)));
    }
    notifyListeners(); // members, unread chat
  }

  /// Back to the room screen (the room bar, a deal, an invite into this same room).
  void reopen() {
    final c = conn, b = _reopen;
    if (c == null || b == null) return;
    _drop(dispose: false);
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => b(c)));
  }

  /// Leaves the room for good (before starting something else).
  void leave() {
    final c = conn;
    if (c == null) return;
    if (c.bye == null) c.send({'t': lanHost ? 'close' : 'leave'});
    final onLeave = _onLeave;
    _drop(dispose: true);
    onLeave?.call();
  }

  void _drop({required bool dispose}) {
    final c = conn;
    c?.removeListener(_watch);
    _side?.cancel(); _side = null;
    conn = null; _reopen = null; _onLeave = null;
    if (dispose) Future.delayed(const Duration(milliseconds: 300), () => c?.dispose()); // the goodbye goes out first
    notifyListeners();
  }
}

/// The online lobby I'm in right now: the room screen open, or the minimized one (null in a game, a Wi-Fi room, or none).
RoomConn? onlineLobby() {
  final c = _openRoom ?? (ActiveRoom.instance.lan ? null : ActiveRoom.instance.conn);
  return c != null && c.room != null && c.view == null && c.bye == null ? c : null;
}
RoomConn? _openRoom; // the online room screen on top, while it's mounted

/// While minimized, starting something else asks first. True when nothing is held (or it was left).
Future<bool> leaveRoomFirst(BuildContext context) async {
  final a = ActiveRoom.instance;
  if (!a.minimized) return true;
  final l = L.of(context);
  if (!await ask(context, l.leaveFirstQ, l.leaveFirstD(a.code), l.leaveRoom)) return false;
  a.leave();
  return true;
}

/// The room bar on every screen while minimized (MaterialApp.builder puts it above the pages).
class RoomBarFrame extends StatelessWidget {
  const RoomBarFrame({super.key, required this.child, this.onLongPress});
  final Widget child;
  final void Function(BuildContext context)? onLongPress; // P4: the friends drawer with Invite ready
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: ActiveRoom.instance, builder: (context, _) {
        final a = ActiveRoom.instance, c = a.conn;
        if (c == null) return child;
        final l = L.of(context), ms = c.members, host = ms.where((m) => m['host'] == true).firstOrNull, n = ms.where((m) => m['online'] != false).length;
        final mine = c.isHost;
        return Column(children: [
          Material(color: C.red, child: SafeArea(bottom: false, child: InkWell(
            key: const Key('roomBar'), onTap: a.reopen, onLongPress: onLongPress == null ? null : () => onLongPress!(context),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(children: [
              Icon(Icons.meeting_room_outlined, color: C.priText, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(mine ? l.roomBarHost(n) : l.roomBarIn((host?['display'] as String?) ?? '?', n),
                  style: TextStyle(color: C.priText, fontWeight: FontWeight.w700))),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: C.priText),
            ])),
          ))),
          Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
        ]);
      });
}

/// [R1] The minimized room's chat on Home, under the friends tab (it was on the red bar at the top, N7), with the unread
/// count. Shown signed out too (a guest minimized in a Wi-Fi room).
class RoomChatButton extends StatelessWidget {
  const RoomChatButton({super.key, required this.account});
  final Account account;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: ActiveRoom.instance, builder: (context, _) {
        final a = ActiveRoom.instance, c = a.conn;
        if (c == null || !a.minimized) return const SizedBox.shrink();
        return ListenableBuilder(listenable: c, builder: (context, _) => Material(
          color: C.card2, elevation: 6,
          shape: RoundedRectangleBorder(side: BorderSide(color: C.red),
              borderRadius: BorderRadiusDirectional.horizontal(start: Radius.circular(C.neon ? 18 : 6)).resolve(Directionality.of(context))),
          child: InkWell(key: const Key('barChat'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(conn: c, account: account, out: false, safety: !a.lan))),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10), child: Semantics(label: L.of(context).chatT, child: Badge(
                isLabelVisible: c.unreadTotal > 0, label: Text('${c.unreadTotal}'), child: Icon(Icons.chat_bubble_outline, color: C.text, size: 22)))))),
        );
      });
}

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
    if (!widget.lan) _openRoom = c;
    if (widget.lanHost) localAddresses().then((a) { if (mounted && a.isNotEmpty) setState(() => _myAddress = a.first); });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { _checkTimeUp(); if (mounted) setState(() {}); });
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _n?.cancel(); _s?.cancel(); _tick?.cancel(); _arm?.cancel();
    c.removeListener(_changed);
    if (identical(_openRoom, c)) _openRoom = null;
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
        api: w.api, lan: w.lan, lanHost: w.lanHost, relocate: w.relocate, onClose: w.onClose, existing: conn), lanHost: w.lanHost, lan: w.lan, onLeave: w.onClose, audio: w.audio);
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
          'buzzMax': p.hostBuzzMax, 'kick': p.hostKick});
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
          backgroundColor: C.bg,
          // [QA] S12: in Neon's wider font "Room 438689" was cut to "Room 4386…"; it shrinks to fit instead
          title: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(l.roomCode(widget.code), style: head.copyWith(fontSize: 20))),
          actions: [
            if (c.room != null && c.bye == null) IconButton(key: const Key('chat'), tooltip: l.chatT,
                icon: Badge(isLabelVisible: c.unreadTotal > 0, label: Text('${c.unreadTotal}'), child: Icon(Icons.chat_bubble_outline, color: C.mute)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(conn: c, account: widget.account,
                    out: c.room?['status'] == 'game' && v?['alive'] == false, safety: !widget.lan)))),
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
            if (!widget.lan && c.room != null && v == null && c.bye == null) Positioned.fill(child: FriendsTab(account: widget.account, prefs: widget.prefs, audio: audio, room: c, above: 200)),
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
    void setup(Counts cc, Rules rr) => c.send({'t': 'setup', 'rules': rr.toJson(), 'counts': {'mafia': cc.mafia, 'detective': cc.detective}, 'buzzMax': room['buzzMax'] ?? 3,
      if (room['kick'] != null) 'kick': room['kick']});
    return Stage(center: false, bottom: [
      if (host) ...[
        Text([l.playersCount(ms.length), '${v.counts.mafia} ${l.mafia}', l.doctor, if (v.counts.detective > 0) l.detective,
              switch (presetOf(rules)) { 'classic' => l.presetClassic, 'beginner' => l.presetBeginner, _ => l.presetCustom }].join(' · '),
            key: const Key('dealSummary'), textAlign: TextAlign.center, style: TextStyle(color: C.mute)),
        for (final m in ms.where((m) => m['online'] == false))
          Text(l.offlineDealt(m['display'] as String), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD9A441))),
        if (ms.length < minPlayers) Text(l.eNoMembers, textAlign: TextAlign.center, style: TextStyle(color: C.red2)),
        Btn(l.deal, key: const Key('deal'), icon: Icons.style_outlined, onTap: v.error == null ? _h(() => c.send({'t': 'deal'})) : null),
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
          Btn(l.buzz, key: const Key('buzzHost'), icon: Icons.campaign_outlined, onTap: _h(() { c.send({'t': 'buzz'}); toast(context, l.buzzSent); })),
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
      // [R7] the old app's "Ping everyone" on the player list's title row
      Sec(title: l.membersN(ms.length), action: host && ms.length > 1 ? TextButton.icon(key: const Key('pingAll'), style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: Icon(Icons.notifications_active_outlined, size: 18, color: C.red2), label: Text(l.ping, style: TextStyle(color: C.red2)),
            onPressed: _h(() { c.send({'t': 'ping'}); toast(context, l.pingSent); })) : null,
          child: Column(children: [for (final m in ms) _member(l, m, host)])),
      DeckEditor(players: ms.length, counts: v.counts, onChanged: host ? (cc) => setup(cc, rules) : null),
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
          if (!me && appBuild > 0 && m['v'] is int && (m['v'] as int) < appBuild)
            Text(l.oldVersion, key: Key('oldVersion_${m['cn']}'), style: TextStyle(color: C.gold, fontSize: 12)),
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
    final role = _role(view['role']);
    final meReady = c.members.any((m) => m['uid'] == c.myUid && m['ready'] == true), ms = c.members;
    final start = [if (c.isHost) Btn(l.startNow, key: const Key('start'), ghost: true, onTap: _h(() => c.send({'t': 'start'})))];
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
            decoration: BoxDecoration(color: on ? const Color(0xFF3A1512) : C.card, border: Border.all(color: on ? C.red : C.line, width: on ? 2 : 1), borderRadius: BorderRadius.circular(C.p.radius)),
            child: Row(children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: accent ?? C.text))),
              for (final t in tags) Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: Text(t, style: TextStyle(color: C.mute, fontSize: 12))),
              if (on) Padding(padding: EdgeInsetsDirectional.only(start: 8), child: Icon(Icons.check, color: C.red2)),
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
        const Spacer(), Text(l.night(view['day'] as int), style: TextStyle(color: C.mute)),
      ]),
      const SizedBox(height: 14),
      Text(title, style: head.copyWith(fontSize: 26)),
      Text(desc, style: TextStyle(color: C.mute)),
      if ((view['mates'] as List).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text(l.mates([for (final j in view['mates'] as List) _name(j as int)].join(', ')), style: TextStyle(color: C.red2))),
      if (secs != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.nightTimeLeft(secs), key: const Key('nightClock'), style: TextStyle(color: C.red2))),
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
    return Stage(color: C.blood, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
      Icon(Icons.visibility_outlined, color: C.mute, size: 48), const SizedBox(height: 12),
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

  Widget _suspense(L l, String text, Color color, IconData icon) => Stage(color: color, bottom: [
        Btn(l.skipWait, key: const Key('revealNow'), ghost: true, onTap: _reveal),
      ], children: [
        Icon(icon, color: C.gold, size: 60), const SizedBox(height: 16), Big(text), const SizedBox(height: 18),
        Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: C.mute))),
      ]);

  Widget _morning(L l, Map<String, Object?> view) {
    if (!revealed) return _suspense(l, l.sunrise, C.day, Icons.wb_sunny_outlined);
    final r = Map<String, Object?>.from(view['result'] as Map? ?? const {'k': 'nobody'}), role = _role(r['role']);
    return Stage(color: r['k'] == 'killed' ? C.blood : C.day, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
      Text(l.morningOf(view['day'] as int).toUpperCase(), textAlign: TextAlign.center, style: head.copyWith(color: C.mute, letterSpacing: 3)),
      const SizedBox(height: 24),
      if (r['k'] == 'killed') ...[
        Text(l.victimIs, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16)),
        Big(_name(r['seat'] as int), size: 42, color: C.red2),
        if (role != null) Text(l.wasRole(roleName(l, role)), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
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
    return Stage(color: C.day, bottom: _hostBar(l, view, _phaseButtons(l, view)), children: [
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
        Text(l.outIs, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16)),
        Big(_name(r['seat'] as int), size: 42, color: C.red2),
        if (role != null) Text(l.wasRole(roleName(l, role)), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
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

// ---------------------------------------------------------------- history
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.account, required this.prefs});
  final Account account;
  final Prefs prefs; // Wi-Fi games are kept on the phone
  @override
  State<HistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends State<HistoryScreen> {
  List<Map<String, Object?>>? games;
  String? error;
  Map<String, Map<String, Object?>> server = {}; // the server's Wi-Fi requests and approved games, by the game's key

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (!widget.account.signedIn) return;
    widget.account.wifiRequests().then((w) { if (mounted) setState(() => server = {for (final x in w) x['key'] as String: x}); }).catchError((_) {});
    try { final g = await widget.account.games(); if (mounted) setState(() => games = g); } catch (e) { if (mounted) setState(() => error = errText(L.of(context), e)); }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.prefs, builder: (context, _) {
    final l = L.of(context);
    final local = widget.prefs.wifiGames, keys = {for (final g in local) g['id']};
    // approved games played on another phone of mine: shown from the server's copy of the record
    final wifi = [...local, for (final s in server.values) if (s['status'] == 'approved' && !keys.contains(s['key']) && s['record'] != null)
      {'id': s['key'], 'record': s['record'], 'names': (s['record'] as Map)['names'], 'mySeat': s['seat'], 'at': s['playedAt'], 'host': s['host']}]
      ..sort((a, b) => ((b['at'] as int?) ?? 0).compareTo((a['at'] as int?) ?? 0));
    final title = Text(l.historyT, style: head.copyWith(fontSize: 20));
    if (!widget.account.signedIn) { // signed out: the Wi-Fi games on this phone (online history needs an account)
      return Scaffold(appBar: AppBar(backgroundColor: C.bg, title: title), body: Column(children: [
        Expanded(child: _wifi(l, wifi)),
        Padding(padding: const EdgeInsets.all(16), child: Text(l.historySignIn, key: const Key('historySignIn'), textAlign: TextAlign.center, style: TextStyle(color: C.dim))),
      ]));
    }
    return DefaultTabController(length: 3, child: Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: title, actions: [
            IconButton(key: const Key('openStats'), tooltip: l.statsT, icon: Icon(Icons.leaderboard_outlined, color: C.mute),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatsScreen(account: widget.account)))),
          ],
          bottom: TabBar(indicatorColor: C.red, labelColor: C.text, unselectedLabelColor: C.mute,
              tabs: [Tab(key: const Key('tabOnline'), text: l.tabOnline), Tab(key: const Key('tabWifi'), text: l.tabWifi), Tab(key: const Key('tabOld'), text: l.tabOld)])),
      body: TabBarView(children: [_online(l), _wifi(l, wifi), OldGamesTab(account: widget.account)]),
    ));
  });

  /// Wi-Fi games on this phone: the detail page is rebuilt from the game's record.
  Widget _wifi(L l, List<Map<String, Object?>> games) => games.isEmpty
      ? Center(child: Text(l.noWifiGames, style: TextStyle(color: C.mute)))
      : ListView(padding: const EdgeInsets.all(16), children: [
          for (final g in games)
            if (_wifiGame(g) case final d?)
              Card(color: C.card, child: ListTile(
                key: Key('wifi_${g['id']}'),
                leading: Icon(d['winner'] == 'mafia' ? Icons.dangerous_outlined : Icons.emoji_events_outlined, color: d['winner'] == 'mafia' ? C.red2 : C.gold),
                title: Text(d['winner'] == 'mafia' ? l.winMafia : l.winCitizens),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([
                    if (d['mine'] != null) l.youPlayed(roleName(l, Role.values.byName(d['mine'] as String))),
                    l.rcSub((d['players'] as List).length, d['days'] as int),
                  ].join(' · '), style: TextStyle(color: C.mute)),
                  WifiApproval(account: widget.account, prefs: widget.prefs, gameKey: g['id'] as String, server: server[g['id']], game: g, compact: true),
                ]),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _GameDetail(account: widget.account, id: '', local: d))),
              )),
        ]);

  /// A saved Wi-Fi game in the online detail page's shape (replayed from its record; null if it doesn't replay).
  static Map<String, Object?>? _wifiGame(Map<String, Object?> g) {
    final r = replay(g['record']);
    if (r.error != null) return null;
    final s = r.state!, my = g['mySeat'] as int? ?? -1;
    return {
      'winner': s.winner?.name, 'days': s.day, 'valid': true, 'host': false, 'log': s.log.map((e) => e.toJson()).toList(), 'stats': {'first': s.stats.first, 'kills': s.stats.kills, 'outs': s.stats.outs, 'saves': s.stats.saves, 'caught': [for (final (d, m) in s.stats.caught) [d, m]]},
      'players': [for (var i = 0; i < s.names.length; i++) {'seat': i, 'name': s.names[i], 'role': s.roles[i].name, 'alive': s.alive[i]}],
      'mine': my >= 0 && my < s.roles.length ? s.roles[my].name : null,
    };
  }

  Widget _online(L l) {
    return error != null ? Center(child: Text(error!, style: TextStyle(color: C.red2)))
          : games == null ? Center(child: CircularProgressIndicator(color: C.red2))
          : games!.isEmpty ? Center(child: Text(l.noHistory, style: TextStyle(color: C.mute)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              for (final g in games!)
                Card(color: C.card, child: ListTile(
                  key: Key('game_${g['id']}'),
                  leading: Icon(g['winner'] == 'mafia' ? Icons.dangerous_outlined : Icons.emoji_events_outlined, color: g['winner'] == 'mafia' ? C.red2 : C.gold),
                  title: Text(g['winner'] == 'mafia' ? l.winMafia : l.winCitizens),
                  subtitle: Text('${l.youPlayed(roleName(l, Role.values.byName(g['role'] as String)))} · ${l.rcSub(g['players'] as int, g['days'] as int)}'
                      '${g['valid'] == true ? '' : ' · ${l.invalid}'}', style: TextStyle(color: C.mute)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _GameDetail(account: widget.account, id: g['id'] as String))),
                )),
            ]);
  }
}

/// A kept Wi-Fi game's way into online history (S7-2): the button for the host, the guest line, or the request's
/// status. `server` is the server's view of the request (History loads it); else the phone's own record of it.
class WifiApproval extends StatefulWidget {
  const WifiApproval({super.key, required this.account, required this.prefs, required this.gameKey, this.server, this.game, this.compact = false});
  final Account account;
  final Prefs prefs;
  final String gameKey;
  final Map<String, Object?>? server, game;
  final bool compact;
  @override
  State<WifiApproval> createState() => _WifiApprovalState();
}

class _WifiApprovalState extends State<WifiApproval> {
  bool busy = false;

  static String reasonText(L l, String? r) => switch (r) {
        'replay' => l.wrReplay, 'seats' => l.wrSeats, 'players' => l.wrPlayers, 'short' => l.wrShort, 'old' => l.wrOld, 'dup' => l.wrDup, _ => r ?? '?' };
  static String statusText(L l, Map<String, Object?> req, int players) => switch (req['status']) {
        'pending' => l.wPending((req['waiting'] as int?) ?? players - 1, (req['total'] as int?) ?? players),
        'approved' => l.wApproved, 'declined' => l.wDeclined, 'expired' => l.wExpired, _ => l.wRejected(reasonText(l, req['reason'] as String?)) };

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Listenable.merge([widget.prefs, widget.account]), builder: (context, _) {
    final l = L.of(context);
    final g = widget.game ?? widget.prefs.wifiGames.where((x) => x['id'] == widget.gameKey).firstOrNull;
    if (g == null) return const SizedBox.shrink();
    final players = ((g['names'] as List?) ?? const []).length;
    final local = g['req'] == null ? null : Map<String, Object?>.from(g['req'] as Map);
    // the server knows better (others' answers), except right after a rejection it never keeps for History
    final req = widget.server ?? local;
    final pad = EdgeInsets.only(top: widget.compact ? 4 : 0, bottom: widget.compact ? 0 : 10);
    if (req != null) {
      final ok = req['status'] == 'approved', waiting = req['status'] == 'pending';
      return Padding(padding: pad, child: Row(mainAxisAlignment: widget.compact ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
        Icon(ok ? Icons.verified_outlined : waiting ? Icons.hourglass_top : Icons.block, size: 16, color: ok ? C.green : waiting ? C.gold : C.dim),
        const SizedBox(width: 6),
        Flexible(child: Text(statusText(l, req, players), key: const Key('wifiStatus'), style: TextStyle(color: ok ? C.green : C.mute, fontSize: 13))),
      ]));
    }
    if (g['host'] != true) return const SizedBox.shrink();
    if (Account.hadGuest(g)) {
      return Padding(padding: pad, child: Text(l.guestStays, key: const Key('guestStays'), textAlign: widget.compact ? TextAlign.start : TextAlign.center, style: TextStyle(color: C.dim, fontSize: 13)));
    }
    if (!widget.account.canAskWifi(g)) return const SizedBox.shrink();
    Future<void> send() async {
      setState(() => busy = true);
      try { await widget.account.askWifi(g); }
      catch (e) { if (context.mounted) toast(context, e is ApiError && e.code == 'slow_down' ? l.wrLimit : errText(l, e)); }
      if (mounted) setState(() => busy = false);
    }
    if (widget.compact) {
      return Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const Key('addOnline'), onPressed: busy ? null : send,
          icon: Icon(Icons.cloud_upload_outlined, size: 18, color: C.red2), label: Text(l.addOnline, style: TextStyle(color: C.red2))));
    }
    return Padding(padding: pad, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Btn(l.addOnline, key: const Key('addOnline'), ghost: true, icon: Icons.cloud_upload_outlined, onTap: busy ? null : send),
      Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.addOnlineD, textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 12))),
    ]));
  });
}

class _GameDetail extends StatefulWidget {
  const _GameDetail({required this.account, required this.id, this.local});
  final Account account;
  final String id;
  final Map<String, Object?>? local; // a Wi-Fi game from this phone (no server)
  @override
  State<_GameDetail> createState() => _GameDetailState();
}

class _GameDetailState extends State<_GameDetail> {
  /// The player of the game, from the saved stats (as on the end screen).
  static ({int seat, String why, int? n})? _mvp(Map<String, Object?> game) {
    final st = game['stats'] as Map?, ps = (game['players'] as List).cast<Map>();
    if (st == null || game['winner'] == null) return null;
    final stats = Stats(first: st['first'] as int?, kills: ((st['kills'] as List?) ?? []).cast<int>(), outs: ((st['outs'] as List?) ?? []).cast<int>(),
        saves: ((st['saves'] as List?) ?? []).cast<int>(), caught: [for (final p in ((st['caught'] as List?) ?? [])) ((p as List)[0] as int, p[1] as int)]);
    return mvp(Winner.values.byName(game['winner'] as String), [for (final p in ps) Role.values.byName(p['role'] as String)], [for (final p in ps) p['alive'] == true], stats);
  }

  Map<String, Object?>? g;
  @override
  void initState() {
    super.initState();
    if (widget.local != null) { g = widget.local; return; }
    widget.account.game(widget.id).then((x) { if (mounted) setState(() => g = x); }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), game = g;
    if (game == null) return Scaffold(appBar: AppBar(backgroundColor: C.bg), body: Center(child: CircularProgressIndicator(color: C.red2)));
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
        if (_mvp(game) case final best?)
          Sec(title: l.mvpT, child: Row(children: [
            Icon(roleIcon(Role.values.byName(ps[best.seat]['role'] as String)), color: roleColor(Role.values.byName(ps[best.seat]['role'] as String))), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ps[best.seat]['name'] as String, key: const Key('detailMvp'), style: head.copyWith(fontSize: 20)),
              Text(switch (best.why) { 'mafia' => l.mvpMafia, 'mafia2' => l.mvpMafia2, 'det' => l.mvpDet(best.n ?? 1), 'doc' => l.mvpDoc(best.n ?? 1), _ => l.mvpSurv },
                  style: TextStyle(color: C.mute)),
            ])),
          ])),
        Sec(title: l.roles, child: Column(children: [
          for (final p in ps)
            InkWell(
              key: Key('player_${p['seat']}'),
              // an account opens its profile from every verified game; a name only from the games I played in
              onTap: widget.account.signedIn ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(account: widget.account,
                  playerKey: p['userId'] != null ? 'u:${p['userId']}' : 'n:${p['name']}', filter: StatsFilter(board: p['userId'] != null ? 'all' : 'mine')))) : null,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
                Icon(roleIcon(Role.values.byName(p['role'] as String)), size: 18, color: roleColor(Role.values.byName(p['role'] as String))), const SizedBox(width: 8),
                Expanded(child: Text(p['name'] as String, style: TextStyle(decoration: p['alive'] == true ? null : TextDecoration.lineThrough))),
                Text(roleName(l, Role.values.byName(p['role'] as String))),
              ])),
            ),
        ])),
        Sec(title: l.history, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final e in (game['log'] as List).cast<Map>()) if (line(e).isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(line(e), style: TextStyle(color: C.mute))),
        ])),
      ]),
    );
  }
}
