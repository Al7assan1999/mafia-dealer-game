// The setup: players, roles and rules. Limits and messages come from the engine (validateSetup), so the Deal button
// can never start a game the rules don't allow.
import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart';

import 'account.dart';
import 'audio.dart';
import 'game.dart';
import 'l10n/app_localizations.dart';
import 'prefs.dart';
import 'ui.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.prefs, required this.audio, this.account, this.onDealt});
  final Prefs prefs;
  final Audio audio;
  final Account? account; // signed in: the chips and the last setup come from the account (decision 2)
  final void Function(OfflineGame)? onDealt; // default: the screen closes with the new game
  @override
  State<SetupScreen> createState() => _SetupState();
}

class _SetupState extends State<SetupScreen> {
  late final List<TextEditingController> names;
  late int mafia, detective;
  late Rules rules;

  @override
  void initState() {
    super.initState();
    final p = widget.prefs, saved = p.players;
    names = [for (final n in saved.isNotEmpty ? saved : List.filled(6, '')) TextEditingController(text: n)];
    final acc = _acc?.setup, s = p.setup, counts = acc?['counts'] as Map?;
    mafia = (counts?['mafia'] ?? s?['mafia']) as int? ?? 1;
    detective = (counts?['detective'] ?? s?['detective']) as int? ?? 1;
    try { rules = defaultRules.merge(Map<String, Object?>.from(((acc ?? s)?['rules'] as Map?) ?? {})); } catch (_) { rules = defaultRules; }
  }

  Account? get _acc => widget.account?.signedIn == true ? widget.account : null;
  List<String> get _roster => _acc?.names ?? widget.prefs.roster;

  @override
  void dispose() { for (final c in names) { c.dispose(); } super.dispose(); }

  /// Empty fields get "Player N" (the narrator knows those names).
  List<String> _names(L l) => [for (var i = 0; i < names.length; i++) names[i].text.trim().isEmpty ? l.playerN(i + 1) : names[i].text.trim()];

  String? _error(L l, SetupCheck v) => switch (v.error) {
        'tooFew' => l.eTooFew, 'tooManyPlayers' => l.eTooMany, 'tooManyRoles' => l.eTooManyRoles,
        'mafiaGap' => l.eMafiaGap(maxMafia(names.length)), 'badName' => l.eBadName, 'dupNames' => l.eDupNames, _ => null,
      };

  void _deal(L l, Counts counts) {
    final ns = _names(l), p = widget.prefs;
    p.players = [for (final c in names) c.text.trim()];
    final roster = [...ns.where((n) => !RegExp(r'^(Player|لاعب) \d+$').hasMatch(n)), ..._roster.where((r) => !ns.map(nameKey).contains(nameKey(r)))].take(30).toList();
    final saved = {'mafia': counts.mafia, 'detective': counts.detective, 'rules': rules.toJson()};
    if (_acc != null) {
      _acc!.saveNames(roster).catchError((_) {}); // offline: the next deal saves them
      _acc!.saveSetup(saved).catchError((_) {});
    } else {
      p.roster = roster;
    }
    p.setup = saved;
    final r = OfflineGame.start(p, widget.audio, Setup(ns, counts, rules));
    if (r.game == null) return;
    widget.onDealt != null ? widget.onDealt!(r.game!) : Navigator.of(context).pop(r.game);
  }

  void _rule(String k, Object v) => setState(() => rules = rules.merge({k: v}));

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), ns = _names(l), v = validateSetup(ns, Counts(mafia, 1, detective)), err = _error(l, v);
    final inList = ns.map(nameKey).toSet(), chips = _roster.where((r) => !inList.contains(nameKey(r))).toList();
    final preset = presetOf(rules);
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.newGame, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, bottom: [
        if (err != null) Text(err, key: const Key('setupError'), textAlign: TextAlign.center, style: const TextStyle(color: C.red2)),
        Btn(l.deal, key: const Key('deal'), icon: Icons.style_outlined, onTap: err == null ? () => _deal(l, v.counts) : null),
      ], children: [
        Sec(
          title: '${l.players} · ${names.length}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < names.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(color: C.dim))),
                  Expanded(
                    child: TextField(
                      key: Key('name$i'), controller: names[i], maxLength: maxName, onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(hintText: l.playerN(i + 1), counterText: ''),
                    ),
                  ),
                  IconButton(key: Key('remove$i'), tooltip: l.remove, icon: const Icon(Icons.close, color: C.dim),
                      onPressed: names.length <= 1 ? null : () => setState(() => names.removeAt(i).dispose())),
                ]),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(key: const Key('addPlayer'), onPressed: names.length >= maxPlayers ? null : () => setState(() => names.add(TextEditingController())),
                  child: Text(l.addPlayer, style: const TextStyle(color: C.red2))),
            ),
            if (chips.isNotEmpty) ...[
              Text(l.saved, style: const TextStyle(color: C.mute, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in chips)
                  ActionChip(label: Text(c), onPressed: () => setState(() {
                        final empty = names.indexWhere((x) => x.text.trim().isEmpty);
                        if (empty >= 0) { names[empty].text = c; } else if (names.length < maxPlayers) { names.add(TextEditingController(text: c)); }
                      })),
              ]),
            ],
          ]),
        ),
        Sec(
          title: l.deck,
          child: Column(children: [
            _count(l.mafia, l.dMafia, Role.mafia, v.counts.mafia, v.counts.mafia > 1 ? () => setState(() => mafia = v.counts.mafia - 1) : null,
                deckOk(ns.length, v.counts.mafia + 1, v.counts.detective) ? () => setState(() => mafia = v.counts.mafia + 1) : null),
            _count(l.doctor, '${l.dDoctor} · ${l.docOne}', Role.doctor, 1, null, null),
            _count(l.detective, v.counts.mafia < 2 ? '${l.dDetective} · ${l.detNeed2}' : l.dDetective, Role.detective, v.counts.detective,
                v.counts.detective > 0 ? () => setState(() => detective = 0) : null,
                v.counts.detective == 0 && v.counts.mafia >= 2 && deckOk(ns.length, v.counts.mafia, 1) ? () => setState(() => detective = 1) : null),
            _count(l.citizen, l.dCitizen, Role.citizen, ns.length - v.counts.mafia - 1 - v.counts.detective, null, null),
            if (ns.length >= minPlayers) Text(l.recM(recMafia(ns.length)), style: const TextStyle(color: C.dim, fontSize: 12)),
          ]),
        ),
        Sec(
          title: l.rules,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, children: [
              for (final p in ['classic', 'beginner'])
                ChoiceChip(label: Text(p == 'classic' ? l.presetClassic : l.presetBeginner), selected: preset == p,
                    onSelected: (_) => setState(() => rules = rules.merge(presets[p]!))),
              if (preset == 'custom') ChoiceChip(label: Text(l.presetCustom), selected: true, onSelected: (_) {}),
            ]),
            _sw(l.rSkip, l.rSkipD, rules.skip, (x) => _rule('skip', x)),
            _sw(l.rNorep, l.rNorepD, rules.norep, (x) => _rule('norep', x)),
            _sw(l.rSaverev, l.rSaverevD, rules.saverev, (x) => _rule('saverev', x)),
            _sw(l.rDecoy, l.rDecoyD, rules.decoy, (x) => _rule('decoy', x)),
            _sw(l.rSelf, null, rules.self, (x) => _rule('self', x)),
            _sw(l.rRep, null, rules.rep, (x) => _rule('rep', x)),
            _sw(l.rReveal, null, rules.reveal, (x) => _rule('reveal', x)),
            _sw(l.rSkipVote, l.rSkipVoteD, rules.skipVote, (x) => _rule('skipVote', x)),
            _pickRow(l.rTimer, null, [60, 120, 180, 240, 300, 420, 600], rules.timer, (s) => l.minutes(s ~/ 60), (x) => _rule('timer', x)),
            _pickRow(l.rNightT, l.rNightTD, nightTimes, rules.nightT, (s) => s == 0 ? l.off : l.seconds(s), (x) => _rule('nightT', x)),
          ]),
        ),
      ]),
    );
  }

  Widget _count(String name, String desc, Role r, int n, VoidCallback? minus, VoidCallback? plus) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(roleIcon(r), color: roleColor(r)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(desc, style: const TextStyle(color: C.dim, fontSize: 12)),
          ])),
          if (r == Role.mafia || r == Role.detective) IconButton(key: Key('minus_${r.name}'), onPressed: minus, icon: const Icon(Icons.remove_circle_outline)),
          SizedBox(width: 24, child: Text('$n', key: Key('count_${r.name}'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          if (r == Role.mafia || r == Role.detective) IconButton(key: Key('plus_${r.name}'), onPressed: plus, icon: const Icon(Icons.add_circle_outline)),
        ]),
      );

  Widget _sw(String t, String? d, bool v, ValueChanged<bool> on) => SwitchListTile(
        contentPadding: EdgeInsets.zero, value: v, onChanged: on, title: Text(t, style: const TextStyle(fontSize: 14)),
        subtitle: d == null ? null : Text(d, style: const TextStyle(color: C.dim, fontSize: 12)),
      );

  Widget _pickRow(String t, String? d, List<int> opts, int v, String Function(int) label, ValueChanged<int> on) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 14)),
          if (d != null) Text(d, style: const TextStyle(color: C.dim, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in {...opts, v}.toList()..sort()) ChoiceChip(label: Text(label(o)), selected: o == v, onSelected: (_) => on(o)),
          ]),
        ]),
      );
}
