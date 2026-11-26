import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/stats/player_screen.dart';
import 'package:mafia_dealer/features/stats/stats_common.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

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
      final d = await widget.account.stats(source: f.source, days: f.days);
      if (mounted && identical(want, f)) setState(() => data = d);
    } catch (e) { if (mounted) setState(() => error = errText(L.of(context), e)); }
  }
  void _set(StatsFilter n) { f = n; _load(); }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), d = data;
    return Scaffold(
      appBar: AppBar(title: Text(l.statsT, style: head.copyWith(fontSize: 20))),
      body: Column(children: [
        // [QA] S8 #4: the period chips sat off-screen in one scrolling row; two rows that wrap
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, t) in [('all', l.fAll), ('online', l.tabOnline), ('wifi', l.tabWifi)] /* [1.2.1] the old app's games are in Online */)
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
    final note = l.boardOne(min); // S13-1
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
          Text(label.toUpperCase(), style: capStyle.copyWith(fontSize: 11.5)),
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
      pairs([for (final w in small) if (w is! SizedBox) w]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Text(l.boardT.toUpperCase(), style: capStyle)),
        if (me != null && me['rank'] != null) Text(l.youRank(me['rank'] as int), key: const Key('myRank'), style: TextStyle(color: C.gold)),
      ]),
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(note, key: const Key('boardNote'), style: TextStyle(color: C.dim, fontSize: 12, height: 1.4))),
      for (final p in board) _row(l, p, min),
      if (me != null && !board.any((p) => p['me'] == true)) ...[Divider(color: C.line), _row(l, me, min)],
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
            Text(q ? pct(p['w'] as int, p['g'] as int) : l.needN(min), style: TextStyle(color: q ? C.text : C.dim, fontWeight: FontWeight.w700, fontSize: q ? 16 : 12)),
            Text(l.winsShort(p['w'] as int, p['g'] as int), style: TextStyle(color: C.dim, fontSize: 12)),
          ]),
        ])),
      ),
    );
  }

  void _open(Map p) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(account: widget.account, playerKey: p['key'] as String)));  // [1.2.1] the same profile from everywhere
}

/// A player's profile (S8-2): the old app's, plus the best partner and a card to share.
