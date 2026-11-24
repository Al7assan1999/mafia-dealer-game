// [S14-3 / his #3] Home's trophy line as the old app: "Best player: Dareer · 83%", under the three tiles. From the one
// board (signed in), read once per start and kept, with the Game History count. [BA P2] a tap opens Player Stats.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/stats/stats_screen.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/state/account.dart';

class BestLine extends StatefulWidget {
  const BestLine({super.key, required this.account, required this.prefs});
  final Account account;
  final Prefs prefs;
  static bool read = false; // once per run
  @override
  State<BestLine> createState() => _BestLineState();
}

class _BestLineState extends State<BestLine> {
  @override
  void initState() {
    super.initState();
    if (!BestLine.read && widget.account.signedIn) { BestLine.read = true; _read(); }
  }

  Future<void> _read() async {
    final a = widget.account, p = widget.prefs;
    try {
      final titles = (await a.stats())['titles'], best = titles is Map ? titles['best'] : null;
      p.homeBest = best is Map ? jsonEncode({'n': best['name'], 'r': best['r']}) : '';
      p.homeGames = (await a.games()).length;
    } catch (_) {} // offline: the kept line stays
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), raw = widget.prefs.homeBest;
    if (!widget.account.signedIn || raw.isEmpty) return const SizedBox(height: 4);
    final b = jsonDecode(raw) as Map;
    return Padding(padding: const EdgeInsets.only(top: 18), child: InkWell(key: const Key('bestLine'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatsScreen(account: widget.account))),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.emoji_events_outlined, color: C.gold, size: 20),
          const SizedBox(width: 10),
          Flexible(child: Text('${l.bestNow(b['n'] as String)} · ${((b['r'] as num) * 100).round()}%',
              style: TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 14.5))),
        ]))));
  }
}
