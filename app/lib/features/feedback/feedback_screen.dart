// Sprint 19 (1.2.0): the suggestions box. Players send a suggestion or a problem with at most one screenshot (S19-1),
// within their limits (S19-2), and see what they sent and how far it got (P3). The admin reads and empties it (S19-3).
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/features/friends/friends_screen.dart' show openProfile;
import 'package:mafia_dealer/features/history/game_detail.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/state/models.dart';

/// A screenshot as a JPEG: at most 1280 px on its long side and 300 KB (S19-2 AC2); null when it can't be read or shrunk.
Uint8List? shotJpeg(Uint8List bytes) {
  final i = img.decodeImage(bytes);
  if (i == null) return null;
  final long = i.width > i.height ? i.width : i.height;
  final s = long <= 1280 ? i : i.width >= i.height ? img.copyResize(i, width: 1280) : img.copyResize(i, height: 1280);
  for (var q = 80; q >= 30; q -= 10) {
    final out = img.encodeJpg(s, quality: q);
    if (out.length <= 300000) return out;
  }
  return null;
}

String _day(BuildContext context, int at) {
  final d = DateTime.fromMillisecondsSinceEpoch(at);
  return '${d.day} ${DateFormat.MMM(Localizations.localeOf(context).languageCode).format(d)} ${d.year}';
}

/// Settings → Suggestions & problems: the form, then "My messages".
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, required this.account, this.gameId});
  final Account account;
  final String? gameId; // [P2] "Report a problem with this game"
  /// Tests replace the gallery with a fake picture.
  static Future<Uint8List?> Function()? testPicker;
  @override
  State<FeedbackScreen> createState() => _FeedbackState();
}

class _FeedbackState extends State<FeedbackScreen> {
  late String kind = widget.gameId != null ? 'problem' : 'idea';
  final text = TextEditingController();
  Uint8List? shot;
  List<Map<String, Object?>>? mine;
  String? blocked, error;
  bool busy = false;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final r = await widget.account.feedbackMine(); if (mounted) setState(() { mine = r.mine; blocked = r.blocked; error = null; }); }
    catch (e) { if (mounted) setState(() { mine ??= []; error = errText(L.of(context), e); }); }
  }

  /// What the phone adds by itself (AC3). [Quin Q4] the Android version from Android itself (Platform has the kernel's).
  Future<Map<String, Object?>> _info(String lang) async {
    String os = Platform.isAndroid ? 'Android' : Platform.operatingSystem;
    try { os = await const MethodChannel('mafia/keep').invokeMethod<String>('android') ?? os; } catch (_) {}
    return {'app': appVersion, 'build': appBuild, 'lang': lang, 'os': os.characters.take(40).toString()};
  }

  Future<void> _pick() async {
    final l = L.of(context);
    // [Quin Q5] Android shrinks it first (a 50 MP photo never reaches Dart whole); the JPEG pass runs off the UI thread
    final raw = FeedbackScreen.testPicker != null ? await FeedbackScreen.testPicker!()
        : await (await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, maxHeight: 1280, imageQuality: 80))?.readAsBytes();
    if (raw == null || !mounted) return;
    setState(() => busy = true);
    final j = await compute(shotJpeg, raw);
    if (!mounted) return;
    setState(() => busy = false);
    if (j == null) return toastErr(context, l.fbShotBad);
    setState(() => shot = j);
  }

  Future<void> _send() async {
    final l = L.of(context), t = text.text.trim(), n = t.runes.length; // [Quin Q9] counted as the server counts
    if (busy) return; // [Quin Q15] two taps, one send
    if (n < 10) return setState(() => error = l.fbTooShort);
    if (n > 1000) return setState(() => error = l.fbTooLong);
    setState(() { busy = true; error = null; });
    try {
      final info = await _info(Localizations.localeOf(context).languageCode);
      await widget.account.sendFeedback({'kind': kind, 'text': t, 'info': info, if (shot != null) 'image': 'data:image/jpeg;base64,${base64Encode(shot!)}',
        if (widget.gameId != null) 'gameId': widget.gameId});
      if (!mounted) return;
      toast(context, l.fbThanks);
      Navigator.of(context).pop();
    } catch (e) {
      // AC2: what was typed stays; it says why and can be sent again
      // (the form stays up even if the limit was reached meanwhile; the next visit says so before typing)
      if (mounted) setState(() { busy = false; error = e is ApiError && e.code == 'box_full' ? l.fbFull : e is ApiError && e.code == 'not_found' ? l.fbGameGone : errText(l, e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), why = blocked;
    return Scaffold(
      appBar: AppBar(title: Text(l.fbT, style: head.copyWith(fontSize: 20))),
      body: mine == null ? Center(child: CircularProgressIndicator(color: C.red2)) : ListView(padding: const EdgeInsets.all(16), children: [
        if (why != null)
          // S19-2 AC1: said before typing
          Sec(key: const Key('fbBlocked'), child: Text(switch (why) { 'day' => l.fbDay, 'waiting' => l.fbWaiting, _ => l.fbFull }, style: TextStyle(color: C.gold)))
        else ...[
          Seg(key: const Key('fbKind'), expand: true, value: kind, onChanged: (v) => setState(() => kind = v),
              options: [('idea', l.fbIdea, const Key('fbIdea')), ('problem', l.fbProblem, const Key('fbProblem'))]),
          if (widget.gameId != null) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
            Icon(Icons.casino_outlined, size: 18, color: C.gold), const SizedBox(width: 6), Expanded(child: Text(l.fbAboutGame, key: const Key('fbGame'), style: TextStyle(color: C.mute))),
          ])),
          const SizedBox(height: 12),
          TextField(key: const Key('fbText'), controller: text, maxLength: 1000, minLines: 4, maxLines: 8,
              decoration: InputDecoration(hintText: kind == 'idea' ? l.fbIdeaHint : l.fbProblemHint)),
          const SizedBox(height: 8),
          if (shot == null)
            OutlinedButton.icon(key: const Key('fbShot'), onPressed: busy ? null : _pick, icon: Icon(Icons.add_photo_alternate_outlined, color: C.text),
                label: Text(l.fbAddShot, style: TextStyle(color: C.text)))
          else Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(C.p.radius), child: Image.memory(shot!, key: const Key('fbShotPreview'), width: 96, height: 96, fit: BoxFit.cover, cacheWidth: 192)),
            const SizedBox(width: 10),
            Expanded(child: Wrap(spacing: 4, children: [
              TextButton(key: const Key('fbShotReplace'), onPressed: busy ? null : _pick, child: Text(l.fbReplace, style: TextStyle(color: C.text))),
              TextButton(key: const Key('fbShotRemove'), onPressed: busy ? null : () => setState(() => shot = null), child: Text(l.fbRemove, style: TextStyle(color: C.red2))),
            ])),
          ]),
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.fbInfo('$appVersion ($appBuild)'), style: TextStyle(color: C.dim, fontSize: 12))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, key: const Key('fbError'), style: TextStyle(color: C.red2))),
          const SizedBox(height: 12),
          Btn(l.fbSend, key: const Key('fbSend'), icon: Icons.send_outlined, onTap: busy ? null : _send),
        ],
        // P3: what I sent, and how far it got
        if (mine!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 18), child: Sec(title: l.fbMine, child: Column(children: [
          for (final m in mine!) Padding(key: Key('mine_${m['id']}'), padding: const EdgeInsets.symmetric(vertical: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(m['kind'] == 'problem' ? Icons.bug_report_outlined : Icons.lightbulb_outline, size: 20, color: C.mute),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['text'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(_day(context, m['at'] as int), style: TextStyle(color: C.dim, fontSize: 12)),
            ])),
            const SizedBox(width: 8),
            Text(switch (m['status']) { 'done' => l.fbDone, 'read' => l.fbRead, _ => l.fbSent }, key: Key('mineStatus_${m['id']}'),
                style: TextStyle(color: m['status'] == 'done' ? C.green : m['status'] == 'read' ? C.gold : C.dim, fontSize: 12, fontWeight: FontWeight.w700)),
          ])),
        ]))),
      ]),
    );
  }
}

/// Profile → Suggestions (admin only, S19-3).
class FeedbackBoxScreen extends StatefulWidget {
  const FeedbackBoxScreen({super.key, required this.account});
  final Account account;
  @override
  State<FeedbackBoxScreen> createState() => _BoxState();
}

class _BoxState extends State<FeedbackBoxScreen> {
  List<Map<String, Object?>>? items;
  String filter = 'all';
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final r = await widget.account.feedbackBox(); if (mounted) setState(() => items = (r['items'] as List).map((x) => Map<String, Object?>.from(x as Map)).toList()); }
    catch (e) { if (mounted) { setState(() => items ??= []); toastErr(context, errText(L.of(context), e)); } }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), all = items, shown = all?.where((x) => filter == 'all' || x['kind'] == filter).toList();
    return Scaffold(
      appBar: AppBar(title: Text(l.fbBoxT, style: head.copyWith(fontSize: 20)), actions: [
        if (all != null && all.isNotEmpty) IconButton(key: const Key('fbEmpty'), tooltip: l.fbEmpty, icon: Icon(Icons.delete_sweep_outlined, color: C.red2), onPressed: () async {
          if (!await ask(context, l.fbEmptyQ(all.length), l.fbEmptyD, l.fbEmpty)) return;
          try { await widget.account.emptyFeedback(all.map((x) => x['at'] as int).reduce((a, b) => a > b ? a : b)); }
          catch (e) { if (context.mounted) toastErr(context, errText(l, e)); } // [Quin Q8]
          _load();
        }),
      ]),
      body: shown == null ? Center(child: CircularProgressIndicator(color: C.red2)) : Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 4), child: Seg(key: const Key('fbFilter'), expand: true, value: filter, onChanged: (v) => setState(() => filter = v),
            options: [('all', l.fbAll, const Key('fbAll')), ('idea', l.fbIdeas, const Key('fbIdeas')), ('problem', l.fbProblems, const Key('fbProblems'))])),
        Expanded(child: shown.isEmpty ? Center(child: Text(l.fbEmptyBox, key: const Key('fbNone'), style: TextStyle(color: C.mute))) : ListView(padding: const EdgeInsets.all(16), children: [
          for (final x in shown)
            ListTile(key: Key('fb_${x['id']}'), contentPadding: EdgeInsets.zero,
              leading: Icon(x['kind'] == 'problem' ? Icons.bug_report_outlined : Icons.lightbulb_outline, color: x['status'] == 'new' ? C.red2 : C.mute),
              title: Text(x['text'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: x['status'] == 'new' ? FontWeight.w700 : FontWeight.w400)),
              subtitle: Text('${(x['from'] as Map?)?['display'] ?? '?'} · ${_day(context, x['at'] as int)}${x['shot'] == true ? ' · 📷' : ''}', style: TextStyle(color: C.dim, fontSize: 12)),
              trailing: x['status'] == 'done' ? Icon(Icons.check_circle_outline, color: C.green) : null,
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _Item(account: widget.account, id: x['id'] as String)));
                _load();
              }),
        ])),
      ]),
    );
  }
}

class _Item extends StatefulWidget {
  const _Item({required this.account, required this.id});
  final Account account;
  final String id;
  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  Map<String, Object?>? x;
  Uint8List? shot;
  Map<String, Object?>? get from => x?['from'] is Map ? Map<String, Object?>.from(x!['from'] as Map) : null;
  @override
  void initState() {
    super.initState();
    widget.account.feedbackItem(widget.id).then((r) {
      if (mounted) setState(() => x = r);
      if (r['shot'] == true) widget.account.feedbackShot(widget.id).then((b) { if (mounted) setState(() => shot = b); }).catchError((_) {});
    }).catchError((Object e) { if (mounted) toastErr(context, errText(L.of(context), e)); });
  }

  /// [Quin Q8] say so when it didn't work, instead of a success that never happened
  Future<bool> _try(Future<void> Function() f) async {
    try { await f(); return true; } catch (e) { if (mounted) toastErr(context, errText(L.of(context), e)); return false; }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), it = x, a = widget.account;
    final shot = this.shot, info = it?['info'] as Map?;
    return Scaffold(
      appBar: AppBar(title: Text(it?['kind'] == 'problem' ? l.fbProblem : l.fbIdea, style: head.copyWith(fontSize: 20))),
      body: it == null ? Center(child: CircularProgressIndicator(color: C.red2)) : Stage(center: false, bottom: [
        if (it['status'] != 'done') Btn(l.fbMarkDone, key: const Key('fbMarkDone'), icon: Icons.check, onTap: () async {
          if (!await _try(() => a.markFeedback(widget.id, 'done'))) return;
          if (context.mounted) { toast(context, l.fbMarkedDone); setState(() => it['status'] = 'done'); }
        }),
        Btn(l.fbDelete, key: const Key('fbDelete'), ghost: true, icon: Icons.delete_outline, onTap: () async {
          if (!await ask(context, l.fbDeleteQ, l.fbEmptyD, l.fbDelete)) return;
          if (!await _try(() => a.deleteFeedback(widget.id))) return;
          if (context.mounted) Navigator.of(context).pop();
        }),
      ], children: [
        if (from != null) ListTile(key: const Key('fbFrom'), contentPadding: EdgeInsets.zero, title: Text(from!['display'] as String),
            subtitle: Text(atHandle(from!['handle'] as String?), style: TextStyle(color: C.mute)), trailing: Icon(Icons.chevron_right, color: C.mute),
            onTap: () => openProfile(context, a, Person(from!))),
        Text(_day(context, it['at'] as int), style: TextStyle(color: C.dim, fontSize: 12)),
        const SizedBox(height: 10),
        SelectableText(it['text'] as String, key: const Key('fbItemText'), style: const TextStyle(fontSize: 16)), // AC5: text only
        if (info != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('v${info['app']} · b${info['build']} · ${info['lang']} · ${info['os']}',
            textDirection: TextDirection.ltr, style: TextStyle(color: C.dim, fontSize: 12))),
        if (it['gameId'] is String) TextButton.icon(key: const Key('fbOpenGame'), icon: Icon(Icons.casino_outlined, color: C.gold), label: Text(l.fbOpenGame, style: TextStyle(color: C.gold)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameDetail(account: a, id: it['gameId'] as String)))),
        if (shot != null) Padding(padding: const EdgeInsets.only(top: 12), child: GestureDetector(key: const Key('fbItemShot'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(), backgroundColor: Colors.black,
                body: InteractiveViewer(child: Center(child: Image.memory(shot, cacheWidth: 1280)))))),
            child: ClipRRect(borderRadius: BorderRadius.circular(C.p.radius), child: Image.memory(shot, height: 220, fit: BoxFit.contain, cacheHeight: 440)))),
      ]),
    );
  }
}
