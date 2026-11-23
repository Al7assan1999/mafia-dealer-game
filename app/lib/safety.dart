// Block and report (Google Play's user-generated-content rule), the blocked list, and the admin's report queue.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'account_screens.dart';
import 'l10n/app_localizations.dart';
import 'ui.dart';

/// "Block X?" then blocks. Returns true when blocked.
Future<bool> confirmBlock(BuildContext context, Account a, String userId, String name) async {
  final l = L.of(context);
  if (!await ask(context, l.blockQ(name), l.blockD, l.block)) return false;
  try {
    await a.block(userId);
    if (context.mounted) toast(context, l.blockedToast(name));
    return true;
  } catch (e) {
    if (context.mounted) toastErr(context, errText(l, e));
    return false;
  }
}

/// Report a player or one of their messages: a reason, an optional note, and "also block". Returns true when sent.
Future<bool> reportDialog(BuildContext context, Account a, String userId, String name, {String? room, int? msgId, String? text}) async {
  final l = L.of(context), note = TextEditingController();
  String? reason; // no preselected reason: "Send report" waits for a choice
  var alsoBlock = true;
  final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: Text(l.reportQ(name), style: head.copyWith(fontSize: 20)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (text != null) ...[
            Container(width: double.infinity, padding: const EdgeInsets.all(10), color: C.card2, child: Text(text, style: const TextStyle(fontStyle: FontStyle.italic))),
            Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Text(l.reportMsg, style: TextStyle(color: C.dim, fontSize: 12))),
          ],
          RadioGroup<String>(
            groupValue: reason,
            onChanged: (v) => set(() => reason = v),
            child: Column(children: [
              for (final (k, t) in [('spam', l.reasonSpam), ('harassment', l.reasonHarassment), ('hate', l.reasonHate), ('other', l.reasonOther)])
                RadioListTile<String>(key: Key('reason_$k'), value: k, title: Text(t), dense: true, contentPadding: EdgeInsets.zero),
            ]),
          ),
          TextField(key: const Key('reportNote'), controller: note, maxLength: 300, maxLines: 2, decoration: InputDecoration(hintText: l.reportNote)),
          CheckboxListTile(key: const Key('alsoBlock'), value: alsoBlock, onChanged: (v) => set(() => alsoBlock = v ?? false), title: Text(l.alsoBlock),
              contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel, style: TextStyle(color: C.mute))),
          TextButton(key: const Key('sendReport'), onPressed: reason == null ? null : () => Navigator.pop(c, true), child: Text(l.sendReport, style: TextStyle(color: C.red2, fontWeight: FontWeight.w700))),
        ],
      )));
  if (ok != true || !context.mounted) return false;
  try {
    await a.report(userId, reason!, note: note.text, room: room, msgId: msgId);
    if (alsoBlock) await a.block(userId);
    if (context.mounted) toast(context, l.reportSent);
    return true;
  } catch (e) {
    if (context.mounted) toastErr(context, errText(l, e));
    return false;
  }
}

/// A "⋮" menu with Block and Report for another player (lobby, friends, chat).
class SafetyMenu extends StatelessWidget {
  const SafetyMenu({super.key, required this.account, required this.userId, required this.name, this.extra = const [], this.onExtra, this.safety = true});
  final bool safety; // block / report need accounts: not on Wi-Fi
  final Account account;
  final String userId, name;
  final List<PopupMenuEntry<String>> extra;
  final void Function(String)? onExtra;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return PopupMenuButton<String>(
      key: Key('safety_$name'),
      icon: Icon(Icons.more_vert, color: C.dim),
      onSelected: (x) {
        if (x == 'block') { confirmBlock(context, account, userId, name); } else if (x == 'report') { reportDialog(context, account, userId, name); } else { onExtra?.call(x); }
      },
      itemBuilder: (_) => [...extra, if (safety) ...[PopupMenuItem(value: 'block', child: Text(l.block)), PopupMenuItem(value: 'report', child: Text(l.report))]],
    );
  }
}

/// Profile → Blocked players.
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key, required this.account});
  final Account account;
  @override
  State<BlockedScreen> createState() => _BlockedState();
}

class _BlockedState extends State<BlockedScreen> {
  List<Person>? list;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final b = await widget.account.blocked(); if (mounted) setState(() => list = b); } catch (_) { if (mounted) setState(() => list = []); } }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.blockedList, style: head.copyWith(fontSize: 20))),
      body: list == null ? Center(child: CircularProgressIndicator(color: C.red2))
          : list!.isEmpty ? Center(child: Text(l.noBlocked, style: TextStyle(color: C.mute)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              for (final p in list!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AvatarView.of(widget.account.api, p, size: 36),
                  title: Text(p.display),
                  subtitle: Text(atHandle(p.handle), style: TextStyle(color: C.mute)),
                  trailing: TextButton(key: Key('unblock_${p.handle}'), onPressed: () async {
                    await widget.account.unblock(p.id).catchError((_) {});
                    _load();
                  }, child: Text(l.unblock, style: TextStyle(color: C.red2))),
                ),
            ]),
    );
  }
}

/// The admin's report queue: dismiss, or ban the reported account.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.account});
  final Account account;
  @override
  State<ReportsScreen> createState() => _ReportsState();
}

class _ReportsState extends State<ReportsScreen> {
  List<Map<String, Object?>>? list;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final r = await widget.account.openReports(); if (mounted) setState(() => list = r); } catch (_) { if (mounted) setState(() => list = []); } }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    String reason(Object? r) => switch (r) { 'spam' => l.reasonSpam, 'harassment' => l.reasonHarassment, 'hate' => l.reasonHate, _ => l.reasonOther };
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.reportsT, style: head.copyWith(fontSize: 20))),
      body: list == null ? Center(child: CircularProgressIndicator(color: C.red2))
          : list!.isEmpty ? Center(child: Text(l.noReports, style: TextStyle(color: C.mute)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              for (final r in list!)
                Sec(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['display']} ${atHandle(r['handle'] as String?)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${reason(r['reason'])} · ${l.reportedBy((r['reporter'] as String?) ?? '—')}', style: TextStyle(color: C.mute, fontSize: 12)),
                  if ((r['message'] as Map?)?['text'] != null) Padding(padding: const EdgeInsets.only(top: 8),
                      child: Text('“${(r['message'] as Map)['text']}”', style: const TextStyle(fontStyle: FontStyle.italic))),
                  if ((r['note'] as String?)?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r['note'] as String, style: TextStyle(color: C.mute))),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () async { await widget.account.moderate(r['id'] as String, 'dismiss').catchError((_) {}); _load(); }, child: Text(l.dismiss, style: TextStyle(color: C.mute))),
                    TextButton(key: Key('ban_${r['id']}'), onPressed: () async {
                      if (!await ask(context, l.banQ(r['display'] as String), l.banD, l.ban)) return;
                      await widget.account.moderate(r['id'] as String, 'ban').catchError((_) {});
                      _load();
                    }, child: Text(l.ban, style: TextStyle(color: C.red2, fontWeight: FontWeight.w700))),
                  ]),
                ])),
            ]),
    );
  }
}

/// Copies a value and says so (the account id for the admin setting).
void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  toast(context, L.of(context).copied);
}
