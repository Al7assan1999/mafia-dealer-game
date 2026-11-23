// How to play: the goal, the roles, night, day, tips (English + Arabic). Offered once on first launch.
import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart';

import 'intro.dart';
import 'l10n/app_localizations.dart';
import 'prefs.dart';
import 'ui.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, this.prefs});
  final Prefs? prefs; // for "Watch the intro" at the top

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    Widget part(String title, String body) => Sec(title: title, child: Text(body, style: const TextStyle(height: 1.45)));
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.howToPlay, style: head.copyWith(fontSize: 20))),
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
        part(l.gTipsT, l.gTips),
      ]),
    );
  }
}
