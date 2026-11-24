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

  Widget _pct(double v) => SizedBox(width: 44, child: Text('${(v * 100).round()}%', textAlign: TextAlign.end, style: TextStyle(color: C.mute, fontSize: 13)));
  Widget _step(Key key, IconData icon, VoidCallback? onTap) => SqBtn(icon, key: key, onTap: onTap);
  Widget get _line => Divider(height: 1, color: C.line);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: prefs,
        builder: (context, _) {
          final l = L.of(context);
          // [his look note] a full page of section cards, as the old app's Settings (it was a bottom sheet)
          return Scaffold(
            appBar: AppBar(leading: BackButton(key: const Key('closeSettings')), title: Text(l.settingsT)),
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Sec(title: l.sLook, icon: Icons.palette_outlined, child: Column(children: [
                OptRow(l.language, trailing: Seg(key: const Key('lang'), value: prefs.lang, onChanged: (v) => prefs.lang = v,
                    options: const [('en', 'English', Key('lang_en')), ('ar', 'العربية', Key('lang_ar'))])),
                _line,
                OptRow(l.sTheme, trailing: Seg(value: prefs.theme, onChanged: (v) => prefs.theme = v,
                    options: [('neon', l.sNeon, const Key('theme_neon')), ('noir', l.sNoir, const Key('theme_noir'))])),
              ])),
              Sec(title: l.sSound, icon: Icons.volume_up_outlined, child: Column(children: [
                OptRow(l.sVoice, desc: l.sVoiceD, trailing: null),
                Row(children: [Expanded(child: Slider(value: prefs.voice, onChanged: (v) => prefs.voice = v)), _pct(prefs.voice)]),
                _line,
                Row(children: [Text(l.sSfx, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.text)),
                  Expanded(child: Slider(value: prefs.sfx, onChanged: (v) => prefs.sfx = v)), _pct(prefs.sfx)]),
              ])),
              Sec(title: l.sHost, icon: Icons.workspace_premium_outlined, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                OptRow(l.sBuzz, desc: l.sBuzzD, trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _step(const Key('buzzLess'), Icons.remove, prefs.hostBuzzMax > 0 ? () => prefs.hostBuzzMax = prefs.hostBuzzMax - 1 : null),
                  SizedBox(width: 40, child: Text('${prefs.hostBuzzMax}', key: const Key('buzzMax'), textAlign: TextAlign.center, style: head.copyWith(fontSize: 18))),
                  _step(const Key('buzzMore'), Icons.add, prefs.hostBuzzMax < 20 ? () => prefs.hostBuzzMax = prefs.hostBuzzMax + 1 : null),
                ])),
                _line,
                OptRow(l.sKick),
                Seg(key: const Key('kickMode'), expand: true, value: prefs.hostKick, onChanged: (v) => prefs.hostKick = v,
                    options: [('lobby', l.sKickLobby, const Key('kick_lobby')), ('any', l.sKickAny, const Key('kick_any'))]),
              ])),
              Sec(title: l.sMore, icon: Icons.visibility_outlined, child: Column(children: [
                OptRow(l.sNotif, key: const Key('notifSettings'), desc: l.sNotifD, onTap: openNotificationSettings, trailing: Icon(Icons.open_in_new, color: C.mute, size: 18)),
                _line,
                OptRow(l.sIntro, desc: l.sIntroD, trailing: SqSwitch(key: const Key('introAtStart'), value: prefs.introAtStart, onChanged: (v) => prefs.introAtStart = v)),
                _line,
                OptRow(l.sWatchIntro, key: const Key('watchIntro'), trailing: Icon(Icons.chevron_right, color: C.mute),
                    onTap: () { final nav = Navigator.of(context)..pop(); showIntro(nav.context, prefs); }),
                if (updater != null && selfUpdate) ...[
                  _line,
                  OptRow(l.sCheck, key: const Key('checkUpdates'), desc: _checked, descKey: const Key('checkResult'), trailing: Icon(Icons.chevron_right, color: C.mute),
                      onTap: () async {
                        final ok = await updater!.check(force: true);
                        if (!context.mounted) return;
                        if (updater!.latest != null) { Navigator.of(context).pop(); return; } // the card on Home has Update
                        setState(() => _checked = ok ? l.sUpToDate : l.sCheckFailed);
                      }),
                ],
                _line,
                // S13-5: a long press shows what the app keeps on the phone (to find out what a big "Data" is)
                OptRow(l.sVersionT, onLongPress: updater == null ? null : () => _storage(context),
                    trailing: Text('v$appVersion · b$appBuild', key: const Key('version'), textDirection: TextDirection.ltr, style: TextStyle(color: C.mute, fontSize: 13))),
              ])),
            ]),
          );
        },
      );
}
