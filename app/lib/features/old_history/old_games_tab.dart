import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart' show Role;
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

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
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OldDetail(g: x))),
        )),
    ]);
  }
}

class OldDetail extends StatelessWidget {
  const OldDetail({super.key, required this.g});
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
