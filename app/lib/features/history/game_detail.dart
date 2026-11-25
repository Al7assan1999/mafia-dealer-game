import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/stats/player_screen.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

class GameDetail extends StatefulWidget {
  const GameDetail({super.key, required this.account, required this.id, this.local, this.prefs});
  final Prefs? prefs; // [S13 P1] hiding the game from my history (online games)
  final Account account;
  final String id;
  final Map<String, Object?>? local; // a Wi-Fi game from this phone (no server)
  @override
  State<GameDetail> createState() => _GameDetailState();
}

class _GameDetailState extends State<GameDetail> {
  /// The player of the game, from the saved stats (as on the end screen).
  static ({int seat, String why, int? n})? _mvp(Map<String, Object?> game) {
    final st = game['stats'] as Map?, ps = (game['players'] as List).cast<Map>();
    if (st == null || game['winner'] == null) return null;
    final stats = Stats(first: st['first'] as int?, kills: ((st['kills'] as List?) ?? []).cast<int>(), outs: ((st['outs'] as List?) ?? []).cast<int>(),
        saves: ((st['saves'] as List?) ?? []).cast<int>(), caught: [for (final p in ((st['caught'] as List?) ?? [])) ((p as List)[0] as int, p[1] as int)],
        guards: [for (final p in ((st['guards'] as List?) ?? [])) ((p as List)[0] as int, p[1] as int)]);
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
    if (game == null) return Scaffold(appBar: AppBar(), body: Center(child: CircularProgressIndicator(color: C.red2)));
    final ps = (game['players'] as List).cast<Map>(), name = {for (final p in ps) p['seat'] as int: p['name'] as String};
    String line(Map e) => switch (e['t']) {
          'night' => l.hNight(e['day'] as int) + switch ((e['mafia'] as Map)['k']) {
              'kill' => l.hKill(name[(e['mafia'] as Map)['seat']] ?? '?'), 'saved' => l.hSaved(name[(e['mafia'] as Map)['seat']] ?? '?'),
              'skip' => l.hSkip, _ => l.hNoMafia } + (e['shot'] is int ? l.hShot(name[e['shot']] ?? '?') : '') +
              // [S18 P2] whom the Bodyguard guarded
              [for (final q in (e['guard'] as List? ?? const [])) l.hGuard(name[q] ?? '?')].join(),
          'day' => l.hDay(e['day'] as int) + (e['out'] != null ? l.hOut(name[e['out']] ?? '?') : l.hNone),
          'removed' => l.hRemoved(name[e['seat']] ?? '?'),
          _ => '',
        };
    final sheikh = (game['sheikh'] ?? (game['record'] as Map?)?['sheikh']) as int?;
    return Scaffold(
      appBar: AppBar(title: Text(winText(l, game['winner']), style: head.copyWith(fontSize: 20)), actions: [
        if (widget.prefs case final p?) ListenableBuilder(listenable: p, builder: (context, _) {
          final hidden = p.hiddenGames.contains(widget.id);
          return IconButton(key: const Key('hideGame'), tooltip: hidden ? l.unhideGame : l.hideGame,
              icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: C.mute),
              onPressed: () { p.hideGame(widget.id, !hidden); toast(context, hidden ? l.unhiddenToast : l.hiddenToast); });
        }),
      ]),
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
              Text(mvpWhy(l, best.why, best.n), style: TextStyle(color: C.mute)),
            ])),
          ])),
        Sec(title: l.roles, child: Column(children: [
          for (final p in ps)
            InkWell(
              key: Key('player_${p['seat']}'),
              // every player's profile, from the one board (S13-1)
              onTap: widget.account.signedIn ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(account: widget.account,
                  playerKey: p['userId'] != null ? 'u:${p['userId']}' : 'n:${p['name']}'))) : null,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
                Icon(roleIcon(Role.values.byName(p['role'] as String)), size: 18, color: roleColor(Role.values.byName(p['role'] as String))), const SizedBox(width: 8),
                Expanded(child: Text(p['name'] as String, style: TextStyle(decoration: p['alive'] == true ? null : TextDecoration.lineThrough))),
                Text(seatRole(l, Role.values.byName(p['role'] as String), p['seat'] == sheikh)),
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
