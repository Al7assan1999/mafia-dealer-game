// The Wi-Fi room, run by the host phone: a Dart port of the Cloudflare Room (server/src/room.ts) and its chat rules
// (server/src/chat.ts), sending exactly the same messages, so every phone uses the online screens unchanged.
// Differences: no accounts or D1 (players bring a name, and their account id if signed in), no blocks, and the finished
// game goes to the phones (a `record` message) instead of a database.
import 'dart:convert';
import 'dart:math';

import 'package:mafia_engine/mafia_engine.dart';

const maxMembers = 20, keepEvents = 200, staleMs = 30000, chatKeep = 50, chatEditMs = 15 * 60 * 1000;

/// One phone's socket to the room.
abstract class LanConn {
  String get uid;
  void send(String data);
  void close([int code = 1000]);
}

/// Who a phone says it is (from its socket's identity token): a device id, a name, and its account if signed in.
class Identity {
  Identity(this.uid, this.display, {this.handle, this.userId, this.preset = 0});
  final String uid, display;
  final String? handle, userId;
  final int preset;

  static Identity? parse(String token) {
    try {
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token)))) as Map<String, Object?>;
      final id = j['id'] as String, n = (j['n'] as String).trim();
      if (id.isEmpty || id.length > 64 || n.isEmpty || n.length > 18) return null;
      return Identity(id, n, handle: j['h'] as String?, userId: j['u'] as String?, preset: (j['a'] as int?)?.clamp(0, 9) ?? 0);
    } catch (_) {
      return null;
    }
  }

  String token() => base64Url.encode(utf8.encode(jsonEncode({'id': uid, 'n': display, 'h': ?handle, 'u': ?userId, 'a': preset}))).replaceAll('=', '');
}

class _Member {
  _Member(this.uid, this.cn, this.display, this.handle, this.userId, this.preset);
  final String uid;
  final int cn;
  String display;
  String? handle, userId;
  int preset, buzz = 0;
  bool left = false;
  Map<String, Object?> toJson() => {'uid': uid, 'cn': cn, 'display': display, 'handle': handle, 'userId': userId, 'preset': preset, 'buzz': buzz, 'left': left};
  static _Member fromJson(Map j) => _Member(j['uid'] as String, j['cn'] as int, j['display'] as String, j['handle'] as String?, j['userId'] as String?, j['preset'] as int? ?? 0)
    ..buzz = j['buzz'] as int? ?? 0
    ..left = j['left'] == true;
}

class LocalRoom {
  LocalRoom(this.code, this.hostUid, {Map<String, Object?>? restore, this.onChange, int Function()? clock, double Function()? rng})
      : now = clock ?? (() => DateTime.now().millisecondsSinceEpoch), _rng = rng ?? Random.secure().nextDouble {
    if (restore != null) _restore(restore);
  }
  final String code;
  String hostUid;
  final int Function() now;
  final double Function() _rng;
  /// After every change (the host saves a snapshot for "Resume hosting").
  final void Function(LocalRoom room)? onChange;

  var members = <_Member>[];
  final kicked = <String>[];
  int nextCn = 1, deal = 0, buzzMax = 3, rev = 0, cut = 0;
  Rules rules = defaultRules;
  int mafia = 1, detective = 0;
  GameState? game;
  GameRecord? rec;
  var seats = <String>[], ready = <String>[];
  String? gameId;
  bool? valid;
  final past = <({int rev, List<Map<String, Object?>> events})>[];
  final lastIn = <String, String>{};
  // chat
  var chatSeq = 0;
  final chat = <Map<String, Object?>>[];
  final _sent = <int, List<int>>{}, _rxs = <int, List<int>>{};
  // sockets and when each last showed life
  final conns = <LanConn>[];
  final _seen = <LanConn, int>{};
  var _events = <GameEvent>[];

  bool get running => game != null && game!.phase != Phase.end;
  String get status => running ? 'game' : 'lobby';
  List<_Member> get _here => members.where((m) => !m.left).toList();
  bool online(String uid) => conns.any((c) => c.uid == uid);

  /// The host's controls: the host while connected, otherwise the first connected player in join order.
  String hostOf() {
    final h = _here;
    if (h.any((m) => m.uid == hostUid) && online(hostUid)) return hostUid;
    return h.where((m) => online(m.uid)).firstOrNull?.uid ?? hostUid;
  }

  // ---------------------------------------------------------------- what phones get
  Map<String, Object?> info() {
    final host = hostOf();
    return {
      'code': code, 'rules': rules.toJson(), 'counts': {'mafia': mafia, 'doctor': 1, 'detective': detective}, 'buzzMax': buzzMax,
      'status': status, 'deal': deal, 'gameId': gameId, 'valid': valid,
      'members': [
        for (final m in _here)
          {
            'uid': m.uid, 'cn': m.cn, 'display': m.display, 'handle': m.handle, 'avatar': {'preset': m.preset}, 'online': online(m.uid),
            'host': m.uid == host, 'ready': ready.contains(m.uid), 'muted': buzzMax > 0 && m.buzz >= buzzMax,
            'seat': game != null && seats.contains(m.uid) ? seats.indexOf(m.uid) : null,
          },
      ],
    };
  }

  void _out(LanConn c, Map<String, Object?> m) { try { c.send(jsonEncode(m)); } catch (_) {} }

  void _broadcast(List<Map<String, Object?>> events) {
    final room = info(), t = now();
    for (final c in List.of(conns)) {
      final m = members.where((x) => x.uid == c.uid).firstOrNull;
      if (m == null) continue;
      if (events.isNotEmpty) _out(c, {'t': 'events', 'rev': rev, 'events': events});
      _out(c, {'t': 'room', 'rev': rev, 'now': t, 'room': room,
        'me': {'uid': c.uid, 'cn': m.cn, 'host': (room['members'] as List).cast<Map>().where((x) => x['uid'] == c.uid).firstOrNull?['host'] ?? false}});
      final seat = seats.indexOf(c.uid);
      _out(c, {'t': 'view', 'rev': rev, 'view': game == null ? null : viewJson(viewFor(game!, seat >= 0 ? seat : null, t))});
    }
  }

  /// After every change: the finished game's record to every phone, rev, the kept events, and everyone's update.
  void _commit() {
    if (game?.phase == Phase.end && gameId == null) {
      gameId = 'wifi-${now()}';
      valid = true;
      final r = {'t': 'record', 'record': rec!.toJson(), 'names': game!.names, 'seats': seats, 'at': now(), 'code': code};
      for (final c in conns) { _out(c, r); }
    }
    final events = [for (final e in _events) if (e is! NightLog) e.toJson()];
    _events = [];
    rev++;
    if (events.isNotEmpty) {
      past.add((rev: rev, events: events));
      while (past.fold(0, (n, p) => n + p.events.length) > keepEvents) { cut = past.removeAt(0).rev; }
    }
    _broadcast(events);
    onChange?.call(this);
  }

  String? _play(Action a) {
    rec ??= startRecord(game!);
    final r = step(rec!, game!, a, Ctx(_rng, now()));
    if (!r.ok) return r.error;
    game = r.state;
    _events.addAll(r.events);
    return null;
  }

  // ---------------------------------------------------------------- connections
  /// A phone connects (since = the last rev it saw, for catch-up). Returns an error code if refused.
  String? join(LanConn c, Identity id, {int? since}) {
    if (kicked.contains(id.uid)) return _refuse(c, 'kicked');
    var m = members.where((x) => x.uid == id.uid).firstOrNull;
    if (m != null) {
      m..left = false..display = id.display..handle = id.handle..userId = id.userId..preset = id.preset;
    } else {
      if (running) return _refuse(c, 'started');
      if (members.length >= maxMembers) return _refuse(c, 'room_full');
      m = _Member(id.uid, nextCn++, id.display, id.handle, id.userId, id.preset);
      members.add(m);
    }
    conns.add(c);
    _seen[c] = now();
    if (since != null && since > 0 && since <= rev) {
      if (since < cut) { _out(c, {'t': 'missed'}); } else { for (final p in past) { if (p.rev > since) _out(c, {'t': 'events', 'rev': p.rev, 'events': p.events}); } }
    }
    _commit();
    final w = _who();
    _out(c, {'t': 'chatAll', 'msgs': chat.where((x) => _canSee(x, m!.cn, w)).toList()});
    return null;
  }

  String _refuse(LanConn c, String error) { _out(c, {'t': 'err', 'error': error}); c.close(4004); return error; }

  void closed(LanConn c) {
    conns.remove(c);
    _seen.remove(c);
    _commit(); // online dots and the host's controls may move
  }

  /// Every few seconds: the night timer, and sockets silent for 30 s closed (the phone lost the Wi-Fi).
  void tick() {
    var changed = false;
    final t = now();
    if (game?.phase == Phase.night && game!.night.endsAt != 0 && t >= game!.night.endsAt) changed = _play(const Action.skipPending()) == null;
    for (final c in List.of(conns)) {
      if (t - (_seen[c] ?? 0) < staleMs) continue;
      conns.remove(c);
      _seen.remove(c);
      c.close(4001);
      changed = true;
    }
    if (changed) _commit();
  }

  void message(LanConn c, String raw) {
    _seen[c] = now();
    if (raw == 'ping') { c.send('pong'); return; }
    Map<String, Object?> inp;
    try { inp = jsonDecode(raw) as Map<String, Object?>; } catch (_) { return _out(c, {'t': 'err', 'error': 'bad_request'}); }
    final uid = c.uid, m = _here.where((x) => x.uid == uid).firstOrNull, t = inp['t'];
    if (m == null) return _out(c, {'t': 'err', 'error': 'not_member'});
    void err(String e) => _out(c, {'t': 'err', 'error': e, 'ref': t});
    if (t == 'chat' || t == 'react' || t == 'edit') return _chat(c, m.cn, inp);
    final key = t == 'night' || t == 'vote' || t == 'ready' ? jsonEncode(inp) : null;
    if (key != null && lastIn[uid] == key) return; // a repeat after a drop: already applied
    const hostOnly = {'setup', 'deal', 'start', 'startDay', 'timer', 'startVote', 'nextNight', 'continue', 'kick', 'unmute', 'ping', 'mark', 'lobby', 'close'};
    if (hostOnly.contains(t) && hostOf() != uid) return err('forbidden');
    final seat = seats.indexOf(uid), g = game;
    String? e;
    switch (t) {
      case 'setup':
        if (running) return err('started');
        try {
          rules = defaultRules.merge(Map<String, Object?>.from(inp['rules'] as Map));
          final cc = inp['counts'] as Map;
          mafia = (cc['mafia'] as int).clamp(1, 10);
          detective = (cc['detective'] as int).clamp(0, 1);
          buzzMax = (inp['buzzMax'] as int? ?? 3).clamp(0, 20);
        } catch (_) { return err('bad_request'); }
      case 'deal':
        if (running) return err('started');
        final players = _here;
        final r = createGame(Setup(_seatNames(players), Counts(mafia, 1, detective), rules), _rng, deal + 1);
        if (r.error != null) return err(r.error!);
        deal++;
        game = r.state;
        rec = startRecord(r.state!);
        seats = [for (final p in players) p.uid];
        ready = [];
        gameId = null;
        valid = null;
        lastIn.clear();
        members = members.where((x) => !x.left).toList();
      case 'start': if (g?.phase != Phase.deal) return err('phase'); e = _play(const Action.begin());
      case 'ready':
        if (g?.phase != Phase.deal || inp['deal'] != deal || seat < 0) return err('phase');
        if (!ready.contains(uid)) ready.add(uid);
        if (seats.every(ready.contains)) e = _play(const Action.begin());
      case 'night':
        if (g == null || seat < 0) return err('phase');
        e = _play(Action.night(seat, inp['choice'], day: inp['day'] as int?));
      case 'vote':
        if (g == null || seat < 0) return err('phase');
        e = _play(Action.vote(seat, inp['choice'] ?? 'none', id: inp['id'] as int?));
      case 'startDay': if (g == null) return err('phase'); e = _play(const Action.startDay());
      case 'timer':
        if (g == null) return err('phase');
        e = _play(inp['op'] == 'add' ? Action.timer('add', sec: inp['sec'] as int? ?? 60) : Action.timer(inp['op'] as String));
      case 'startVote': if (g == null) return err('phase'); e = _play(Action.startVote(inp['open'] == true));
      case 'nextNight': if (g == null) return err('phase'); e = _play(const Action.nextNight());
      case 'continue':
        if (g == null || (g.phase != Phase.night && g.phase != Phase.vote)) return err('phase');
        final pending = [for (var i = 0; i < g.alive.length; i++) if (g.alive[i] && (g.phase == Phase.night ? !g.night.done.contains(i) : !g.vote!.votes.containsKey(i))) i];
        final off = pending.where((i) => !online(seats[i])).toList();
        if (off.isEmpty) return err('nothing');
        e = _play(Action.skipPending(off));
      case 'kick':
        final who = inp['uid'] as String?;
        if (who == uid || !members.any((x) => x.uid == who)) return err('not_member');
        final s = seats.indexOf(who!);
        if (running && s >= 0 && g!.alive[s] && g.phase != Phase.deal) e = _play(Action.remove(s));
        if (e != null) return err(e);
        kicked.add(who);
        _drop(who, 'kicked');
        if (hostUid == who) hostUid = uid;
      case 'unmute':
        for (final x in members) { if (x.uid == inp['uid']) x.buzz = 0; }
      case 'ping':
        for (final x in conns) { if (x != c) _out(x, {'t': 'ping'}); }
        return;
      case 'buzz':
        m.buzz++;
        if (buzzMax == 0 || m.buzz <= buzzMax) { for (final x in conns.where((x) => x.uid == hostOf())) { _out(x, {'t': 'buzz', 'from': uid}); } }
      case 'mark':
        if (g?.phase != Phase.end || gameId == null) return err('phase');
        valid = inp['valid'] == true;
      case 'lobby':
        if (g?.phase != Phase.end) return err('phase');
        game = null; rec = null; seats = []; ready = []; gameId = null; valid = null; lastIn.clear();
      case 'close':
        for (final x in List.of(conns)) { _out(x, {'t': 'bye', 'why': 'closed'}); x.close(4000); }
        conns.clear();
        closedRoom = true;
        onChange?.call(this);
        return;
      case 'leave':
        _drop(uid, 'left');
      default:
        return err('bad_request');
    }
    if (e != null) return err(e);
    if (key != null) lastIn[uid] = key;
    _commit();
  }

  bool closedRoom = false;

  /// Someone leaves for good (left, kicked); in a running game their seat stays (a leaver may come back).
  void _drop(String uid, String why) {
    final m = members.where((x) => x.uid == uid).firstOrNull;
    if (m == null) return;
    if (why == 'left' && running && seats.contains(uid)) { m.left = true; } else { members.remove(m); }
    ready.remove(uid);
    for (final x in conns.where((x) => x.uid == uid).toList()) { _out(x, {'t': 'bye', 'why': why}); x.close(4000); conns.remove(x); }
    if (uid == hostUid) hostUid = members.where((x) => !x.left).firstOrNull?.uid ?? hostUid;
  }

  /// Seat names: display names, with handles (then numbers) where two would be the same.
  static List<String> _seatNames(List<_Member> ms) {
    int n(String k) => ms.where((m) => nameKey(m.display) == k).length;
    final names = [for (final m in ms) (n(nameKey(m.display)) > 1 ? (m.handle ?? m.display) : m.display).substring(0, min(18, (n(nameKey(m.display)) > 1 ? (m.handle ?? m.display) : m.display).length))];
    return [
      for (var i = 0; i < names.length; i++)
        names.where((y) => nameKey(y) == nameKey(names[i])).length > 1 ? '${names[i].substring(0, min(15, names[i].length))} ${i + 1}' : names[i],
    ];
  }

  // ---------------------------------------------------------------- chat (server/src/chat.ts)
  ({Set<int> members, Set<int> outs}) _who() {
    final outs = <int>{};
    if (running) { for (final m in members) { final s = seats.indexOf(m.uid); if (s >= 0 && !game!.alive[s]) outs.add(m.cn); } }
    return (members: {for (final m in _here) m.cn}, outs: outs);
  }
  static bool _canSee(Map<String, Object?> m, int viewer, ({Set<int> members, Set<int> outs}) w) =>
      m['to'] == -1 ? m['outOnly'] != true || w.outs.contains(viewer) : viewer == m['from'] || viewer == m['to'];
  static String _conv(Map<String, Object?> m) => m['to'] == -1 ? 'all' : ([m['from'] as int, m['to'] as int]..sort()).join(':');
  bool _rate(Map<int, List<int>> log, int who, int max, int t) {
    final recent = (log[who] ?? []).where((x) => t - x < 10000).toList();
    if (recent.length >= max) { log[who] = recent; return false; }
    log[who] = [...recent, t];
    return true;
  }

  void _chat(LanConn c, int me, Map<String, Object?> inp) {
    final w = _who(), t = now(), out = w.outs.contains(me);
    void err(String e) => _out(c, {'t': 'err', 'error': e, 'ref': inp['t'] == 'chat' ? inp['cid'] : inp['t']});
    Map<String, Object?> msg;
    var mentions = <int>[];
    if (inp['t'] == 'chat') {
      final to = inp['to'] as int? ?? -1, text = ((inp['text'] as String?) ?? '').trim();
      if (text.isEmpty || text.length > 200) return err('bad_request');
      if (to != -1 && (!w.members.contains(to) || to == me)) return err('to');
      if (out && to != -1 && !w.outs.contains(to)) return err('out');
      msg = {'id': 0, 'from': me, 'to': to, 'text': text, 'at': t, if (out && to == -1) 'outOnly': true};
      final reply = inp['reply'] as int?;
      if (reply != null) {
        final r = chat.where((x) => x['id'] == reply).firstOrNull;
        if (r == null || _conv(r) != _conv(msg) || !_canSee(r, me, w)) return err('reply');
        msg['reply'] = reply;
      }
      mentions = {...((inp['mentions'] as List?) ?? const []).cast<int>()}.where((x) => x != me && w.members.contains(x) && _canSee(msg, x, w)).toList();
      if (mentions.isNotEmpty) msg['mentions'] = mentions;
      if (!_rate(_sent, me, 8, t)) return err('slow_down');
      msg['id'] = ++chatSeq;
      chat.add(msg);
      final same = chat.where((x) => _conv(x) == _conv(msg)).toList();
      if (same.length > chatKeep) { final drop = same.take(same.length - chatKeep).map((x) => x['id']).toSet(); chat.removeWhere((x) => drop.contains(x['id'])); }
    } else if (inp['t'] == 'react') {
      final m = chat.where((x) => x['id'] == inp['id']).firstOrNull, rx = inp['rx'] as int? ?? -1;
      if (m == null || !_canSee(m, me, w) || rx < 0 || rx >= 30) return err('not_found');
      if (out && m['to'] == -1 && m['outOnly'] != true) return err('out');
      if (!_rate(_rxs, me, 20, t)) return err('slow_down');
      final rxs = Map<String, Object?>.from((m['rx'] as Map?) ?? {}), list = [...((rxs['$rx'] as List?) ?? const []).cast<int>()];
      list.contains(me) ? list.remove(me) : list.add(me);
      list.isEmpty ? rxs.remove('$rx') : rxs['$rx'] = list;
      rxs.isEmpty ? m.remove('rx') : m['rx'] = rxs;
      msg = m;
    } else {
      final m = chat.where((x) => x['id'] == inp['id']).firstOrNull, text = ((inp['text'] as String?) ?? '').trim();
      if (m == null || m['from'] != me || text.isEmpty || text.length > 200) return err('not_found');
      if (t - (m['at'] as int) > chatEditMs) return err('too_late');
      m['text'] = text;
      m['edited'] = true;
      msg = m;
    }
    for (final s in List.of(conns)) {
      final mm = _here.where((x) => x.uid == s.uid).firstOrNull;
      if (mm == null || !_canSee(msg, mm.cn, w)) continue;
      _out(s, {'t': 'chat', 'msg': msg, if (s == c && inp['t'] == 'chat') 'cid': inp['cid']});
      if (mentions.contains(mm.cn)) _out(s, {'t': 'mention', 'id': msg['id'], 'from': me});
    }
    onChange?.call(this);
  }

  // ---------------------------------------------------------------- "Resume hosting": a snapshot of the room and game
  Map<String, Object?> toJson() => {
        'v': 1, 'code': code, 'hostUid': hostUid, 'members': [for (final m in members) m.toJson()], 'kicked': kicked, 'nextCn': nextCn,
        'deal': deal, 'buzzMax': buzzMax, 'rev': rev, 'cut': cut, 'rules': rules.toJson(), 'mafia': mafia, 'detective': detective,
        'rec': rec?.toJson(), 'seats': seats, 'ready': ready, 'gameId': gameId, 'valid': valid,
        'past': [for (final p in past) {'rev': p.rev, 'events': p.events}], 'lastIn': lastIn, 'chatSeq': chatSeq, 'chat': chat,
      };

  void _restore(Map<String, Object?> j) {
    hostUid = j['hostUid'] as String;
    members = [for (final m in (j['members'] as List)) _Member.fromJson(m as Map)];
    kicked.addAll((j['kicked'] as List).cast<String>());
    nextCn = j['nextCn'] as int; deal = j['deal'] as int; buzzMax = j['buzzMax'] as int; rev = j['rev'] as int; cut = j['cut'] as int;
    rules = defaultRules.merge(Map<String, Object?>.from(j['rules'] as Map));
    mafia = j['mafia'] as int; detective = j['detective'] as int;
    seats = (j['seats'] as List).cast<String>(); ready = (j['ready'] as List).cast<String>();
    gameId = j['gameId'] as String?; valid = j['valid'] as bool?;
    for (final p in (j['past'] as List).cast<Map>()) { past.add((rev: p['rev'] as int, events: (p['events'] as List).map((e) => Map<String, Object?>.from(e as Map)).toList())); }
    lastIn.addAll(Map<String, String>.from(j['lastIn'] as Map));
    chatSeq = j['chatSeq'] as int;
    chat.addAll((j['chat'] as List).map((m) => Map<String, Object?>.from(m as Map)));
    final r = j['rec'];
    if (r != null) {
      final re = replay(r); // the game is rebuilt from its record (the engine checks it)
      if (re.error == null) { game = re.state; rec = _record(Map<String, Object?>.from(r as Map)); }
    }
  }

  static GameRecord _record(Map<String, Object?> j) => GameRecord(
        j['deal'] as int, (j['names'] as List).cast<String>(), defaultRules.merge(Map<String, Object?>.from(j['rules'] as Map)),
        (j['roles'] as List).map((x) => Role.values.byName(x as String)).toList(),
        (j['actions'] as List).map((x) {
          final m = x as Map;
          return RecordedAction(Action.fromJson(Map<String, Object?>.from(m['a'] as Map)), m['at'] as int, (m['r'] as List?)?.map((d) => (d as num).toDouble()).toList());
        }).toList(),
        j['winner'] == null ? null : Winner.values.byName(j['winner'] as String), (j['log'] as List).cast<Object?>());
}

/// A view as JSON, exactly as the TypeScript engine's viewFor() serializes (the phones read the same shape online).
Map<String, Object?> viewJson(View v) {
  Map<String, Object?>? result() {
    final r = v.result;
    if (r == null) return null;
    return {'k': r.k, if (r.seat != null) 'seat': r.seat, if (r.k == 'killed' || r.k == 'out') 'role': r.role?.name,
      if (r.k == 'out' || r.k == 'tie' || r.k == 'skipped') 'tally': r.tally?.map((x) => x.toJson()).toList()};
  }
  final rc = v.recap;
  return {
    'deal': v.deal, 'phase': v.phase.name, 'day': v.day,
    'roster': [for (final r in v.roster) {'name': r.name, 'alive': r.alive}],
    'timer': v.timerEnd != null ? {'end': v.timerEnd} : v.timerLeft != null ? {'left': v.timerLeft} : null,
    'progress': v.progress == null ? null : {'done': v.progress!.done, 'total': v.progress!.total},
    'board': v.board?.map((b) => {'seat': b.seat, 'v': b.v}).toList(),
    'voteId': v.voteId, 'result': result(), 'winner': v.winner?.name, 'roles': v.roles?.map((r) => r.name).toList(),
    'recap': rc == null ? null : {
      'winner': rc.winner.name, 'names': rc.names, 'roles': rc.roles.map((r) => r.name).toList(), 'alive': rc.alive, 'day': rc.day,
      'stats': {'first': rc.stats.first, 'kills': rc.stats.kills, 'outs': rc.stats.outs, 'saves': rc.stats.saves, 'caught': [for (final c in rc.stats.caught) [c.$1, c.$2]]},
    },
    if (v.seat != null) ...{
      'seat': v.seat, 'role': v.role?.name, 'alive': v.alive, 'mates': v.mates,
      'check': v.check == null ? null : {'seat': v.check!.seat, 'mafia': v.check!.mafia},
      'ph': v.ph,
      'night': v.night == null ? null : {
        'key': v.night!.key,
        'opts': [for (final o in v.night!.opts) {'seat': o.seat, 'disabled': o.disabled, 'self': o.self, 'teammate': o.teammate, 'lastTarget': o.lastTarget, 'lastNight': o.lastNight, 'mateVotes': o.mateVotes}],
        'skip': v.night!.canSkip ? {'mateVotes': v.night!.skipMateVotes} : null,
      },
      'voteOpts': v.voteOpts?.map((o) => {'seat': o.seat, 'disabled': o.disabled}).toList(),
    },
  };
}
