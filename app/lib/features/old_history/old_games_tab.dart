import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart' show Role;
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

/// An old app game, opened from History → Online (1.2.1: the Old tab is gone, its games are listed with Online).
class OldDetail extends StatelessWidget {
  const OldDetail({super.key, required this.g});
  final Map<String, Object?> g;
  @override
  Widget build(BuildContext context) {
    final l = L.of(context), names = (g['names'] as List).cast<String>(), roles = (g['roles'] as List).cast<String>(), alive = (g['alive'] as List).cast<bool>();
    return Scaffold(
      appBar: AppBar(title: Text(g['winner'] == 'mafia' ? l.winMafia : l.winCitizens, style: head.copyWith(fontSize: 20))),
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
