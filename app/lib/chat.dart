// The room chat: Everyone and 1:1 conversations, sending with "sending / not sent · retry", replies (swipe or long press),
// the old app's 30 reactions (quick six first), edits for 15 minutes, @mentions, and block / report from a message.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account.dart';
import 'l10n/app_localizations.dart';
import 'room.dart';
import 'safety.dart';
import 'ui.dart';

/// The old app's reactions: the quick six (👍 ❤️ 😂 😮 🔪 suspicious, 🤫 lying), then the rest (🐀 = snitch).
const reactions = ['👍', '❤️', '😂', '😮', '🔪', '🤫', '😡', '🤬', '😢', '😭', '💔', '🤨', '🙏', '🔥', '💀', '🤔', '🙄', '😱', '🤡', '👀',
  '👏', '😈', '🥲', '😴', '🤝', '💯', '🎯', '🐀', '🕵️', '🩸'];
const editWindowMs = 15 * 60 * 1000;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conn, required this.account, required this.out, this.safety = true});
  final bool safety; // block / report (online only: Wi-Fi players may have no account)
  final RoomConn conn;
  final Account account;
  final bool out; // I'm out of the running game: Everyone reaches only out players
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  RoomConn get c => widget.conn;
  String conv = 'all';
  final text = TextEditingController();
  Map<String, Object?>? replyTo, editing;
  final mentions = <int>{};

  @override
  void initState() {
    super.initState();
    // not during the build: marking it read tells the room screen to rebuild
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) c.openConversation(conv); });
  }
  @override
  void dispose() {
    final conn = c;
    Future.microtask(() => conn.openConversation(null)); // after this screen is gone (the room may be closing too)
    text.dispose();
    super.dispose();
  }

  Map<String, Object?>? memberByCn(int cn) => c.members.where((m) => m['cn'] == cn).firstOrNull;
  String nameOf(int cn) => (memberByCn(cn)?['display'] as String?) ?? '?';
  int get to => conv == 'all' ? -1 : int.parse(conv);

  void _send() {
    final t = text.text.trim();
    if (t.isEmpty) return;
    if (editing != null) {
      c.send({'t': 'edit', 'id': editing!['id'], 'text': t});
    } else {
      c.sendChat(to, t, reply: replyTo?['id'] as int?, mentions: mentions.where((cn) => t.contains('@${nameOf(cn)}')).toList());
    }
    setState(() { text.clear(); replyTo = null; editing = null; mentions.clear(); });
  }

  void _menu(Map<String, Object?> m) {
    final l = L.of(context), mine = m['from'] == c.myCn, sender = memberByCn(m['from'] as int);
    final canEdit = mine && c.serverNow - (m['at'] as int) < editWindowMs;
    showModalBottomSheet(context: context, backgroundColor: C.card, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
        for (var i = 0; i < reactions.length; i++)
          InkWell(key: Key('rx_$i'), onTap: () { Navigator.pop(ctx); c.send({'t': 'react', 'id': m['id'], 'rx': i}); },
              child: Padding(padding: const EdgeInsets.all(6), child: Text(reactions[i], style: const TextStyle(fontSize: 24)))),
      ])),
      ListTile(key: const Key('menuReply'), leading: const Icon(Icons.reply), title: Text(l.replyTo), onTap: () { Navigator.pop(ctx); setState(() => replyTo = m); }),
      if (canEdit) ListTile(key: const Key('menuEdit'), leading: const Icon(Icons.edit_outlined), title: Text(l.editMsg),
          onTap: () { Navigator.pop(ctx); setState(() { editing = m; replyTo = null; text.text = m['text'] as String; }); }),
      if (!mine && sender != null && widget.safety) ...[
        ListTile(key: const Key('menuReport'), leading: Icon(Icons.flag_outlined, color: C.red2), title: Text(l.report), onTap: () {
          Navigator.pop(ctx);
          reportDialog(context, widget.account, sender['uid'] as String, sender['display'] as String, room: c.code, msgId: m['id'] as int, text: m['text'] as String);
        }),
        ListTile(key: const Key('menuBlock'), leading: Icon(Icons.block, color: C.red2), title: Text(l.block), onTap: () async {
          Navigator.pop(ctx);
          if (await confirmBlock(context, widget.account, sender['uid'] as String, sender['display'] as String)) setState(() {});
        }),
      ],
    ])));
  }

  Future<void> _pickMention() async {
    final l = L.of(context);
    final who = c.members.where((m) => m['cn'] != c.myCn && (conv == 'all' || '${m['cn']}' == conv)).toList();
    final cn = await showModalBottomSheet<int>(context: context, backgroundColor: C.card, builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
      Padding(padding: const EdgeInsets.all(12), child: Text(l.mention, style: head.copyWith(fontSize: 18))),
      for (final m in who) ListTile(key: Key('mention_${m['cn']}'), title: Text(m['display'] as String), onTap: () => Navigator.pop(ctx, m['cn'] as int)),
    ])));
    if (cn == null) return;
    mentions.add(cn);
    setState(() => text.text = '${text.text}${text.text.isEmpty || text.text.endsWith(' ') ? '' : ' '}@${nameOf(cn)} ');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) {
        final l = L.of(context), msgs = c.messages(conv), pending = c.outbox.entries.where((e) => '${e.value['to'] == -1 ? 'all' : e.value['to']}' == conv).toList();
        final others = c.members.where((m) => m['cn'] != c.myCn).toList();
        return Scaffold(
          appBar: AppBar(backgroundColor: C.bg, title: Text(l.chatT, style: head.copyWith(fontSize: 20))),
          body: Column(children: [
            SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              _convChip(l.everyone, 'all'),
              for (final m in others) _convChip(m['display'] as String, '${m['cn']}'),
            ])),
            if (widget.out && conv == 'all') Container(width: double.infinity, color: C.card2, padding: const EdgeInsets.all(8),
                child: Text(l.outOnlyNote, key: const Key('outOnly'), textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 12))),
            Expanded(child: msgs.isEmpty && pending.isEmpty
                ? Center(child: Text(l.noMessages, style: TextStyle(color: C.mute)))
                : ListView(reverse: true, padding: const EdgeInsets.all(12), children: [
                    for (final e in pending.reversed) _bubble(l, {...e.value, 'from': c.myCn}, cid: e.key),
                    for (final m in msgs.reversed) _bubble(l, m),
                  ])),
            if (replyTo != null || editing != null)
              Container(color: C.card2, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Row(children: [
                Icon(editing != null ? Icons.edit_outlined : Icons.reply, size: 18, color: C.mute),
                const SizedBox(width: 8),
                Expanded(child: Text(editing != null ? l.editMsg : '${nameOf(replyTo!['from'] as int)}: ${replyTo!['text']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute))),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() { replyTo = null; if (editing != null) { editing = null; text.clear(); } })),
              ])),
            SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 8), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(key: const Key('mentionBtn'), tooltip: l.mention, icon: Icon(Icons.alternate_email, color: C.mute), onPressed: _pickMention),
              Expanded(child: TextField(key: const Key('chatText'), controller: text, maxLength: 200, minLines: 1, maxLines: 4,
                  textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: l.typeMsg))),
              ListenableBuilder(listenable: text, builder: (context, _) => IconButton(key: const Key('chatSend'), // S12-6: dimmed while empty
                  icon: Icon(editing != null ? Icons.check : Icons.send, color: text.text.trim().isEmpty ? C.dim : C.red2), onPressed: text.text.trim().isEmpty ? null : _send)),
            ]))),
          ]),
        );
      });

  Widget _convChip(String label, String key) {
    final n = c.unread[key] ?? 0;
    return Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: ChoiceChip(
      key: Key('conv_$key'),
      label: Text(n > 0 ? '$label ($n)' : label),
      selected: conv == key,
      onSelected: (_) { setState(() { conv = key; replyTo = null; }); c.openConversation(key); },
    ));
  }

  Widget _bubble(L l, Map<String, Object?> m, {String? cid}) {
    final mine = m['from'] == c.myCn;
    final reply = m['reply'] == null ? null : c.chat[m['reply'] as int];
    final rx = ((m['rx'] as Map?) ?? const {}).entries.where((e) => (e.value as List).isNotEmpty).toList();
    final failed = cid != null && c.outbox[cid]?['failed'] == true;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: mine ? C.red : C.alt, borderRadius: BorderRadius.circular(C.neon ? 10 : 3),
          boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(2, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (!mine) Text(nameOf(m['from'] as int).toUpperCase(), style: head.copyWith(fontSize: 12, color: C.red, letterSpacing: 1)),
        if (reply != null) Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.all(6), color: Colors.black12,
            child: Text('${nameOf(reply['from'] as int)}: ${reply['text']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: mine ? C.priText : C.altText))),
        Text(m['text'] as String, textDirection: dirOf(m['text'] as String), style: TextStyle(color: mine ? C.priText : C.altText, fontSize: 15)),
        if (m['edited'] == true || cid != null)
          Text(cid == null ? l.edited : failed ? l.notSent : l.sending, key: cid == null ? null : Key('state_$cid'),
              style: TextStyle(fontSize: 11, color: failed ? const Color(0xFFFFD0C8) : (mine ? C.priText : C.altText).withValues(alpha: .7))),
        if (rx.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 4, children: [
          for (final e in rx) Text('${reactions[int.parse('${e.key}')]} ${(e.value as List).length}', style: TextStyle(fontSize: 12, color: mine ? C.priText : C.altText)),
        ])),
      ]),
    );
    final w = GestureDetector(
      key: Key('msg_${m['id'] ?? cid}'),
      onLongPress: cid == null ? () => _menu(m) : null,
      onTap: failed ? () => c.retryChat(cid) : cid == null ? () => _menu(m) : null, // S12-6: a tap opens the menu (Telegram)
      child: bubble,
    );
    // [N3] swipe anywhere on the message's line, either direction, to reply; [R5] the message follows the finger (Telegram)
    return SwipeReply(
      key: Key('row_${m['id'] ?? cid}'),
      onReply: cid == null ? () => setState(() => replyTo = m) : null,
      child: Align(alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart, child: w),
    );
  }
}

/// [R5] A message line that slides with a horizontal drag (at most [max] px), a reply arrow fading in behind it; past
/// [at] px it ticks, and letting go there replies. It springs back either way.
class SwipeReply extends StatefulWidget {
  const SwipeReply({super.key, required this.child, this.onReply});
  final Widget child;
  final VoidCallback? onReply; // null: not swipeable (a message still sending)
  static const at = 56.0, max = 72.0;
  @override
  State<SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply> {
  double dx = 0;
  bool dragging = false;

  void _end() {
    if (dx.abs() >= SwipeReply.at) widget.onReply?.call();
    setState(() { dx = 0; dragging = false; });
  }

  @override
  Widget build(BuildContext context) {
    final p = (dx.abs() / SwipeReply.at).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: widget.onReply == null ? null : (_) => setState(() => dragging = true),
      onHorizontalDragUpdate: widget.onReply == null ? null : (d) {
        final was = dx.abs() >= SwipeReply.at;
        setState(() => dx = (dx + d.delta.dx).clamp(-SwipeReply.max, SwipeReply.max));
        if (!was && dx.abs() >= SwipeReply.at) HapticFeedback.selectionClick();
      },
      onHorizontalDragEnd: widget.onReply == null ? null : (_) => _end(),
      onHorizontalDragCancel: widget.onReply == null ? null : _end,
      child: Stack(alignment: Alignment.center, children: [
        if (dx != 0) Positioned.fill(child: Align(
          alignment: dx < 0 ? Alignment.centerRight : Alignment.centerLeft,
          child: Opacity(opacity: p, child: Transform.scale(scale: .6 + .4 * p, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CircleAvatar(radius: 15, backgroundColor: C.card2, child: Icon(Icons.reply, size: 18, color: p >= 1 ? C.red2 : C.mute))))))),
        AnimatedContainer(
          duration: dragging ? Duration.zero : const Duration(milliseconds: 180), curve: Curves.easeOutBack,
          transform: Matrix4.translationValues(dx, 0, 0),
          child: SizedBox(width: double.infinity, child: widget.child)),
      ]),
    );
  }
}
