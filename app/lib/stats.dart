// Stats (S8): the old app's titles, leaderboard and player profile; Mine / Everyone with filters; sharing a profile card;
// importing the old app's history and its games in History → Old app.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mafia_engine/mafia_engine.dart' show Role;
import 'package:share_plus/share_plus.dart';

import 'account.dart';
import 'account_screens.dart';
import 'api.dart';
import 'l10n/app_localizations.dart';
import 'online.dart' show onlineLobby;
import 'ui.dart';

String _pct(num w, num g) => g == 0 ? '–' : '${(w / g * 100).round()}%';

/// Tiles two per row, each row as tall as its tallest tile ([QA] S8 #1: a fixed-ratio grid cut the text off).
Widget _pairs(List<Widget> tiles) => Column(children: [
      for (var i = 0; i < tiles.length; i += 2)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: tiles[i]),
          const SizedBox(width: 8),
          Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
        ]))),
    ]);

/// The filters every stats view shares.
class StatsFilter {
  const StatsFilter({this.board = 'mine', this.source = 'all', this.days = 0});
  final String board, source;
  final int days;
  StatsFilter copy({String? board, String? source, int? days}) => StatsFilter(board: board ?? this.board, source: source ?? this.source, days: days ?? this.days);
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.account});
  final Account account;
  @override
  State<StatsScreen> createState() => _StatsState();
}

class _StatsState extends State<StatsScreen> {
  StatsFilter f = const StatsFilter();
  Map<String, Object?>? data;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { data = null; error = null; });
    final want = f;
    try {
      final d = await widget.account.stats(board: f.board, source: f.source, days: f.days);
      if (mounted && identical(want, f)) setState(() => data = d);
    } catch (e) { if (mounted) setState(() => error = errText(L.of(context), e)); }
  }
  void _set(StatsFilter n) { f = n; _load(); }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), d = data;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.statsT, style: head.copyWith(fontSize: 20))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: SegmentedButton<String>(
          key: const Key('statsBoard'),
          segments: [ButtonSegment(value: 'mine', label: Text(l.tabMine, key: const Key('boardMine'))), ButtonSegment(value: 'all', label: Text(l.tabEveryone, key: const Key('boardAll')))],
          selected: {f.board}, showSelectedIcon: false,
          style: SegmentedButton.styleFrom(selectedBackgroundColor: C.red, selectedForegroundColor: C.priText, side: BorderSide(color: C.line2)),
          onSelectionChanged: (s) => _set(f.copy(board: s.first, source: s.first == 'all' && f.source == 'old' ? 'all' : null)),
        )),
        // [QA] S8 #4: the period chips sat off-screen in one scrolling row; two rows that wrap
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, t) in [('all', l.fAll), ('online', l.tabOnline), ('wifi', l.tabWifi), if (f.board == 'mine') ('old', l.fOld)])
              ChoiceChip(key: Key('src_$k'), label: Text(t), selected: f.source == k, onSelected: (_) => _set(f.copy(source: k))),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, t) in [(0, l.fAllTime), (30, l.f30)])
              ChoiceChip(key: Key('days_$k'), label: Text(t), selected: f.days == k, onSelected: (_) => _set(f.copy(days: k))),
          ]),
        ])),
        Expanded(child: error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(error!, textAlign: TextAlign.center, style: TextStyle(color: C.red2))),
              TextButton.icon(key: const Key('statsRetry'), onPressed: _load, icon: Icon(Icons.refresh, color: C.text), label: Text(l.retry, style: TextStyle(color: C.text))),
            ]))
            : d == null ? Center(child: CircularProgressIndicator(color: C.red2))
            : _body(l, d)),
      ]),
    );
  }

  Widget _body(L l, Map<String, Object?> d) {
    final board = (d['board'] as List).cast<Map>(), titles = Map<String, Object?>.from(d['titles'] as Map), min = d['minGames'] as int;
    final me = d['me'] as Map?;
    final note = f.board == 'all' ? l.boardEveryone(min) : '${l.boardMine(min)} ${l.boardFrom}';
    if (board.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Text(l.noStats, key: const Key('noStats'), textAlign: TextAlign.center, style: TextStyle(color: C.mute))),
        Text(note, textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 12)),
      ]);
    }
    Widget title(String k, String label, String Function(Map p) sub, {bool wide = false}) {
      final p = titles[k] as Map?;
      if (p == null) return const SizedBox.shrink();
      final box = Container(
        key: Key('title_$k'), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.card, border: Border.all(color: k == 'best' ? C.gold : C.line), borderRadius: BorderRadius.circular(C.p.radius)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: head.copyWith(fontSize: 11, color: C.mute, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text(p['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: head.copyWith(fontSize: wide ? 22 : 17, color: k == 'best' ? C.gold : C.text)),
          Text(sub(p), style: TextStyle(color: C.dim, fontSize: 12)),
        ]),
      );
      return InkWell(onTap: () => _open(p), child: box);
    }
    final small = [
      title('mafia', l.tMafia, (p) => l.tMafiaSub(p['mw'] as int, p['mg'] as int)),
      title('det', l.tDet, (p) => l.tDetSub(p['ct'] as int)),
      title('doc', l.tDoc, (p) => l.tDocSub(p['sv'] as int)),
      title('first', l.tFirst, (p) => l.tFirstSub(p['fk'] as int)),
    ];
    return RefreshIndicator(onRefresh: _load, color: C.red2, child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      title('best', l.tBest, (p) => l.tBestSub(((p['r'] as num) * 100).round(), p['w'] as int, p['g'] as int), wide: true),
      const SizedBox(height: 8),
      _pairs([for (final w in small) if (w is! SizedBox) w]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Text(l.boardT.toUpperCase(), style: head.copyWith(fontSize: 14, color: C.mute, letterSpacing: 2))),
        if (f.board == 'all' && me != null && me['rank'] != null) Text(l.youRank(me['rank'] as int), key: const Key('myRank'), style: TextStyle(color: C.gold)),
      ]),
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(note, key: const Key('boardNote'), style: TextStyle(color: C.dim, fontSize: 12, height: 1.4))),
      for (final p in board) _row(l, p, min),
      if (f.board == 'all' && me != null && !board.any((p) => p['me'] == true)) ...[Divider(color: C.line), _row(l, me, min)],
    ]));
  }

  Widget _row(L l, Map p, int min) {
    final q = p['q'] == true, mine = p['me'] == true, rank = p['rank'] as int?;
    return InkWell(
      key: Key('row_${p['key']}'), onTap: () => _open(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: mine ? C.card2 : C.card, border: Border.all(color: mine ? C.red : C.line), borderRadius: BorderRadius.circular(C.p.radius)),
        child: Opacity(opacity: q ? 1 : .55, child: Row(children: [
          SizedBox(width: 30, child: Text(q ? '$rank' : '–', style: head.copyWith(fontSize: 17, color: rank == 1 ? C.gold : C.mute))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(l.sideLine(p['mw'] as int, p['mg'] as int, p['tw'] as int, p['tg'] as int), style: TextStyle(color: C.dim, fontSize: 12)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(q ? _pct(p['w'] as int, p['g'] as int) : l.needN(min), style: TextStyle(color: q ? C.text : C.dim, fontWeight: FontWeight.w700, fontSize: q ? 16 : 12)),
            Text(l.winsShort(p['w'] as int, p['g'] as int), style: TextStyle(color: C.dim, fontSize: 12)),
          ]),
        ])),
      ),
    );
  }

  void _open(Map p) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(account: widget.account, playerKey: p['key'] as String, filter: f)));
}

/// A player's profile (S8-2): the old app's, plus the best partner and a card to share.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.account, required this.playerKey, this.filter = const StatsFilter(), this.person});
  final Account account;
  final String playerKey;
  final Person? person; // [N2] a friend or a player: their card shows even with no games yet
  final StatsFilter filter;
  @override
  State<PlayerScreen> createState() => _PlayerState();
}

class _PlayerState extends State<PlayerScreen> {
  Map<String, Object?>? p;
  String? error;
  bool none = false; // no counted games (yet)
  final _card = GlobalKey();

  @override
  void initState() {
    super.initState();
    final f = widget.filter;
    widget.account.player(widget.playerKey, board: f.board, source: f.source, days: f.days)
        .then((x) { if (mounted) setState(() => p = x); })
        .catchError((Object e) {
          if (!mounted) return;
          setState(() => e is ApiError && e.code == 'not_found' ? none = true : error = errText(L.of(context), e));
        });
  }

  /// P3: the profile card as a picture, to the share sheet.
  Future<void> _share() async {
    final b = _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (b == null) return;
    final img = await b.toImage(pixelRatio: 3), data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    // share_plus writes the bytes to a temporary file itself
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: 'mafia-profile.png')],
        fileNameOverrides: ['mafia-profile.png'], text: 'Mafia Dealer: ${p?['name']}'));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), x = p;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(x?['name'] as String? ?? widget.person?.display ?? '', style: head.copyWith(fontSize: 20)), actions: [
        if (x != null) IconButton(key: const Key('shareProfile'), tooltip: l.shareProfile, icon: Icon(Icons.ios_share, color: C.mute), onPressed: _share),
      ]),
      body: none ? _nobody(l)
          : error != null ? Center(child: Text(error!, style: TextStyle(color: C.red2)))
          : x == null ? Center(child: CircularProgressIndicator(color: C.red2))
          : ListView(padding: const EdgeInsets.all(16), children: [
              RepaintBoundary(key: _card, child: Container(color: C.bg, child: _card_(l, x))),
              ..._rest(l, x),
            ]),
    );
  }

  /// [R3] Who this is, live from my friends list when they're a friend (a lobby passes a bare card), and how we're related.
  Person? get _who {
    final f = widget.person, a = widget.account;
    if (f == null) return null;
    return a.friends.where((x) => x.id == f.id).firstOrNull ?? a.incoming.where((x) => x.id == f.id).firstOrNull ?? a.outgoing.where((x) => x.id == f.id).firstOrNull ?? f;
  }
  String _rel(Person f) {
    final a = widget.account;
    if (f.id == a.me?['id']) return 'me';
    if (a.friends.any((x) => x.id == f.id)) return 'friends';
    if (a.outgoing.any((x) => x.id == f.id)) return 'requested';
    if (a.incoming.any((x) => x.id == f.id)) return 'incoming';
    return f.rel == 'me' ? 'me' : 'none';
  }

  Future<void> _act(Future<void> Function() f, String done) async {
    final l = L.of(context);
    try { await f(); if (mounted) { toast(context, done); setState(() {}); } } catch (e) { if (mounted) toastErr(context, errText(l, e)); }
  }

  /// [R3] A player with no counted games still gets a whole profile: who, status, friendship, what I can do, and the
  /// stat tiles empty ("–") so it reads as their page, not an empty one.
  Widget _nobody(L l) {
    final f = _who;
    Widget tile(String k) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.card, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(C.p.radius)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k.toUpperCase(), style: head.copyWith(fontSize: 11, color: C.mute, letterSpacing: 1.5)),
            Text('–', style: head.copyWith(fontSize: 19, color: C.dim)),
            Text(l.winsShort(0, 0), style: TextStyle(color: C.dim, fontSize: 12)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (f != null) ..._header(l, f),
      const SizedBox(height: 18),
      tile(l.winRate),
      const SizedBox(height: 8),
      _pairs([tile(l.bestRole), tile(l.asMafiaT), tile(l.asTownT)]),
      Padding(padding: const EdgeInsets.only(top: 24), child: Text(l.noGamesYet, key: const Key('noGamesYet'), textAlign: TextAlign.center, style: head.copyWith(fontSize: 18, color: C.mute))),
      Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.pNoGamesD, textAlign: TextAlign.center, style: TextStyle(color: C.dim))),
    ]);
  }

  List<Widget> _header(L l, Person f) {
    final a = widget.account, rel = _rel(f), friend = rel == 'friends', lobby = onlineLobby();
    final status = !friend ? null : friendStatus(l, f);
    final statusColor = !f.online ? C.dim : f.status == 'game' ? C.red2 : f.status == 'lobby' ? C.gold : C.green;
    final fav = f.fav.isEmpty ? null : Role.values.byName(f.fav);
    return [
      Center(child: AvatarView.of(a.api, f, size: 96, online: friend ? f.online : null)),
      const SizedBox(height: 12),
      Text(f.display, key: const Key('profileName'), textAlign: TextAlign.center, style: head.copyWith(fontSize: 26)),
      if (f.handle != null) Text(atHandle(f.handle), textAlign: TextAlign.center, style: TextStyle(color: C.mute)),
      const SizedBox(height: 10),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
        if (status != null) Chip(key: const Key('profileStatus'), avatar: Icon(Icons.circle, size: 10, color: statusColor), label: Text(status), visualDensity: VisualDensity.compact),
        if (friend) Chip(avatar: Icon(Icons.people_alt_outlined, size: 16, color: C.green), label: Text(l.friendsT), visualDensity: VisualDensity.compact),
        if (fav != null) Chip(avatar: Icon(roleIcon(fav), size: 16, color: roleColor(fav)), label: Text(roleName(l, fav)), visualDensity: VisualDensity.compact),
      ]),
      const SizedBox(height: 12),
      if (rel == 'none' && f.handle != null)
        Btn(l.pAddFriend, key: const Key('profileAdd'), icon: Icons.person_add_alt, onTap: () => _act(() async { await a.request(f.handle!); }, l.fReqSent(atHandle(f.handle)))),
      if (rel == 'requested') Text(l.pRequested, key: const Key('profileRequested'), textAlign: TextAlign.center, style: TextStyle(color: C.gold)),
      if (rel == 'incoming') Btn(l.fAccept, key: const Key('profileAccept'), icon: Icons.check, onTap: () => _act(() => a.accept(f.id), l.fNowFriends(f.display))),
      if (friend && lobby != null && !lobby.members.any((m) => m['uid'] == f.id))
        Btn(l.invite, key: const Key('profileInvite'), ghost: true, icon: Icons.mail_outline, onTap: () => _act(() => a.invite(f.id, lobby.code), l.invited)),
      if (friend && lobby == null && f.online && f.status == 'lobby' && f.j['op'] == true && a.roomCode == null)
        Btn(l.askJoin, key: const Key('profileAsk'), ghost: true, icon: Icons.login, onTap: () => _act(() => a.askToJoin(f.id), l.asked)),
    ];
  }

  /// The shareable part: who, the win rate and the four headline numbers.
  Widget _card_(L l, Map<String, Object?> x) {
    final roles = Map<String, Object?>.from(x['roles'] as Map), best = Role.values.byName(x['best'] as String), br = (roles[best.name] as List).cast<int>();
    final mafia = (x['mafia'] as List).cast<int>(), side = (x['side'] as List).cast<int>(), nem = x['nemesis'] as Map?, card = x['card'] as Map?;
    Widget tile(String k, String big, String sub, {Color? color}) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.card, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(C.p.radius)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k.toUpperCase(), style: head.copyWith(fontSize: 11, color: C.mute, letterSpacing: 1.5)),
            Text(big, maxLines: 1, overflow: TextOverflow.ellipsis, style: head.copyWith(fontSize: 19, color: color ?? C.text)),
            Text(sub, style: TextStyle(color: C.dim, fontSize: 12)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (card != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
        AvatarView.of(widget.account.api, Person(Map<String, Object?>.from(card)), size: 48),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x['name'] as String, style: head.copyWith(fontSize: 22)),
          if (card['handle'] != null) Text(atHandle(card['handle'] as String), style: TextStyle(color: C.mute)),
        ])),
      ])),
      tile(l.winRate, _pct(x['wins'] as int, x['games'] as int), l.winsShort(x['wins'] as int, x['games'] as int), color: C.gold),
      const SizedBox(height: 8),
      _pairs([
        tile(l.bestRole, roleName(l, best), l.winsShort(br[1], br[0]), color: roleColor(best)),
        tile(l.asMafiaT, _pct(mafia[1], mafia[0]), l.winsShort(mafia[1], mafia[0])),
        tile(l.asTownT, _pct(side[1], side[0]), l.winsShort(side[1], side[0])),
        tile(l.nemesis, nem?['name'] as String? ?? '–', nem == null ? l.nemesisNone : l.nTimes(nem['n'] as int)),
      ]),
      const SizedBox(height: 6),
      Text('MAFIA DEALER', textAlign: TextAlign.end, style: head.copyWith(fontSize: 10, color: C.dim, letterSpacing: 3)),
    ]);
  }

  List<Widget> _rest(L l, Map<String, Object?> x) {
    final roles = Map<String, Object?>.from(x['roles'] as Map), m = Map<String, Object?>.from(x['moments'] as Map), part = x['partner'] as Map?;
    final form = (x['form'] as List).cast<bool>();
    return [
      const SizedBox(height: 14),
      Sec(title: l.partner, child: Row(children: [
        Icon(Icons.handshake_outlined, color: C.red2), const SizedBox(width: 10),
        Expanded(child: Text(part?['name'] as String? ?? l.partnerNone, key: const Key('partner'), style: const TextStyle(fontWeight: FontWeight.w700))),
        if (part != null) Text(l.nTogether(part['n'] as int), style: TextStyle(color: C.dim)),
      ])),
      Sec(title: l.byRole, child: Column(children: [
        for (final r in Role.values)
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
            SizedBox(width: 86, child: Text(roleName(l, r), style: TextStyle(color: roleColor(r), fontWeight: FontWeight.w700))),
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(
                value: (roles[r.name] as List)[0] == 0 ? 0 : ((roles[r.name] as List)[1] as int) / ((roles[r.name] as List)[0] as int),
                minHeight: 8, backgroundColor: C.card2, color: roleColor(r)))),
            SizedBox(width: 48, child: Text('${(roles[r.name] as List)[1]}/${(roles[r.name] as List)[0]}', textAlign: TextAlign.end, style: TextStyle(color: C.dim))),
          ])),
      ])),
      Sec(title: l.moments, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        for (final (n, t) in [(m['saves'], l.psSaves), (m['caught'], l.psCaught), (m['killed'], l.psKilled), (m['out'], l.psOut)])
          Column(children: [Text('$n', style: head.copyWith(fontSize: 22)), Text(t, style: TextStyle(color: C.dim, fontSize: 12))]),
      ])),
      Sec(title: l.form, child: Wrap(spacing: 6, children: [
        for (final w in form) Container(width: 30, height: 30, alignment: Alignment.center,
            decoration: BoxDecoration(color: w ? C.green.withValues(alpha: .2) : C.red.withValues(alpha: .2), border: Border.all(color: w ? C.green : C.red2), borderRadius: BorderRadius.circular(C.neon ? 10 : 3)),
            child: Text(w ? l.fW : l.fL, style: TextStyle(color: w ? C.green : C.red2, fontWeight: FontWeight.w700))),
      ])),
    ];
  }
}

/// Profile → Import old history (S8-3).
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.account});
  final Account account;
  @override
  State<ImportScreen> createState() => _ImportState();
}

class _ImportState extends State<ImportScreen> {
  final code = TextEditingController();
  Map<String, Object?>? names;
  String? result;
  bool busy = false;

  @override
  void initState() { super.initState(); _names(); }
  Future<void> _names() async { try { final n = await widget.account.oldNames(); if (mounted) setState(() => names = n); } catch (_) {} }

  Future<void> _import() async {
    final l = L.of(context);
    setState(() { busy = true; result = null; });
    try {
      final r = await widget.account.importOld(code.text);
      // [S12-1] every game is kept; say what waits for names and what couldn't be read
      final waiting = r['waiting'] as int? ?? 0, broken = r['broken'] as int? ?? 0;
      final line = [l.importFound(r['found'] as int? ?? 0, r['imported'] as int, r['duplicates'] as int),
        if (waiting > 0) l.importWaiting(waiting), if (broken > 0) l.importBroken(broken)].join(' ');
      if (mounted) setState(() => result = line);
    } catch (e) {
      if (mounted) setState(() => result = e is ApiError && e.code == 'not_found' ? l.importNotFound : e is ApiError && e.code == 'busy' ? l.importDown : errText(l, e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() { code.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), list = (names?['names'] as List?)?.cast<Map>() ?? const [], mine = names?['mine'] as String?;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.importT, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, children: [
        Sec(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.importD, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final s in [l.importS1, l.importS2]) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(s, style: TextStyle(color: C.mute))),
          const SizedBox(height: 6),
          Text(l.importS3, style: TextStyle(color: C.dim, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(key: const Key('oldCode'), controller: code, textCapitalization: TextCapitalization.characters, maxLength: 9,
              style: const TextStyle(letterSpacing: 3, fontSize: 18), textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l.importCode, hintText: 'ABCD2345', counterText: '')),
          const SizedBox(height: 10),
          Btn(l.importBtn, key: const Key('importOld'), icon: Icons.download_outlined, onTap: busy ? null : _import),
          if (result != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(result!, key: const Key('importResult'), style: TextStyle(color: C.gold))),
        ])),
        Sec(title: l.whoWereYou, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.whoD, style: TextStyle(color: C.dim, fontSize: 12)),
          const SizedBox(height: 8),
          if (names != null && list.isEmpty) Text(l.noNames, key: const Key('noNames'), style: TextStyle(color: C.mute)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in list)
              ChoiceChip(key: Key('claim_${n['name']}'), label: Text(n['taken'] == true ? '${n['name']} · ${l.nameTaken}' : n['name'] as String),
                  selected: mine == n['name'], onSelected: n['taken'] == true ? null : (_) async {
                    try { await widget.account.claimOldName(n['name'] as String); await _names(); } catch (e) { if (context.mounted) toastErr(context, errText(l, e)); }
                  }),
          ]),
        ])),
      ]),
    );
  }
}

/// History → Old app: the imported games (read from the server), with the same kind of detail page.
class OldGamesTab extends StatefulWidget {
  const OldGamesTab({super.key, required this.account});
  final Account account;
  @override
  State<OldGamesTab> createState() => _OldGamesState();
}

class _OldGamesState extends State<OldGamesTab> {
  List<Map<String, Object?>>? games;
  @override
  void initState() { super.initState(); widget.account.oldGames().then((g) { if (mounted) setState(() => games = g); }).catchError((_) { if (mounted) setState(() => games = []); }); }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), g = games;
    if (g == null) return Center(child: CircularProgressIndicator(color: C.red2));
    if (g.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(l.noOldGames, key: const Key('noOldGames'), textAlign: TextAlign.center, style: TextStyle(color: C.mute))));
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final x in g)
        Card(color: C.card, child: ListTile(
          key: Key('old_${x['id']}'),
          leading: Icon(x['winner'] == 'mafia' ? Icons.dangerous_outlined : Icons.emoji_events_outlined, color: x['winner'] == 'mafia' ? C.red2 : C.gold),
          title: Text(x['winner'] == 'mafia' ? l.winMafia : l.winCitizens),
          subtitle: Text([
            if (x['seat'] != null) l.youPlayed(roleName(l, Role.values.byName((x['roles'] as List)[x['seat'] as int] as String))),
            l.rcSub((x['names'] as List).length, x['days'] as int),
            if (x['valid'] != true) l.invalid,
            if (x['status'] == 'waiting') l.oldWaiting, // S12-1
            if (x['status'] == 'test') l.oldTestGame,
          ].join(' · '), style: TextStyle(color: x['status'] == 'counted' || x['status'] == null ? C.mute : C.gold)),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _OldDetail(g: x))),
        )),
    ]);
  }
}

class _OldDetail extends StatelessWidget {
  const _OldDetail({required this.g});
  final Map<String, Object?> g;
  @override
  Widget build(BuildContext context) {
    final l = L.of(context), names = (g['names'] as List).cast<String>(), roles = (g['roles'] as List).cast<String>(), alive = (g['alive'] as List).cast<bool>();
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(g['winner'] == 'mafia' ? l.winMafia : l.winCitizens, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, children: [
        Sec(title: l.roles, child: Column(children: [
          for (var i = 0; i < names.length; i++)
            Row(children: [
              Icon(roleIcon(Role.values.byName(roles[i])), size: 18, color: roleColor(Role.values.byName(roles[i]))), const SizedBox(width: 8),
              Expanded(child: Text(names[i], style: TextStyle(decoration: alive[i] ? null : TextDecoration.lineThrough))),
              Text(roleName(l, Role.values.byName(roles[i]))),
            ]),
        ])),
        // the old app wrote these lines in the language it was set to at the time
        Sec(title: l.history, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final h in (g['hist'] as List).cast<String>()) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(h, style: TextStyle(color: C.mute))),
        ])),
      ]),
    );
  }
}

/// [S12-1] Settings → Old players (admin): every name found in the imported games, marked Real (with an optional
/// @username), Test, or Not sure. A game counts once all its names are Real; a Test name keeps it out.
class OldPlayersScreen extends StatefulWidget {
  const OldPlayersScreen({super.key, required this.account});
  final Account account;
  @override
  State<OldPlayersScreen> createState() => _OldPlayersState();
}

class _OldPlayersState extends State<OldPlayersScreen> {
  List<Map<String, Object?>>? players;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final p = await widget.account.oldPlayers(); if (mounted) setState(() => players = p); } catch (e) { if (mounted) setState(() => error = errText(L.of(context), e)); }
  }

  Future<void> _mark(Map<String, Object?> p, String mark, {String? link}) async {
    final l = L.of(context);
    try {
      final r = await widget.account.markOldPlayer(p['name'] as String, mark, link: link);
      if (mounted) setState(() { p['mark'] = r['mark']; p['link'] = r['link']; });
    } catch (e) { if (mounted) toastErr(context, errText(l, e)); }
  }

  Future<void> _link(Map<String, Object?> p) async {
    final l = L.of(context), c = TextEditingController(text: (p['link'] as String?) ?? '@');
    final h = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(p['name'] as String),
      content: TextField(key: const Key('opLinkField'), controller: c, autofocus: true, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: l.opLink)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
        TextButton(key: const Key('opLinkSave'), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(l.save)),
      ],
    ));
    if (h != null && h.replaceAll('@', '').isNotEmpty) await _mark(p, 'real', link: h);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), ps = players;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.oldPlayersT, style: head.copyWith(fontSize: 20))),
      body: error != null ? Center(child: Text(error!, style: TextStyle(color: C.red2)))
          : ps == null ? Center(child: CircularProgressIndicator(color: C.red2))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(l.oldPlayersD, style: TextStyle(color: C.mute)),
              const SizedBox(height: 12),
              if (ps.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(l.opNone, key: const Key('opNone'), textAlign: TextAlign.center, style: TextStyle(color: C.mute))),
              for (final p in ps) Sec(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(p['name'] as String, key: Key('op_${p['name']}'), style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(l.opGames(p['games'] as int), style: TextStyle(color: C.dim, fontSize: 12)),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (final (m, t) in [('real', l.opReal), ('test', l.opTest), ('unknown', l.opUnknown)])
                    ChoiceChip(key: Key('op_${p['name']}_$m'), label: Text(t), selected: p['mark'] == m, onSelected: (_) => _mark(p, m)),
                  if (p['mark'] == 'real') TextButton.icon(key: Key('op_${p['name']}_link'), onPressed: () => _link(p),
                      icon: const Icon(Icons.link, size: 18), label: Text((p['link'] as String?) ?? l.opLink, textDirection: TextDirection.ltr)),
                ]),
              ])),
            ]),
    );
  }
}
