import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/avatar.dart';
import 'package:mafia_dealer/features/old_history/import_screen.dart';
import 'package:mafia_dealer/features/old_history/old_players_screen.dart';
import 'package:mafia_dealer/features/safety/safety.dart';
import 'package:mafia_dealer/features/stats/player_screen.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

// ---------------------------------------------------------------- profile
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.account});
  final Account account;
  /// Tests replace the gallery with a fake picture.
  static Future<Uint8List?> Function()? testPicker;
  @override
  State<ProfileScreen> createState() => _ProfileState();
}

/// Crops a picture to a square, 256 px, and makes it a JPEG of at most 150 KB (null when it can't be read).
Uint8List? squareJpeg(Uint8List bytes) {
  final i = img.decodeImage(bytes);
  if (i == null) return null;
  final sq = img.copyResizeCropSquare(i, size: 256);
  for (var q = 85; q >= 40; q -= 15) {
    final out = img.encodeJpg(sq, quality: q);
    if (out.length <= 150000) return out;
  }
  return null;
}

class _ProfileState extends State<ProfileScreen> {
  late final a = widget.account;
  late final handle = TextEditingController(text: a.handle ?? ''), name = TextEditingController(text: a.display);
  late String fav = (a.me?['fav'] as String?) ?? '';
  late bool showOn = a.me?['showOnline'] != false;
  List<Map<String, Object?>>? devices;
  Object? devicesErr; // [S15] his phone showed an empty list: the reason is shown now, with Try again
  bool busy = false;

  @override
  void initState() { super.initState(); _loadDevices(); }
  Future<void> _loadDevices() async {
    try { final d = await a.sessions(); if (mounted) setState(() { devices = d; devicesErr = null; }); }
    catch (e) { if (mounted) setState(() => devicesErr = e); }
  }

  Future<void> _do(Future<void> Function() f, [String? ok]) async {
    if (busy) return;
    setState(() => busy = true);
    final l = L.of(context);
    try { await f(); if (ok != null && mounted) toast(context, ok); } catch (e) { if (mounted) toastErr(context, errText(l, e)); }
    if (mounted) setState(() => busy = false);
  }

  Future<Uint8List?> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
    return f == null ? null : await f.readAsBytes();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: a, builder: (context, _) {
        final l = L.of(context);
        if (!a.signedIn) return Scaffold(appBar: AppBar(), body: Stage(children: [Big(l.aDeleted)]));
        return Scaffold(
          appBar: AppBar(title: Text(l.profT, style: head.copyWith(fontSize: 20))),
          body: Stage(center: false, children: [
            Sec(title: l.aAvatar, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < 10; i++)
                  InkWell(key: Key('preset$i'), onTap: () => _do(() => a.avatarPreset(i)),
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: a.card!.photo == null && a.card!.preset == i ? C.red : Colors.transparent, width: 2), borderRadius: BorderRadius.circular(6)),
                        child: AvatarView(api: a.api, id: a.card!.id, preset: i, size: 44))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                AvatarView.of(a.api, a.card!, size: 56),
                const SizedBox(width: 12),
                OutlinedButton.icon(key: const Key('photo'), icon: const Icon(Icons.photo_outlined), label: Text(l.aPhoto),
                    onPressed: busy ? null : () => _do(() async {
                          final raw = await (ProfileScreen.testPicker ?? _pick)();
                          if (raw == null) return;
                          final jpeg = squareJpeg(raw);
                          if (jpeg == null) throw ApiError('avatar');
                          await a.avatarPhoto(jpeg);
                        })),
              ]),
            ])),
            Sec(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(key: const Key('handle'), controller: handle, maxLength: 21, decoration: InputDecoration(labelText: l.aUser, prefixText: '@', counterText: '')),
              const SizedBox(height: 10),
              TextField(key: const Key('display'), controller: name, maxLength: 18, decoration: InputDecoration(labelText: l.aName, counterText: '')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: const Key('fav'), initialValue: fav, decoration: InputDecoration(labelText: l.aFav),
                items: [
                  for (final (k, t) in [('', l.aNone), ('mafia', l.mafia), ('doctor', l.doctor), ('detective', l.detective), ('citizen', l.citizen)])
                    DropdownMenuItem(value: k, child: Text(t)),
                ],
                onChanged: (v) => setState(() => fav = v ?? ''),
              ),
              SqSwitchTile(key: const Key('showOnline'), value: showOn, onChanged: (v) => setState(() => showOn = v), title: l.fShowOn, subtitle: l.fShowOnD),
              Btn(l.aSave, key: const Key('saveProfile'), onTap: busy ? null : () {
                if (!handleRx.hasMatch(handle.text.trim())) return toast(context, l.eHandle);
                if (name.text.trim().isEmpty) return toast(context, l.eBadName);
                _do(() => a.patch({'handle': handle.text.trim(), 'display': name.text.trim(), 'fav': fav, 'showOnline': showOn}), l.aSaved);
              }),
            ])),
            Sec(child: Column(children: [
              ListTile(key: const Key('myStats'), contentPadding: EdgeInsets.zero, leading: Icon(Icons.leaderboard_outlined, color: C.gold), title: Text(l.myStats),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(account: a, playerKey: 'u:${a.card!.id}')))),
              // S13-1: only the admin imports (one truth for everyone)
              if (a.isAdmin) ListTile(key: const Key('importOldHistory'), contentPadding: EdgeInsets.zero, leading: Icon(Icons.history_edu_outlined, color: C.mute), title: Text(l.importT),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportScreen(account: a)))),
              // [S12-1] the admin marks the names found in imported games (replaces "send me the list")
              if (a.isAdmin) ListTile(key: const Key('oldPlayers'), contentPadding: EdgeInsets.zero, leading: Icon(Icons.how_to_reg_outlined, color: C.gold), title: Text(l.oldPlayersT),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OldPlayersScreen(account: a)))),
              SqSwitchTile(key: const Key('onBoard'), value: a.me?['onBoard'] != false, onChanged: busy ? null : (v) => _do(() => a.patch({'onBoard': v})),
                  title: l.onBoardT, subtitle: l.onBoardD),
            ])),
            Sec(title: l.aDevices, child: Column(children: [
              if (devicesErr != null)
                Row(key: const Key('devicesErr'), children: [
                  Expanded(child: Text(errText(l, devicesErr!), style: TextStyle(color: C.mute))),
                  TextButton(onPressed: _loadDevices, child: Text(l.retry)),
                ]),
              for (final d in devices ?? const <Map<String, Object?>>[])
                Row(children: [
                  Icon(Icons.smartphone, color: C.mute, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${d['device']}${d['current'] == true ? ' · ${l.aThisDevice}' : ''}')),
                  TextButton(onPressed: () => _do(() async {
                        await a.endSession(d['id'] as String, current: d['current'] == true);
                        await _loadDevices();
                      }), child: Text(l.aSignOutDevice, style: TextStyle(color: C.red2))),
                ]),
            ])),
            Sec(child: Column(children: [
              ListTile(key: const Key('blockedList'), contentPadding: EdgeInsets.zero, leading: Icon(Icons.block, color: C.mute), title: Text(l.blockedList),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BlockedScreen(account: a)))),
              if (a.isAdmin) ListTile(key: const Key('reports'), contentPadding: EdgeInsets.zero, leading: Icon(Icons.flag_outlined, color: C.red2), title: Text(l.reportsT),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportsScreen(account: a)))),
              ListTile(key: const Key('accountId'), contentPadding: EdgeInsets.zero, leading: Icon(Icons.badge_outlined, color: C.mute), title: Text(l.accountId),
                  subtitle: Text(a.card!.id, style: TextStyle(color: C.dim, fontSize: 11)), trailing: Icon(Icons.copy, size: 18, color: C.dim),
                  onTap: () => copyText(context, a.card!.id)),
            ])),
            Btn(l.aOut, key: const Key('signOut'), ghost: true, icon: Icons.logout, onTap: () async {
              if (await ask(context, l.aOutQ, l.aOutD, l.aOut)) {
                await a.logout();
                if (context.mounted) Navigator.of(context).pop();
              }
            }),
            const SizedBox(height: 12),
            TextButton(key: const Key('deleteAccount'), onPressed: () => _confirmDelete(l), child: Text(l.aDel, style: TextStyle(color: C.red2))),
          ]),
        );
      });

  Future<void> _confirmDelete(L l) async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
          title: Text(l.aDelQ, style: head.copyWith(fontSize: 20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(l.aDelD, style: TextStyle(color: C.mute)),
            const SizedBox(height: 10),
            TextField(key: const Key('typeDelete'), controller: typed, onChanged: (_) => set(() {}), decoration: const InputDecoration(hintText: 'delete')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel, style: TextStyle(color: C.mute))),
            TextButton(key: const Key('confirmDelete'), onPressed: typed.text.trim().toLowerCase() == 'delete' ? () => Navigator.pop(c, true) : null,
                child: Text(l.aDel, style: TextStyle(color: C.red2, fontWeight: FontWeight.w700))),
          ],
        )));
    if (ok != true || !mounted) return;
    await _do(() async {
      await a.deleteAccount();
      if (mounted) { toast(context, l.aDeleted); Navigator.of(context).pop(); }
    });
  }
}
