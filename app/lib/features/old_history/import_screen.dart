import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

/// Profile → Import old history (S8-3).
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.account});
  final Account account;
  @override
  State<ImportScreen> createState() => _ImportState();
}

class _ImportState extends State<ImportScreen> {
  final code = TextEditingController();
  String? result;
  bool busy = false;


  Future<void> _import() async {
    final l = L.of(context);
    setState(() { busy = true; result = null; });
    try {
      final r = await widget.account.importOld(code.text);
      // [S12-1] every game is kept; say what waits for names and what couldn't be read
      final waiting = r['waiting'] as int? ?? 0, broken = r['broken'] as int? ?? 0;
      final line = [l.importFound(r['found'] as int? ?? 0, r['imported'] as int, r['duplicates'] as int),
        if (waiting > 0) l.importWaiting(waiting), if (broken > 0) l.importBroken(broken)].join(' ');
      if (mounted) setState(() => result = line);
    } catch (e) {
      if (mounted) setState(() => result = e is ApiError && e.code == 'not_found' ? l.importNotFound : e is ApiError && e.code == 'busy' ? l.importDown : errText(l, e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() { code.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.importT, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, children: [
        Sec(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.importD, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final s in [l.importS1, l.importS2]) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(s, style: TextStyle(color: C.mute))),
          const SizedBox(height: 6),
          Text(l.importS3, style: TextStyle(color: C.dim, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(key: const Key('oldCode'), controller: code, textCapitalization: TextCapitalization.characters, maxLength: 9,
              style: const TextStyle(letterSpacing: 3, fontSize: 18), textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l.importCode, hintText: 'ABCD2345', counterText: '')),
          const SizedBox(height: 10),
          Btn(l.importBtn, key: const Key('importOld'), icon: Icons.download_outlined, onTap: busy ? null : _import),
          if (result != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(result!, key: const Key('importResult'), style: TextStyle(color: C.gold))),
        ])),
      ]),
    );
  }
}

/// History → Old app: the imported games (read from the server), with the same kind of detail page.
