import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/history/game_detail.dart';
import 'package:mafia_dealer/features/history/wifi_approval.dart';
import 'package:mafia_dealer/features/old_history/old_games_tab.dart';
import 'package:mafia_dealer/features/stats/stats_screen.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

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
  List<Map<String, Object?>> old = []; // [1.2.1] the old app's games I played, listed with Online
  bool oldFailed = false;
  String? error;
  Map<String, Map<String, Object?>> server = {}; // the server's Wi-Fi requests and approved games, by the game's key
  String show = 'all'; // [S13 P1] all | valid | invalid | hidden
  String winner = 'all', q = ''; // [S15-5] the old app's Winner filter and player search

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (!widget.account.signedIn) return;
    widget.account.wifiRequests().then((w) { if (mounted) setState(() => server = {for (final x in w) x['key'] as String: x}); }).catchError((_) {});
    // [1.2.1 hotfix] his note: every old player is linked, so the old app's games I played are listed with Online.
    // [Quin Q4] they come in after the online games, and a failure says so (with a retry) instead of hiding them
    _loadOld();
    try { final g = await widget.account.games(); if (mounted) setState(() => games = g); } catch (e) { if (mounted) setState(() => error = errText(L.of(context), e)); }
  }
  void _loadOld() {
    widget.account.oldGames().then((o) {
      final mine = [for (final x in o) if (x['seat'] is int) {
        'id': x['id'], 'winner': winnerIn(x), 'days': x['days'], 'valid': x['valid'], 'playedAt': x['playedAt'], 'names': x['names'],
        'role': (x['roles'] as List)[x['seat'] as int], 'players': (x['names'] as List).length, 'old': x}];
      if (mounted) setState(() { oldFailed = false; old = mine; });
    })
      .catchError((_) { if (mounted) setState(() => oldFailed = true); });
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
      return Scaffold(appBar: AppBar(title: title), body: Column(children: [
        Expanded(child: _wifi(l, wifi)),
        Padding(padding: const EdgeInsets.all(16), child: Text(l.historySignIn, key: const Key('historySignIn'), textAlign: TextAlign.center, style: TextStyle(color: C.dim))),
      ]));
    }
    return DefaultTabController(length: 2, child: Scaffold(
      appBar: AppBar(title: title, actions: [
            IconButton(key: const Key('openStats'), tooltip: l.statsT, icon: Icon(Icons.leaderboard_outlined, color: C.mute),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatsScreen(account: widget.account)))),
          ],
          bottom: TabBar(indicatorColor: C.red, labelColor: C.text, unselectedLabelColor: C.mute,
              tabs: [Tab(key: const Key('tabOnline'), text: l.tabOnline), Tab(key: const Key('tabWifi'), text: l.tabWifi)])),
      body: TabBarView(children: [_online(l), _wifi(l, wifi)]),
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
                leading: Icon(winIcon(d['winner']), color: winColor(d['winner'])),
                title: Text(winText(l, d['winner'])),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([
                    if (d['mine'] != null) l.youPlayed(roleName(l, roleOf(d['mine']) ?? Role.citizen)),
                    l.rcSub((d['players'] as List).length, d['days'] as int),
                  ].join(' · '), style: TextStyle(color: C.mute)),
                  WifiApproval(account: widget.account, prefs: widget.prefs, gameKey: g['id'] as String, server: server[g['id']], game: g, compact: true),
                ]),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameDetail(account: widget.account, id: '', local: d))),
              )),
        ]);

  /// A saved Wi-Fi game in the online detail page's shape (replayed from its record; null if it doesn't replay).
  static Map<String, Object?>? _wifiGame(Map<String, Object?> g) {
    final r = replay(g['record']);
    if (r.error != null) return null;
    final s = r.state!, my = g['mySeat'] as int? ?? -1;
    return {
      'winner': s.winner?.name, 'days': s.day, 'valid': true, 'host': false, 'log': s.log.map((e) => e.toJson()).toList(), 'stats': {'first': s.stats.first, 'kills': s.stats.kills, 'outs': s.stats.outs, 'saves': s.stats.saves, 'caught': [for (final (d, m) in s.stats.caught) [d, m]],
        'guards': [for (final (b, q) in s.stats.guards) [b, q]], 'hunts': [for (final (h, q) in s.stats.hunts) [h, q]],
        if (s.stats.lovers != null) 'lovers': [s.stats.lovers!.$1, s.stats.lovers!.$2]}, 'sheikh': s.sheikh, 'framer': s.framer,
      'players': [for (var i = 0; i < s.names.length; i++) {'seat': i, 'name': s.names[i], 'role': s.roles[i].name, 'alive': s.alive[i]}],
      'mine': my >= 0 && my < s.roles.length ? s.roles[my].name : null,
    };
  }

  Widget _online(L l) {
    final hidden = widget.prefs.hiddenGames;
    // [S13 P1] the old app's filter, and the games I hid (shown again under "Hidden")
    final needle = q.trim().toLowerCase();
    final all = games == null ? null : ([...games!, ...old]..sort((a, b) => ((b['playedAt'] as int?) ?? 0).compareTo((a['playedAt'] as int?) ?? 0)));
    final shown = (all ?? const <Map<String, Object?>>[]).where((g) => switch (show) {
          'hidden' => hidden.contains(g['id']),
          'valid' => g['valid'] == true && !hidden.contains(g['id']),
          'invalid' => g['valid'] != true && !hidden.contains(g['id']),
          _ => !hidden.contains(g['id']),
        } && (winner == 'all' || g['winner'] == winner)
          && (needle.isEmpty || ((g['names'] as List?) ?? const []).any((n) => '$n'.toLowerCase().contains(needle)))).toList();
    Widget chips(List<(String, String)> opts, String on, ValueChanged<String> pick, String prefix) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, t) in opts) ChoiceChip(key: Key('$prefix$k'), label: Text(t), selected: on == k, onSelected: (_) => setState(() => pick(k))),
        ]);
    Widget cap(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text(t.toUpperCase(), style: capStyle));
    return error != null ? Center(child: Text(error!, style: TextStyle(color: C.red2)))
          : games == null ? Center(child: CircularProgressIndicator(color: C.red2))
          : all!.isEmpty && !oldFailed ? Center(child: Text(l.noHistory, style: TextStyle(color: C.mute)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (oldFailed) Row(key: const Key('oldFailed'), children: [
                Expanded(child: Text(l.oldGamesFailed, style: TextStyle(color: C.gold))),
                TextButton(key: const Key('oldRetry'), onPressed: _loadOld, child: Text(l.retry, style: TextStyle(color: C.text))),
              ]),
              // [S15-5] as the old app: search by a player's name, Winner, Record, then how many games
              TextField(key: const Key('histSearch'), onChanged: (v) => setState(() => q = v), decoration: InputDecoration(hintText: l.searchName, prefixIcon: Icon(Icons.search, color: C.dim))),
              cap(l.fWinner),
              chips([('all', l.fAll), ('mafia', l.mafiaWon), ('citizens', l.citizensWon)], winner, (k) => winner = k, 'win_'),
              cap(l.fRecord),
              chips([('all', l.fAll), ('valid', l.valid), ('invalid', l.invalid), if (hidden.isNotEmpty) ('hidden', l.hiddenN(hidden.length))], show, (k) => show = k, 'hist_'),
              cap(l.nGames(shown.length)),
              if (shown.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(l.noHistory, textAlign: TextAlign.center, style: TextStyle(color: C.mute))),
              for (final g in shown)
                Card(color: C.card, child: ListTile(
                  key: Key('game_${g['id']}'),
                  leading: Icon(winIcon(winnerIn(g)), color: winColor(winnerIn(g))),
                  title: Text(winText(l, winnerIn(g))),
                  subtitle: Text('${l.youPlayed(roleName(l, roleIn(g)))} · ${l.rcSub(g['players'] as int, g['days'] as int)}'
                      '${g['valid'] == true ? '' : ' · ${l.invalid}'}${g['old'] is Map ? ' · ${l.tabOld}${switch ((g['old'] as Map)['status']) { 'waiting' => ' · ${l.oldWaiting}', 'test' => ' · ${l.oldTestGame}', _ => '' }}' : ''}', style: TextStyle(color: C.mute)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => g['old'] is Map ? OldDetail(g: Map<String, Object?>.from(g['old'] as Map))
                      : GameDetail(account: widget.account, id: g['id'] as String, prefs: widget.prefs))),
                )),
            ]);
  }
}

/// A kept Wi-Fi game's way into online history (S7-2): the button for the host, the guest line, or the request's
