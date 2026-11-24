import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mafia_engine/mafia_engine.dart' show Role;
import 'package:share_plus/share_plus.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/avatar.dart';
import 'package:mafia_dealer/features/friends/friends_screen.dart';
import 'package:mafia_dealer/features/stats/stats_common.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/state/models.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

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
    widget.account.player(widget.playerKey, source: f.source, days: f.days)
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
      appBar: AppBar(title: Text(x?['name'] as String? ?? widget.person?.display ?? '', style: head.copyWith(fontSize: 20)), actions: [
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
            Text(k.toUpperCase(), style: capStyle.copyWith(fontSize: 11.5)),
            Text('–', style: head.copyWith(fontSize: 19, color: C.dim)),
            Text(l.winsShort(0, 0), style: TextStyle(color: C.dim, fontSize: 12)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (f != null) ..._header(l, f),
      const SizedBox(height: 18),
      tile(l.winRate),
      const SizedBox(height: 8),
      pairs([tile(l.bestRole), tile(l.asMafiaT), tile(l.asTownT)]),
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
            Text(k.toUpperCase(), style: capStyle.copyWith(fontSize: 11.5)),
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
      tile(l.winRate, pct(x['wins'] as int, x['games'] as int), l.winsShort(x['wins'] as int, x['games'] as int), color: C.gold),
      const SizedBox(height: 8),
      pairs([
        tile(l.bestRole, roleName(l, best), l.winsShort(br[1], br[0]), color: roleColor(best)),
        tile(l.asMafiaT, pct(mafia[1], mafia[0]), l.winsShort(mafia[1], mafia[0])),
        tile(l.asTownT, pct(side[1], side[0]), l.winsShort(side[1], side[0])),
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
