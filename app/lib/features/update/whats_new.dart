// [S14-4 / his #3] What's new and the update card, as the old app's: the card shows "What's new in vX", its first three
// points, See all and Update; What's new lists every recent release (date, points, Available / Installed), Update · vX
// and OK. It opens by itself once after an update.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/features/update/updater.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

Widget _dot(String n) => Padding(padding: const EdgeInsets.only(top: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsetsDirectional.only(top: 7, end: 14), child: Container(width: 6, height: 6, decoration: BoxDecoration(color: C.gold, shape: BoxShape.circle))),
      Expanded(child: Text(n, style: TextStyle(color: C.mute, fontSize: 15, height: 1.4))),
    ]));

class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key, required this.updater});
  final Updater updater;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: updater, builder: (context, _) {
        final r = updater.latest, l = L.of(context);
        if (r == null) return const SizedBox.shrink();
        final busy = updater.state == 'downloading' || updater.state == 'installing';
        return Container(key: const Key('updateCard'), margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: C.card2, border: Border.all(color: C.gold.withValues(alpha: .45)), borderRadius: BorderRadius.circular(C.neon ? 18 : 3)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.updWhatsNew('v${r.version}'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: C.text)),
            for (final n in r.notes.take(3)) _dot(n),
            const SizedBox(height: 12),
            if (updater.state == 'downloading') ...[
              LinearProgressIndicator(value: updater.progress, color: C.red, backgroundColor: C.card),
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.updDownloading((updater.progress * 100).round()), key: const Key('updProgress'), style: TextStyle(color: C.mute))),
            ] else if (updater.state == 'installing')
              Text(l.updInstalling, style: TextStyle(color: C.mute))
            else ...[
              if (updater.state == 'allow') Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l.updAllow, key: const Key('updAllow'), style: TextStyle(color: C.mute))),
              if (updater.state == 'failed') Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l.updFailed, style: TextStyle(color: C.red2))),
              Row(children: [
                TextButton(key: const Key('updSeeAll'), onPressed: () => whatsNewSheet(context, updater), child: Text(l.seeAll, style: TextStyle(color: C.gold, fontSize: 15))),
                const Spacer(),
                SizedBox(width: 150, child: Btn(l.updBtn, key: const Key('updBtn'), onTap: busy ? null : updater.update)),
              ]),
            ],
          ]),
        );
      });
}

/// What's new: every recent release; [fallback] (this version's kept points) when nothing answered.
Future<void> whatsNewSheet(BuildContext context, Updater u, {List<String> fallback = const []}) async {
  final l = L.of(context), list = await u.releases();
  if (!context.mounted) return;
  final rels = list.isNotEmpty ? list : [if (fallback.isNotEmpty) ReleaseNote(appVersion, appBuild, null, fallback)];
  if (rels.isEmpty) { toast(context, l.noNotes); return; }
  final newer = u.latest, loc = Localizations.localeOf(context).languageCode;
  String day(DateTime d) => DateFormat('d MMM y', loc).format(d); // "20 Nov 2026", as the old app
  await showDialog(context: context, builder: (ctx) => Dialog(
    key: const Key('whatsNewSheet'), backgroundColor: C.card, insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
    shape: RoundedRectangleBorder(side: BorderSide(color: C.line), borderRadius: BorderRadius.circular(C.neon ? 22 : 6)),
    child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l.whatsNew, style: head.copyWith(fontSize: 22)),
      const SizedBox(height: 8),
      Flexible(child: ListView.separated(shrinkWrap: true, itemCount: rels.length, separatorBuilder: (_, _) => Divider(height: 28, color: C.line), itemBuilder: (_, i) {
        final r = rels[i], mine = r.build == appBuild || (appBuild == 0 && r.version == appVersion), avail = !mine && r.build > appBuild && appBuild != 0;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('v${r.version}', textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: C.text)),
            if (avail || mine) Container(margin: const EdgeInsetsDirectional.only(start: 10), padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: avail ? C.red : C.green.withValues(alpha: .16), borderRadius: BorderRadius.circular(C.neon ? 8 : 2)),
                child: Text(avail ? l.relAvailable : l.relInstalled, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: avail ? C.priText : C.green))),
            const Spacer(),
            if (r.date != null) Text(day(r.date!), style: TextStyle(color: C.mute, fontSize: 13.5, locale: Locale(loc))),
          ]),
          for (final n in r.notes) _dot(n),
        ]);
      })),
      const SizedBox(height: 16),
      if (newer != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Btn('${l.updBtn} · v${newer.version}', key: const Key('whatsNewUpdate'),
          onTap: () { Navigator.of(ctx).pop(); u.update(); })),
      Btn(l.ok, key: const Key('notesOk'), ghost: true, onTap: () => Navigator.of(ctx).pop()),
    ])),
  ));
}
