import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/push.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/features/intro/intro_screen.dart';
import 'package:mafia_dealer/features/update/updater.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.prefs, this.updater, this.account});
  final Prefs prefs;
  final Updater? updater;
  final Account? account; // the test notification (P5)
  @override
  State<SettingsSheet> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsSheet> {
  Prefs get prefs => widget.prefs;
  Updater? get updater => widget.updater;
  String? _checked; // the answer to "Check for updates", shown in the sheet ([QA] S8 #7)

  Future<void> _storage(BuildContext context) async {
    final l = L.of(context), rows = await updater!.storage();
    if (!context.mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(l.storageT),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (name, mb) in rows) Row(children: [Expanded(child: Text(name)), Text('${mb.toStringAsFixed(1)} MB', key: Key('storage_$name'), textDirection: TextDirection.ltr)]),
        if (rows.isEmpty) Text(l.storageNone),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.close))],
    ));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: prefs,
        builder: (context, _) {
          final l = L.of(context);
          // [R2] the switch and link rows in the same text size as the other rows (they were a size bigger)
          return ListTileTheme(data: ListTileThemeData(titleTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: C.text)), child: SafeArea(
            child: SingleChildScrollView( // [QA] S7: with the Notifications row it outgrew a 640 px phone's sheet
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // [S13-5 / his note 16] an × to close it, top right
                Row(children: [
                  Expanded(child: Text(l.settingsT, style: head.copyWith(fontSize: 22))),
                  IconButton(key: const Key('closeSettings'), tooltip: l.close, icon: Icon(Icons.close, color: C.mute), onPressed: () => Navigator.of(context).pop()),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Text(l.language)),
                  OutlinedButton(key: const Key('lang'), onPressed: () => prefs.lang = prefs.lang == 'en' ? 'ar' : 'en', child: Text(l.langSwitch, style: TextStyle(color: C.text))),
                ]),
                const SizedBox(height: 10),
                Text(l.sVoice),
                Text(l.sVoiceD, style: TextStyle(color: C.dim, fontSize: 12)),
                Slider(value: prefs.voice, onChanged: (v) => prefs.voice = v),
                Text(l.sSfx),
                Slider(value: prefs.sfx, onChanged: (v) => prefs.sfx = v),
                const SizedBox(height: 6),
                Text(l.sLook, style: head.copyWith(fontSize: 16)),
                const SizedBox(height: 8),
                Row(children: [
                  for (final (k, name, pal) in [('noir', l.sNoir, noirPalette), ('neon', l.sNeon, neonPalette)]) ...[
                    Expanded(child: _ThemeCard(key: Key('theme_$k'), name: name, p: pal, selected: prefs.theme == k, onTap: () => prefs.theme = k)),
                    if (k == 'noir') const SizedBox(width: 10),
                  ],
                ]),
                SwitchListTile(key: const Key('introAtStart'), contentPadding: EdgeInsets.zero, value: prefs.introAtStart, onChanged: (v) => prefs.introAtStart = v,
                    title: Text(l.sIntro), subtitle: Text(l.sIntroD, style: TextStyle(color: C.dim, fontSize: 12))),
                ListTile(key: const Key('watchIntro'), contentPadding: EdgeInsets.zero, title: Text(l.sWatchIntro),
                    trailing: Icon(Icons.play_circle_outline, color: C.mute, size: 20),
                    onTap: () { final nav = Navigator.of(context)..pop(); showIntro(nav.context, prefs); }),
                const SizedBox(height: 14),
                Text(l.sHost, style: head.copyWith(fontSize: 16)),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.sBuzz), Text(l.sBuzzD, style: TextStyle(color: C.dim, fontSize: 12)),
                  ])),
                  IconButton(key: const Key('buzzLess'), icon: Icon(Icons.remove_circle_outline, color: C.mute), onPressed: prefs.hostBuzzMax > 0 ? () => prefs.hostBuzzMax = prefs.hostBuzzMax - 1 : null),
                  Text('${prefs.hostBuzzMax}', key: const Key('buzzMax'), style: head.copyWith(fontSize: 18)),
                  IconButton(key: const Key('buzzMore'), icon: Icon(Icons.add_circle_outline, color: C.mute), onPressed: prefs.hostBuzzMax < 20 ? () => prefs.hostBuzzMax = prefs.hostBuzzMax + 1 : null),
                ]),
                // [QA] S9 #2: label above, the switch full width (side by side it overflowed in Neon / Arabic)
                Text(l.sKick),
                const SizedBox(height: 6),
                SizedBox(width: double.infinity, child: SegmentedButton<String>(key: const Key('kickMode'), showSelectedIcon: false,
                      segments: [ButtonSegment(value: 'lobby', label: Text(l.sKickLobby)), ButtonSegment(value: 'any', label: Text(l.sKickAny))],
                      selected: {prefs.hostKick}, onSelectionChanged: (s) => prefs.hostKick = s.first,
                      style: SegmentedButton.styleFrom(selectedBackgroundColor: C.red, selectedForegroundColor: C.priText, side: BorderSide(color: C.line2)))),
                const SizedBox(height: 6),
                // S13-5 / his note 10: the test notification button is gone (the server route stays for QA)
                ListTile(key: const Key('notifSettings'), contentPadding: EdgeInsets.zero, title: Text(l.sNotif),
                    subtitle: Text(l.sNotifD, style: TextStyle(color: C.dim, fontSize: 12)),
                    trailing: Icon(Icons.open_in_new, color: C.mute, size: 18), onTap: openNotificationSettings),
                if (updater != null && selfUpdate) ...[
                  ListTile(key: const Key('checkUpdates'), contentPadding: EdgeInsets.zero, title: Text(l.sCheck),
                      subtitle: _checked == null ? null : Text(_checked!, key: const Key('checkResult'), style: TextStyle(color: C.gold, fontSize: 12)),
                      trailing: Icon(Icons.refresh, color: C.mute, size: 18),
                      onTap: () async {
                        await updater!.check(force: true);
                        if (!context.mounted) return;
                        if (updater!.latest != null) { Navigator.of(context).pop(); return; } // the card on Home has Update
                        setState(() => _checked = l.sUpToDate);
                      }),
                ],
                // S13-5: a long press shows what the app keeps on the phone (to find out what a big "Data" is)
                GestureDetector(onLongPress: updater == null ? null : () => _storage(context),
                    child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.sVersion(appVersion, appBuild), key: const Key('version'), style: TextStyle(color: C.dim, fontSize: 12)))),
              ]),
            ),
          ));
        },
      );
}

/// A small preview of a look (P3): its background, a primary button and a heading in its font.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({super.key, required this.name, required this.p, required this.selected, required this.onTap});
  final String name;
  final Palette p;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(p.radius),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(p.radius),
              gradient: p.neon ? const RadialGradient(center: Alignment(-.8, -1), radius: 1.2, colors: [Color(0x55FF2E63), Color(0xFF0B0A10)]) : null,
              border: Border.all(color: selected ? p.red : p.line2, width: selected ? 2 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(name, style: TextStyle(fontFamily: p.head, fontFamilyFallback: p.headFallback, color: p.text, fontSize: 18, fontWeight: p.headWeight,
                fontVariations: p.neon ? const [FontVariation('wght', 700)] : null)),
            const SizedBox(height: 8),
            Container(height: 22, decoration: BoxDecoration(color: p.neon ? null : p.red, gradient: p.neon ? neonPrimary : null, borderRadius: BorderRadius.circular(p.neon ? 11 : 3),
                boxShadow: p.neon ? null : const [BoxShadow(color: Colors.black, offset: Offset(2, 2))])),
            const SizedBox(height: 6),
            Row(children: [for (final r in p.roles.values) Expanded(child: Container(height: 6, margin: const EdgeInsets.symmetric(horizontal: 1), color: r))]),
            if (selected) Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.check_circle, color: p.red, size: 18)),
          ]),
        ),
      );
}
