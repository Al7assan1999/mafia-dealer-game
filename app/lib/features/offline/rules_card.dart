// [S13-2 / his note 13] The rules as a card, as in the old app: the preset and the rules in force as chips; a tap opens
// it in place, grouped Night / Day / Online (the old app's grouping); a tap on the header folds it again.
import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_engine/mafia_engine.dart';

class RulesEditor extends StatefulWidget {
  const RulesEditor({super.key, required this.rules, this.onChanged});
  final Rules rules;
  final ValueChanged<Rules>? onChanged; // null: read only (a player in someone's lobby)
  @override
  State<RulesEditor> createState() => _RulesState();
}

class _RulesState extends State<RulesEditor> {
  bool open = false;
  Rules get rules => widget.rules;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), preset = presetOf(rules), on = widget.onChanged;
    void rule(String k, Object v) => on?.call(rules.merge({k: v}));
    final chips = [
      if (rules.skip) l.cSkip, if (rules.norep) l.cNorep, if (rules.decoy) l.cDecoy, if (rules.self) l.cSelf, if (rules.rep) l.cRep,
      if (rules.saverev) l.cSaverev, if (rules.reveal) l.cReveal, if (rules.skipVote) l.cSkipVote,
      l.cTimer(l.minutes(rules.timer ~/ 60)), if (rules.nightT > 0) l.cNightT(rules.nightT),
    ];
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Material(
      key: const Key('rulesCard'), color: C.card,
      shape: RoundedRectangleBorder(side: BorderSide(color: C.line), borderRadius: BorderRadius.circular(C.p.radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(key: const Key('rulesToggle'), borderRadius: BorderRadius.circular(C.p.radius), onTap: () => setState(() => open = !open),
          child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(C.neon ? l.rules : l.rules.toUpperCase(), style: head.copyWith(fontSize: 14, color: C.mute, letterSpacing: C.neon ? 1 : 2))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: C.green.withValues(alpha: .15), borderRadius: BorderRadius.circular(C.neon ? 10 : 2)),
                  child: Text(switch (preset) { 'classic' => l.presetClassic, 'beginner' => l.presetBeginner, _ => l.presetCustom },
                      key: const Key('rulesPreset'), style: TextStyle(color: C.green, fontSize: 12, fontWeight: FontWeight.w700))),
              const SizedBox(width: 6),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: C.mute),
            ]),
            if (!open) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in chips) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: C.card2, border: Border.all(color: C.line2), borderRadius: BorderRadius.circular(C.neon ? 12 : 2)),
                  child: Text(c, style: TextStyle(color: C.text, fontSize: 12))),
            ])),
          ]))),
        if (open) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, children: [
            for (final p in ['classic', 'beginner'])
              ChoiceChip(key: Key('preset_$p'), label: Text(p == 'classic' ? l.presetClassic : l.presetBeginner), selected: preset == p,
                  onSelected: on == null ? null : (_) => on(rules.merge(presets[p]!))),
            if (preset == 'custom') ChoiceChip(label: Text(l.presetCustom), selected: true, onSelected: (_) {}),
          ]),
          _group(l.gNightT, Icons.nightlight_outlined),
          _sw(l.rSkip, l.rSkipD, rules.skip, on == null ? null : (x) => rule('skip', x)),
          _sw(l.rNorep, l.rNorepD, rules.norep, on == null ? null : (x) => rule('norep', x)),
          _sw(l.rDecoy, l.rDecoyD, rules.decoy, on == null ? null : (x) => rule('decoy', x)),
          _sw(l.rSelf, null, rules.self, on == null ? null : (x) => rule('self', x)),
          _sw(l.rRep, null, rules.rep, on == null ? null : (x) => rule('rep', x)),
          _group(l.gDayT, Icons.wb_sunny_outlined),
          _sw(l.rSaverev, l.rSaverevD, rules.saverev, on == null ? null : (x) => rule('saverev', x)),
          _sw(l.rReveal, null, rules.reveal, on == null ? null : (x) => rule('reveal', x)),
          _sw(l.rSkipVote, l.rSkipVoteD, rules.skipVote, on == null ? null : (x) => rule('skipVote', x)),
          _pickRow(l.rTimer, null, [60, 120, 180, 240, 300, 420, 600], rules.timer, (s) => l.minutes(s ~/ 60), on == null ? null : (x) => rule('timer', x)),
          _group(l.gOnlineT, Icons.public),
          _pickRow(l.rNightT, l.rNightTD, nightTimes, rules.nightT, (s) => s == 0 ? l.off : l.seconds(s), on == null ? null : (x) => rule('nightT', x)),
        ])),
      ]),
    ));
  }

  Widget _group(String t, IconData icon) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 2), child: Row(children: [
        Icon(icon, size: 16, color: C.gold), const SizedBox(width: 6),
        Text(t, style: head.copyWith(fontSize: 14, color: C.gold)),
      ]));

  Widget _sw(String t, String? d, bool v, ValueChanged<bool>? on) => SwitchListTile(
        contentPadding: EdgeInsets.zero, value: v, onChanged: on, title: Text(t, style: const TextStyle(fontSize: 14)),
        subtitle: d == null ? null : Text(d, style: TextStyle(color: C.dim, fontSize: 12)),
      );

  Widget _pickRow(String t, String? d, List<int> opts, int v, String Function(int) label, ValueChanged<int>? on) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 14)),
          if (d != null) Text(d, style: TextStyle(color: C.dim, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in {...opts, v}.toList()..sort())
              ChoiceChip(label: Text(label(o)), selected: o == v, onSelected: on == null ? null : (_) => on(o)),
          ]),
        ]),
      );
}
