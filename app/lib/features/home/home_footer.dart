// [S13-5 / his note 11] Home's footer, as the old app: "v0.4.3 · Check for updates · What's new". What's new shows this
// version's notes at any time (they used to show once after an update and then were gone).
import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/features/update/updater.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

class HomeFooter extends StatelessWidget {
  const HomeFooter({super.key, required this.updater});
  final Updater updater;

  Future<void> _check(BuildContext context) async {
    final l = L.of(context);
    final ok = await updater.check(force: true);
    if (context.mounted && updater.latest == null) toast(context, ok ? l.sUpToDate : l.sCheckFailed); // a newer one shows its card above
  }

  Future<void> _whatsNew(BuildContext context) async {
    final l = L.of(context), notes = await updater.whatsNew();
    if (!context.mounted) return;
    notes.isEmpty ? toast(context, l.noNotes) : notesSheet(context, l.updWhatsNew(appVersion), notes);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), dim = TextStyle(color: C.dim, fontSize: 12);
    return Padding(padding: const EdgeInsets.only(top: 22), child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('v$appVersion', key: const Key('homeVersion'), style: dim),
      Text('  ·  ', style: dim),
      InkWell(key: const Key('homeCheck'), onTap: () => _check(context), child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(l.sCheck, style: dim))),
      Text('  ·  ', style: dim),
      InkWell(key: const Key('whatsNew'), onTap: () => _whatsNew(context),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(l.whatsNew, style: TextStyle(color: C.gold, fontSize: 12, fontWeight: FontWeight.w700)))),
    ]));
  }
}
