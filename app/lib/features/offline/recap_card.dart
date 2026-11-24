// [S15-4] The end of a game as the old app's recap card ("case file" in Noir: paper with a hard red shadow; Neon: a
// card with a gold or red glow): the brand and the date, who won, the player of the game, every player's role in two
// columns (the dead crossed out), and what happened. Offline and online.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:mafia_engine/mafia_engine.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

class RecapCard extends StatelessWidget {
  const RecapCard({super.key, required this.mafia, required this.days, required this.players, this.best, this.lines = const []});
  final bool mafia;
  final int days;
  final List<({String name, Role role, bool alive})> players;
  final ({String name, String why, Role role})? best;
  final List<({bool night, String text})> lines;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), noir = !C.neon;
    final ink = noir ? C.altText : C.text, soft = noir ? const Color(0xFF5A5248) : C.mute, rule = noir ? const Color(0xFF9A8F7C) : C.line2;
    final win = noir ? C.red : mafia ? C.red2 : C.gold;
    return Container(
      key: const Key('recap'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: noir ? C.alt : C.card,
        gradient: noir ? null : RadialGradient(center: const Alignment(0, -1), radius: 1.2,
            colors: [Color.alphaBlend((mafia ? C.red2 : C.gold).withValues(alpha: mafia ? .26 : .22), C.card), C.card], stops: const [0, .7]),
        border: noir ? null : Border.all(color: C.line2),
        borderRadius: BorderRadius.circular(noir ? 4 : 28),
        boxShadow: noir ? [BoxShadow(color: C.red, offset: const Offset(4, 4))] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 22, height: 22, alignment: Alignment.center,
              decoration: BoxDecoration(color: noir ? C.red : null, gradient: noir ? null : const LinearGradient(colors: [Color(0xFFFF2E63), Color(0xFFFF8A3D)]),
                  borderRadius: BorderRadius.circular(noir ? 2 : 7)),
              child: const HatMark(size: 14, color: Colors.white)),
          const SizedBox(width: 6),
          Text('Mafia Dealer', style: head.copyWith(fontSize: 13.5, color: ink)),
          const Spacer(),
          Text(_date(DateTime.now(), Localizations.localeOf(context).languageCode), style: TextStyle(fontSize: 12, color: soft)),
        ]),
        const SizedBox(height: 14),
        Center(child: Container(width: 76, height: 76, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: noir ? rule : win.withValues(alpha: .5), width: 2)),
            child: Icon(mafia ? Icons.dangerous_outlined : Icons.emoji_events_outlined, size: 38, color: win))),
        const SizedBox(height: 10),
        Text(mafia ? l.winMafia : l.winCitizens, key: const Key('winner'), textAlign: TextAlign.center, style: head.copyWith(fontSize: 34, color: win, height: 1.15)),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.rcSub(players.length, days), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: soft))),
        if (best case final b?) Container(
          margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: noir ? const Color(0x10000000) : C.gold.withValues(alpha: .12),
              border: Border.all(color: noir ? rule : C.gold.withValues(alpha: .35)), borderRadius: BorderRadius.circular(noir ? 3 : 16)),
          child: Row(children: [
            Icon(Icons.workspace_premium_outlined, size: 26, color: noir ? C.red : C.gold),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.mvpT.toUpperCase(), style: capStyle.copyWith(fontSize: 12, color: soft)),
              Text(b.name, key: const Key('mvpName'), style: head.copyWith(fontSize: 21, color: ink)),
              Text(b.why, style: TextStyle(fontSize: 12.5, color: soft)),
            ])),
            Text(roleName(l, b.role), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _rc(b.role))),
          ]),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) => Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in players) Container(
            width: (box.maxWidth - 6) / 2, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: _rc(p.role).withValues(alpha: .12), borderRadius: BorderRadius.circular(noir ? 2 : 12),
                border: BorderDirectional(start: BorderSide(color: _rc(p.role), width: 3))),
            child: Row(children: [
              Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
                  color: p.alive ? ink : ink.withValues(alpha: .6), decoration: p.alive ? null : TextDecoration.lineThrough))),
              Text(roleName(l, p.role), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _rc(p.role))),
            ]),
          ),
        ])),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(height: 1, color: rule),
          const SizedBox(height: 8),
          for (final x in lines) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(x.night ? Icons.nightlight_outlined : Icons.wb_sunny_outlined, size: 15, color: soft),
            const SizedBox(width: 8),
            Expanded(child: Text(x.text, style: TextStyle(fontSize: 13, height: 1.45, color: noir ? const Color(0xFF3D362D) : C.mute))),
          ])),
        ],
      ]),
    );
  }

  // the role's colour on paper (the citizen's gold is too light on Noir's paper)
  static Color _rc(Role r) => !C.neon && r == Role.citizen ? const Color(0xFFB0873A) : roleColor(r);
}

/// [S15] "24 Nov 2026"; the numbers stay 0-9 in Arabic, as everywhere else in the app (as the bell)
String _date(DateTime d, String lang) => '${d.day} ${DateFormat.MMM(lang).format(d)} ${d.year}';
