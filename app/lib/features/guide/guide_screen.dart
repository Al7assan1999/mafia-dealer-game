import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/intro/intro_screen.dart';
import 'package:mafia_dealer/features/offline/rules_card.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

// How to play: the goal, the roles, night, day, table rules, suggested setup, the game options, tips (English + Arabic). Offered once on first launch.

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, this.prefs});
  final Prefs? prefs; // for "Watch the intro" at the top

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    Widget part(String title, String body) => Sec(title: title, child: Text(body, style: const TextStyle(height: 1.45)));
    return Scaffold(
      appBar: AppBar(title: Text(l.howToPlay, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, bottom: [Btn(l.gotIt, key: const Key('guideDone'), onTap: () => Navigator.of(context).pop())], children: [
        if (prefs != null) Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const Key('guideIntro'),
            icon: Icon(Icons.play_circle_outline, color: C.red2), label: Text(l.sWatchIntro, style: TextStyle(color: C.red2)),
            onPressed: () => showIntro(context, prefs!))),
        part(l.gGoalT, l.gGoal),
        Sec(title: l.gRolesT, child: Column(children: [
          for (final (r, d) in [(Role.mafia, l.dMafia), (Role.doctor, l.dDoctor), (Role.detective, l.dDetective), (Role.citizen, l.dCitizen)])
            Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
              Icon(roleIcon(r), color: roleColor(r)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(roleName(l, r), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(d, style: TextStyle(color: C.mute)),
              ])),
            ])),
        ])),
        part(l.gNightT, l.gNight),
        part(l.gDayT, l.gDay),
        part(l.gTableT, l.gTable), // [S15] the old guide's table rules and suggested setup
        part(l.gSetupT, l.gSetup),
        // [BA P3, S15] the old guide's "Options in this app": the setup's own rules card, read only (one source of truth)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l.gOptions, key: const Key('guideOptions'), style: TextStyle(color: C.mute))),
        RulesEditor(rules: defaultRules),
        part(l.gTipsT, l.gTips),
      ]),
    );
  }
}
