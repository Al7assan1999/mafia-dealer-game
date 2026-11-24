// [QA] The click map: every control on every screen, tapped once from a fresh start, and what it did.
// Not part of the normal test run (it writes a report and takes minutes); CI runs it as a gate (no control may crash).
// Run:
//   flutter test tool/click_map_test.dart
// It writes docs/qa/click-map.md. Each screen is rebuilt from scratch before every tap, so one tap never changes the
// next. Against the fake server (the real server is covered by server/test and the emulator).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/core/ui.dart';

import '../test/driver.dart';
import '../test/fake_server.dart';
import '../test/harness.dart';
import '../test/online_test.dart' show FakeRoom, frames, member, openRoom, roomMsg, view, nightOpts;
import '../test/sprint8_test.dart' show row, statsOf;

/// One screen: how to get there (fresh each time), and the fake server / room to watch.
class Spot {
  Spot(this.name, this.open);
  final String name;
  final Future<({FakeServer? server, FakeRoom? room})> Function(WidgetTester t) open;
}

/// A signed-in phone with friends, a request, notes and stats to look at.
Future<FakeServer> richServer() async {
  final s = FakeServer()..statsAnswer = statsOf([row('u:2', 'Dareer', w: 9, g: 12, rank: 1), row('u:1', 'Sami', w: 7, g: 12, rank: 2, me: true)]);
  s.user('Sami');
  s.user('Dareer');
  s.user('Hokan');
  s.user('Fater');
  final me = s.idOf('Sami'), d = s.idOf('Dareer'), h = s.idOf('Hokan'), f = s.idOf('Fater');
  s.friends.add(me.compareTo(d) < 0 ? (me, d) : (d, me));
  s.users[d]!['st'] = 'lobby';
  s.users[d]!['op'] = true;
  s.friendships.add(me.compareTo(h) < 0 ? (me, h, h) : (h, me, h)); // Hokan asks me
  s.friendships.add(me.compareTo(f) < 0 ? (me, f, me) : (f, me, me)); // I asked Fater
  s.note(me, d, 'invite');
  s.notes.last['code'] = '654321';
  s.note(me, h, 'friend_request');
  return s;
}

Future<Launched> signedIn(WidgetTester t, FakeServer s) async {
  final a = await launch(t, server: s, tokens: MemoryTokens()..t = 'tu1', stored: {'guideSeen': true});
  await t.runAsync(a.account.loadFriends);
  await t.pump(const Duration(milliseconds: 500));
  return a;
}

Future<void> go(WidgetTester t, String key) async { await tapKey(t, key); await t.pump(const Duration(milliseconds: 600)); }

/// One step of an offline game, as the table would play it.
Future<void> step(WidgetTester t) async {
  final g = gameOf(t);
  switch (g.screen) {
    case Screen.dealPass || Screen.nightPass || Screen.ballotPass: await tapKey(t, 'open');
    case Screen.dealCard: await tapKey(t, 'memorized');
    case Screen.nightPick:
      final no = g.view(g.who).night!;
      if (no.key != 'none') await tapKey(t, 'opt_${no.opts.firstWhere((o) => !o.disabled).seat}');
      await tapKey(t, 'confirm');
    case Screen.nightLocked: await tapKey(t, 'nightNext');
    case Screen.ballotVoted: await tapKey(t, 'ballotNext');
    case Screen.dawn: await tapKey(t, 'dawn');
    case Screen.morning: await tapKey(t, g.revealed ? 'startDay' : 'revealNow');
    case Screen.verdict: await tapKey(t, g.revealed ? 'nextNight' : 'revealNow');
    case Screen.day: await tapKey(t, 'ballot');
    case Screen.ballotPick: await tapKey(t, 'opt_none'); await tapKey(t, 'castVote');
    case Screen.end: await tapKey(t, 'revealNow');
  }
  await t.pump(const Duration(milliseconds: 200));
}

Future<({FakeServer? server, FakeRoom? room})> offlineAt(WidgetTester t, bool Function(OfflineGame g) here) async {
  await launch(t, stored: {'guideSeen': true});
  await setUpGame(t, ['Dareer', 'Halawy', 'Farouq', 'Sami', 'Hokan']);
  for (var i = 0; i < 300 && !here(gameOf(t)); i++) { await step(t); }
  await t.pump(const Duration(milliseconds: 500));
  return (server: null, room: null);
}

Future<({FakeServer? server, FakeRoom? room})> room(WidgetTester t, {bool host = true, Map<String, Object?>? v, bool chat = false}) async {
  final r = (await openRoom(t)).room;
  r.last.push(roomMsg(1, host: host, members: [member(0, host: host), member(1, host: !host), member(2), member(3)]));
  r.last.push(v ?? {'t': 'view', 'rev': 1, 'view': null});
  final now = DateTime.now().millisecondsSinceEpoch;
  r.last.push({'t': 'chatAll', 'msgs': [{'id': 1, 'from': 2, 'to': -1, 'text': 'Who is lying here?', 'at': now}, {'id': 2, 'from': 1, 'to': -1, 'text': 'Not me', 'at': now}]});
  await frames(t);
  if (chat) await go(t, 'chat');
  return (server: null, room: r);
}

final spots = <Spot>[
  Spot('Home (signed out, first launch)', (t) async { await launch(t); return (server: null, room: null); }),
  Spot('Home (signed in)', (t) async { final s = await richServer(); await signedIn(t, s); return (server: s, room: null); }),
  Spot('Settings (signed in)', (t) async { final s = await richServer(); await signedIn(t, s); await go(t, 'settings'); return (server: s, room: null); }),
  Spot('Sign in', (t) async { final a = await launch(t, stored: {'guideSeen': true}); await go(t, 'signIn'); return (server: a.server, room: null); }),
  Spot('My profile', (t) async { final s = await richServer(); await signedIn(t, s); await go(t, 'profile'); return (server: s, room: null); }),
  Spot('Friends', (t) async { final s = await richServer(); await signedIn(t, s); await openFriends(t); await t.pump(const Duration(milliseconds: 600)); return (server: s, room: null); }),
  Spot('Friends → Requests', (t) async { final s = await richServer(); await signedIn(t, s); await openFriends(t); await t.pump(const Duration(milliseconds: 600)); await go(t, 'tabRequests'); return (server: s, room: null); }),
  Spot('A friend\'s profile (no games)', (t) async { final s = await richServer(); await signedIn(t, s); await openFriends(t); await t.pump(const Duration(milliseconds: 600)); await go(t, 'friendStats_Dareer'); return (server: s, room: null); }),
  Spot('The bell', (t) async { final s = await richServer(); await signedIn(t, s); await go(t, 'bell'); return (server: s, room: null); }),
  Spot('Friends drawer', (t) async { final s = await richServer(); await signedIn(t, s); await go(t, 'friendsTab'); return (server: s, room: null); }),
  Spot('Stats', (t) async { final s = await richServer(); await signedIn(t, s); await go(t, 'stats'); return (server: s, room: null); }),
  Spot('Game history', (t) async { final s = await richServer(); await signedIn(t, s); await go(t, 'history'); return (server: s, room: null); }),
  Spot('Online', (t) async { final s = await richServer(); await signedIn(t, s); await go(t, 'online'); return (server: s, room: null); }),
  Spot('Wi-Fi / Hotspot', (t) async { final a = await launch(t, stored: {'guideSeen': true}); await go(t, 'wifi'); return (server: a.server, room: null); }),
  Spot('How to play', (t) async { await launch(t, stored: {'guideSeen': true}); await go(t, 'howToPlay'); return (server: null, room: null); }),
  Spot('Offline setup', (t) async { await launch(t, stored: {'guideSeen': true}); await go(t, 'newGame'); return (server: null, room: null); }),
  Spot('Offline: pass the phone (deal)', (t) => offlineAt(t, (g) => g.screen == Screen.dealPass)),
  Spot('Offline: night pick', (t) => offlineAt(t, (g) => g.screen == Screen.nightPick)),
  Spot('Offline: day', (t) => offlineAt(t, (g) => g.screen == Screen.day)),
  Spot('Offline: ballot pick', (t) => offlineAt(t, (g) => g.screen == Screen.ballotPick)),
  Spot('Online lobby (host)', (t) => room(t)),
  Spot('Online lobby (player)', (t) => room(t, host: false)),
  Spot('Online: night pick', (t) => room(t, v: view(2, 'night', ph: 'night', extra: {'night': nightOpts}))),
  Spot('Online: day (host)', (t) => room(t, v: view(2, 'day'))),
  Spot('Room chat', (t) => room(t, chat: true)),
];

// ------------------------------------------------------------------ finding the controls
const _compound = <Type>{IconButton, ListTile, PopupMenuButton, Switch, SwitchListTile, Checkbox, Slider, TextField, Chip, ChoiceChip, FilterChip, DropdownButton, BackButton};
bool _isCompound(Widget w) => _compound.contains(w.runtimeType) || w is ButtonStyleButton || w is DropdownButton || w is PopupMenuButton || w is TextField;

bool _control(Widget w) =>
    (w is InkWell && (w.onTap != null || w.onLongPress != null)) ||
    (w is IconButton && w.onPressed != null) ||
    (w is ButtonStyleButton && w.onPressed != null) ||
    (w is GestureDetector && (w.onTap != null || w.onLongPress != null || w.onHorizontalDragEnd != null)) ||
    (w is Switch && w.onChanged != null) || (w is Slider && w.onChanged != null) || (w is Checkbox && w.onChanged != null) ||
    (w is ListTile && (w.onTap != null || w.onLongPress != null)) || w is PopupMenuButton || w is TextField || w is DropdownButton;

/// The controls a player can actually reach: on stage, not inside another control's own parts, and hit by a tap.
List<Element> controls(WidgetTester t) {
  final out = <Element>[], rects = <Rect>[];
  for (final e in find.byWidgetPredicate(_control).evaluate()) {
    var inside = false, depth = 0;
    e.visitAncestorElements((a) {
      if (depth++ > 80) return false;
      if (_isCompound(a.widget) && !(e.widget is ButtonStyleButton && a.widget is SegmentedButton)) { inside = true; return false; }
      return true;
    });
    if (inside) continue;
    final ro = e.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    // covered by a sheet, a dialog or the drawer: not reachable (on screen but another layer takes the tap)
    final view = t.view.physicalSize / t.view.devicePixelRatio;
    if ((Offset.zero & view).contains(r.center) && !t.hitTestOnBinding(r.center).path.any((h) => h.target == ro)) continue;
    // one control is several nested tap widgets (a button = InkWell + GestureDetector): keep the outermost of a spot
    if (rects.any((x) => (x.topLeft - r.topLeft).distance < 2 && (x.size.width - r.size.width).abs() < 2 && (x.size.height - r.size.height).abs() < 2)) continue;
    rects.add(r);
    out.add(e);
  }
  return out;
}

String? keyNear(Element e) {
  String? k = e.widget.key is ValueKey ? '${(e.widget.key as ValueKey).value}' : null;
  var depth = 0;
  if (k == null) e.visitAncestorElements((a) { if (depth++ > 4) return false; if (a.widget.key is ValueKey<String>) { k = (a.widget.key as ValueKey<String>).value; return false; } return true; });
  return k;
}

String labelOf(WidgetTester t, Element e) {
  final w = e.widget, k = keyNear(e);
  final texts = <String>[];
  void walk(Element x) {
    final y = x.widget;
    if (y is Text && (y.data ?? y.textSpan?.toPlainText() ?? '').trim().isNotEmpty) texts.add((y.data ?? y.textSpan!.toPlainText()).trim());
    if (texts.length < 3) x.visitChildElements(walk);
  }
  walk(e);
  String? tip;
  if (w is IconButton) tip = w.tooltip;
  final sem = e.findRenderObject()?.debugSemantics?.label;
  final words = [?tip, if (texts.isNotEmpty) texts.take(2).join(' / '), if (tip == null && texts.isEmpty && sem != null && sem.isNotEmpty) sem].join(' · ');
  final kind = switch (w) {
    IconButton() => 'icon button', ButtonStyleButton() => 'button', Switch() => 'switch', Slider() => 'slider', Checkbox() => 'checkbox',
    ListTile() => 'row', PopupMenuButton() => 'menu ⋮', TextField() => 'text field', DropdownButton() => 'dropdown',
    GestureDetector() => 'gesture area', _ => 'tap area' };
  final l = words.isEmpty ? '(no label)' : words.replaceAll('\n', ' ').replaceAll('|', '/');
  return '$kind: ${l.length > 70 ? '${l.substring(0, 67)}…' : l}${k != null ? ' `$k`' : ''}';
}

// ------------------------------------------------------------------ what a tap did
class Sig {
  Sig(WidgetTester t) {
    final scaffolds = find.byType(Scaffold).evaluate().toList();
    route = scaffolds.isEmpty ? null : ModalRoute.of(scaffolds.last);
    final bars = find.byType(AppBar).evaluate().toList();
    title = bars.isEmpty ? null : _firstText(bars.last);
    dialogs = find.byType(Dialog).evaluate().length + find.byType(AlertDialog).evaluate().length;
    sheets = find.byType(BottomSheet).evaluate().length;
    menus = find.byWidgetPredicate((w) => w is PopupMenuItem || w is DropdownMenuItem).evaluate().length;
    snack = find.byType(SnackBar).evaluate().map(_firstText).whereType<String>().join(' ');
    texts = {for (final e in find.byType(Text).evaluate()) ((e.widget as Text).data ?? '').trim()}..remove('');
    states = [
      for (final e in find.byType(Switch).evaluate()) 'sw${(e.widget as Switch).value}',
      for (final e in find.byType(Slider).evaluate()) 'sl${(e.widget as Slider).value}',
      for (final e in find.byType(Checkbox).evaluate()) 'cb${(e.widget as Checkbox).value}',
      for (final e in find.byType(EditableText).evaluate()) 'ed${(e.widget as EditableText).focusNode.hasFocus}${(e.widget as EditableText).controller.text}',
      for (final e in find.byType(Icon).evaluate()) 'ic${(e.widget as Icon).icon?.codePoint}',
      for (final e in find.byWidgetPredicate((w) => w is SegmentedButton).evaluate()) 'sg${(e.widget as SegmentedButton).selected}',
      'neon${C.neon}',
    ].join(',');
  }
  Route<dynamic>? route;
  String? title, snack;
  late int dialogs, sheets, menus;
  late Set<String> texts;
  late String states;
}

String? _firstText(Element e) {
  String? r;
  void walk(Element x) { if (r != null) return; final w = x.widget; if (w is Text && (w.data ?? '').trim().isNotEmpty) { r = w.data!.trim(); return; } x.visitChildElements(walk); }
  walk(e);
  return r;
}

String describe(Sig a, Sig b, List<String> calls, List<Map<String, Object?>> sent, Object? error) {
  final out = <String>[];
  if (error != null) {
    final s = '$error'.split('\n').first;
    out.add(s.contains('MissingPlugin') || s.contains('PlatformException') ? 'opens a system screen / phone feature (share, photos, Android settings…)' : '**ERROR: ${s.length > 90 ? s.substring(0, 90) : s}**');
  }
  if (b.dialogs > a.dialogs) out.add('opens a dialog «${_dialogTitle() ?? ''}»');
  if (b.sheets > a.sheets) out.add('opens a sheet');
  if (b.menus > a.menus && b.route == a.route) out.add('opens a menu');
  if (b.dialogs < a.dialogs || b.sheets < a.sheets) out.add('closes it');
  if (b.route != a.route && b.dialogs == a.dialogs && b.sheets == a.sheets) out.add(b.title != null ? 'opens «${b.title}»' : 'changes screen');
  if (b.snack != null && b.snack!.isNotEmpty && b.snack != a.snack) out.add('says «${b.snack}»');
  if (b.states != a.states && b.route == a.route && b.dialogs == a.dialogs && b.sheets == a.sheets) out.add('changes a setting, a selection or an icon');
  if (calls.isNotEmpty) out.add('calls ${calls.toSet().take(3).join(', ')}');
  if (sent.isNotEmpty) out.add('sends ${sent.map((m) => m['t']).toSet().join(', ')} to the room');
  if (out.isEmpty) {
    final added = b.texts.difference(a.texts), gone = a.texts.difference(b.texts);
    if (added.isNotEmpty || gone.isNotEmpty) out.add('updates the screen${added.isEmpty ? '' : ': «${added.take(2).join('», «')}»'}');
  }
  return out.isEmpty ? '❓ nothing visible' : out.join('; ');
}

String? _dialogTitle() {
  final d = [...find.byType(AlertDialog).evaluate(), ...find.byType(Dialog).evaluate()];
  return d.isEmpty ? null : _firstText(d.last);
}

Future<void> reset(WidgetTester t) async {
  ActiveRoom.instance.leave();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

final report = StringBuffer();
var total = 0, nothing = 0, errors = 0;

void main() {
  setUpAll(setUpHarness);
  tearDownAll(() {
    final head = StringBuffer()
      ..writeln('# [QA] Click map: every control on every screen (v0.4.0)')
      ..writeln()
      ..writeln('Generated by `app/tool/click_map_test.dart` on ${DateTime.now().toIso8601String().substring(0, 16)}. Each control was tapped once,')
      ..writeln('on a freshly opened screen (English, 393×851, fake server). **$total controls on ${spots.length} screens; '
          '$errors errors; $nothing with nothing visible** (❓: QA checked each one by hand, see the QA report).')
      ..writeln();
    File('../docs/qa/click-map.md').writeAsStringSync('$head$report');
  });

  for (final s in spots) {
    testWidgets('click map: ${s.name}', (t) async {
      await reset(t);
      await s.open(t);
      final n = controls(t).length;
      final rows = <String>[];
      for (var i = 0; i < n; i++) {
        await reset(t);
        final env = await s.open(t);
        final cs = controls(t);
        if (i >= cs.length) break;
        final e = cs[i], label = labelOf(t, e);
        final f = find.byElementPredicate((x) => x == e);
        try { await t.ensureVisible(f); await t.pump(const Duration(milliseconds: 300)); } catch (_) {}
        final before = Sig(t), calls0 = env.server?.calls.length ?? 0, sent0 = env.room?.last.msgs.length ?? 0;
        Object? error;
        try {
          if (e.widget is TextField) { await t.tap(f, warnIfMissed: false); } else { await t.tap(f, warnIfMissed: false); }
          for (var k = 0; k < 6; k++) { await t.pump(const Duration(milliseconds: 150)); }
        } catch (x) { error = x; }
        error ??= t.takeException();
        final after = Sig(t);
        final calls = env.server == null ? <String>[] : env.server!.calls.sublist(calls0);
        final sent = env.room == null ? <Map<String, Object?>>[] : env.room!.last.msgs.sublist(sent0);
        final what = describe(before, after, calls, sent, error);
        total++;
        if (what.startsWith('❓')) nothing++;
        if (what.contains('ERROR')) errors++;
        rows.add('| ${i + 1} | $label | $what |');
      }
      report
        ..writeln('## ${s.name} ($n)')
        ..writeln()
        ..writeln('| # | Control | What the tap did |')
        ..writeln('| --- | --- | --- |')
        ..writeAll(rows.map((r) => '$r\n'))
        ..writeln();
      await reset(t);
      await t.pump(const Duration(minutes: 1));
      // P1 (Sprint 12): CI runs this; a control that throws fails the build
      expect(rows.where((r) => r.contains('**ERROR')), isEmpty, reason: 'controls that crashed on ${s.name}');
    }, semanticsEnabled: true);
  }
}

