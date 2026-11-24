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
  String? error;
  Map<String, Map<String, Object?>> server = {}; // the server's Wi-Fi requests and approved games, by the game's key
  String show = 'all'; // [S13 P1] all | valid | invalid | hidden

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
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameDetail(account: widget.account, id: '', local: d))),
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
    final hidden = widget.prefs.hiddenGames;
    // [S13 P1] the old app's filter, and the games I hid (shown again under "Hidden")
    final shown = (games ?? const <Map<String, Object?>>[]).where((g) => switch (show) {
          'hidden' => hidden.contains(g['id']),
          'valid' => g['valid'] == true && !hidden.contains(g['id']),
          'invalid' => g['valid'] != true && !hidden.contains(g['id']),
          _ => !hidden.contains(g['id']),
        }).toList();
    return error != null ? Center(child: Text(error!, style: TextStyle(color: C.red2)))
          : games == null ? Center(child: CircularProgressIndicator(color: C.red2))
          : games!.isEmpty ? Center(child: Text(l.noHistory, style: TextStyle(color: C.mute)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (k, t) in [('all', l.fAll), ('valid', l.valid), ('invalid', l.invalid), if (hidden.isNotEmpty) ('hidden', l.hiddenN(hidden.length))])
                  ChoiceChip(key: Key('hist_$k'), label: Text(t), selected: show == k, onSelected: (_) => setState(() => show = k)),
              ]),
              const SizedBox(height: 8),
              if (shown.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(l.noHistory, textAlign: TextAlign.center, style: TextStyle(color: C.mute))),
              for (final g in shown)
                Card(color: C.card, child: ListTile(
                  key: Key('game_${g['id']}'),
                  leading: Icon(g['winner'] == 'mafia' ? Icons.dangerous_outlined : Icons.emoji_events_outlined, color: g['winner'] == 'mafia' ? C.red2 : C.gold),
                  title: Text(g['winner'] == 'mafia' ? l.winMafia : l.winCitizens),
                  subtitle: Text('${l.youPlayed(roleName(l, Role.values.byName(g['role'] as String)))} · ${l.rcSub(g['players'] as int, g['days'] as int)}'
                      '${g['valid'] == true ? '' : ' · ${l.invalid}'}', style: TextStyle(color: C.mute)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameDetail(account: widget.account, id: g['id'] as String, prefs: widget.prefs))),
                )),
            ]);
  }
}

/// A kept Wi-Fi game's way into online history (S7-2): the button for the host, the guest line, or the request's
