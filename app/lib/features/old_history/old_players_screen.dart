import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

/// [S12-1] Settings → Old players (admin): every name found in the imported games, marked Real (with an optional
/// @username), Test, or Not sure. A game counts once all its names are Real; a Test name keeps it out.
class OldPlayersScreen extends StatefulWidget {
  const OldPlayersScreen({super.key, required this.account});
  final Account account;
  @override
  State<OldPlayersScreen> createState() => _OldPlayersState();
}

class _OldPlayersState extends State<OldPlayersScreen> {
  List<Map<String, Object?>>? players;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final p = await widget.account.oldPlayers(); if (mounted) setState(() => players = p); } catch (e) { if (mounted) setState(() => error = errText(L.of(context), e)); }
  }

  Future<void> _mark(Map<String, Object?> p, String mark, {String? link}) async {
    final l = L.of(context);
    try {
      final r = await widget.account.markOldPlayer(p['name'] as String, mark, link: link);
      if (mounted) setState(() { p['mark'] = r['mark']; p['link'] = r['link']; });
    } catch (e) { if (mounted) toastErr(context, errText(l, e)); }
  }

  Future<void> _link(Map<String, Object?> p) async {
    final l = L.of(context), c = TextEditingController(text: (p['link'] as String?) ?? '@');
    final h = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(p['name'] as String),
      content: TextField(key: const Key('opLinkField'), controller: c, autofocus: true, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: l.opLink)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
        TextButton(key: const Key('opLinkSave'), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(l.save)),
      ],
    ));
    if (h != null && h.replaceAll('@', '').isNotEmpty) await _mark(p, 'real', link: h);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), ps = players;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.oldPlayersT, style: head.copyWith(fontSize: 20))),
      body: error != null ? Center(child: Text(error!, style: TextStyle(color: C.red2)))
          : ps == null ? Center(child: CircularProgressIndicator(color: C.red2))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(l.oldPlayersD, style: TextStyle(color: C.mute)),
              const SizedBox(height: 12),
              if (ps.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(l.opNone, key: const Key('opNone'), textAlign: TextAlign.center, style: TextStyle(color: C.mute))),
              for (final p in ps) Sec(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(p['name'] as String, key: Key('op_${p['name']}'), style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(l.opGames(p['games'] as int), style: TextStyle(color: C.dim, fontSize: 12)),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (final (m, t) in [('real', l.opReal), ('test', l.opTest), ('unknown', l.opUnknown)])
                    ChoiceChip(key: Key('op_${p['name']}_$m'), label: Text(t), selected: p['mark'] == m, onSelected: (_) => _mark(p, m)),
                  if (p['mark'] == 'real') TextButton.icon(key: Key('op_${p['name']}_link'), onPressed: () => _link(p),
                      icon: const Icon(Icons.link, size: 18), label: Text((p['link'] as String?) ?? l.opLink, textDirection: TextDirection.ltr)),
                ]),
              ])),
            ]),
    );
  }
}
