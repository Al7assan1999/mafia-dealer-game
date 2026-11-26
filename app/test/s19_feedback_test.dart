// Sprint 19 (1.2.0): the suggestions box (docs/sprint-19-prd.md): send with one screenshot (S19-1), the limits said
// before typing (S19-2), "My messages" (P3), the admin's box (S19-3), Mark done (P1), a game attached (P2).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/features/account/profile_screen.dart';
import 'package:mafia_dealer/features/feedback/feedback_screen.dart';
import 'package:mafia_dealer/features/history/game_detail.dart';
import 'package:mafia_dealer/features/settings/settings_sheet.dart';
import 'package:mafia_dealer/state/active_room.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'hotfix_room_test.dart' show recap, withGame;
import 'online_test.dart' show frames, openRoom, roomMsg, view;

Future<Launched> _open(WidgetTester t, FakeServer s, String tok, Widget Function(Launched a) page, {String lang = 'en', Size size = const Size(393, 851), double text = 1}) async {
  final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true}, lang: lang, size: size, text: text);
  ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => page(a)));
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await frames(t);
  return a;
}

void main() {
  setUpAll(setUpHarness);

  testWidgets('S19-1: a problem with one screenshot (shrunk to ≤ 1280 px and 300 KB), sent with the phone details', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await _open(t, s, tok, (a) => FeedbackScreen(account: a.account));
    await t.tap(find.byKey(const Key('fbProblem')));
    await t.enterText(find.byKey(const Key('fbText')), 'short');
    await tapKey(t, 'fbSend');
    await frames(t);
    expect(find.text('Write at least 10 characters'), findsOneWidget);
    expect(s.feedback, isEmpty);
    final big = img.encodePng(img.Image(width: 2400, height: 3600)..clear(img.ColorRgb8(20, 90, 200)));
    FeedbackScreen.testPicker = () async => Uint8List.fromList(big);
    addTearDown(() => FeedbackScreen.testPicker = null);
    await t.runAsync(() async { await t.tap(find.byKey(const Key('fbShot'))); await Future<void>.delayed(const Duration(seconds: 3)); });
    await frames(t);
    expect(find.byKey(const Key('fbShotPreview')), findsOneWidget);
    expect(find.byKey(const Key('fbShotRemove')), findsOneWidget);
    await t.enterText(find.byKey(const Key('fbText')), 'The vote froze on my phone');
    await t.runAsync(() async { await t.tap(find.byKey(const Key('fbSend'))); await Future<void>.delayed(const Duration(milliseconds: 300)); });
    await frames(t);
    expect(s.feedback, hasLength(1));
    final f = s.feedback.single;
    expect(f['kind'], 'problem');
    expect((f['info'] as Map).keys, containsAll(['app', 'build', 'lang', 'os']));
    final shot = base64Decode((f['image'] as String).split(',').last), pic = img.decodeJpg(shot)!;
    expect(shot.length, lessThanOrEqualTo(300000));
    expect([pic.width, pic.height], [853, 1280]);
    expect(find.byKey(const Key('fbText')), findsNothing, reason: 'the form closes after Send');
  });

  testWidgets('S19-2: over the limit it says so before typing, and offers no form; P3 lists what I sent', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.feedback.add({'id': 'f1', 'by': s.idOf('Sami'), 'kind': 'idea', 'text': 'A Medium role please', 'status': 'done', 'at': 1795700000000, 'shot': false, 'info': {}});
    s.feedbackBlocked = 'day';
    await _open(t, s, tok, (a) => FeedbackScreen(account: a.account));
    expect(find.text("You've sent a lot today; try again tomorrow"), findsOneWidget);
    expect(find.byKey(const Key('fbText')), findsNothing);
    expect(find.text('MY MESSAGES'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('mineStatus_f1'))).data, 'Done ✓');
  });

  testWidgets('S19-2 AC3: the box filled up while typing: the text stays, and it says why', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await _open(t, s, tok, (a) => FeedbackScreen(account: a.account));
    s.feedbackBlocked = 'full';
    await t.enterText(find.byKey(const Key('fbText')), 'Please add a Medium role');
    await t.runAsync(() async { await t.tap(find.byKey(const Key('fbSend'))); await Future<void>.delayed(const Duration(milliseconds: 300)); });
    await frames(t);
    expect(find.text('The box is full right now. Try again later.'), findsWidgets);
    expect(find.text('Please add a Medium role'), findsOneWidget, reason: 'nothing typed is lost');
  });

  testWidgets('S19-1 AC4: signed out, Settings offers sign-in instead', (t) async {
    final a = await launch(t, server: FakeServer(), stored: {'guideSeen': true});
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => SettingsSheet(prefs: a.prefs, account: a.account)));
    await frames(t);
    await t.scrollUntilVisible(find.byKey(const Key('feedback')), 200);
    expect(find.text('Sign in to send'), findsOneWidget);
  });

  testWidgets('S19-3, P1, P2: the admin opens one (with its game), marks it done, deletes, empties', (t) async {
    final s = FakeServer(), tok = s.user('Boss');
    s.user('Sami');
    s.admin = s.idOf('Boss');
    final sami = s.idOf('Sami'), shot = 'data:image/jpeg;base64,${base64Encode(img.encodeJpg(img.Image(width: 40, height: 80)))}';
    s.feedback.addAll([
      {'id': 'f1', 'by': sami, 'kind': 'problem', 'text': 'The vote froze on my phone', 'status': 'new', 'at': 1795700000000, 'shot': true, 'image': shot, 'gameId': 'g1',
        'info': {'app': '1.2.0', 'build': 100021, 'lang': 'ar', 'os': 'Android 14'}},
      {'id': 'f2', 'by': sami, 'kind': 'idea', 'text': 'A Medium role please', 'status': 'new', 'at': 1795700000001, 'shot': false, 'info': {}},
    ]);
    await _open(t, s, tok, (a) => FeedbackBoxScreen(account: a.account));
    expect(find.byKey(const Key('fb_f1')), findsOneWidget);
    await t.tap(find.byKey(const Key('fbProblems')));
    await frames(t);
    expect(find.byKey(const Key('fb_f2')), findsNothing, reason: 'the filter');
    await t.tap(find.byKey(const Key('fb_f1')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await frames(t);
    expect(find.byKey(const Key('fbItemShot')), findsOneWidget);
    expect(find.byKey(const Key('fbOpenGame')), findsOneWidget);
    expect(find.text('Sami'), findsOneWidget);
    expect(s.feedback.first['status'], 'read', reason: 'opened = read');
    await tapKey(t, 'fbMarkDone');
    await frames(t);
    expect(s.feedback.first['status'], 'done');
    expect(find.byKey(const Key('fbMarkDone')), findsNothing);
    await t.pump(const Duration(seconds: 3)); // the "Done" toast goes
    await tapKey(t, 'fbDelete');
    await t.tap(find.text('Delete').last);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await frames(t);
    expect(s.feedback.map((f) => f['id']), ['f2']);
    await tapKey(t, 'fbEmpty');
    expect(find.text('Delete all 1?'), findsOneWidget);
    await t.tap(find.text('Empty the box').last);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await frames(t);
    expect(s.feedback, isEmpty);
    expect(find.byKey(const Key('fbNone')), findsOneWidget);
  });

  testWidgets('P2: "about this game" is shown and the game goes with it', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await _open(t, s, tok, (a) => FeedbackScreen(account: a.account, gameId: 'g9'));
    expect(find.byKey(const Key('fbGame')), findsOneWidget);
    await t.enterText(find.byKey(const Key('fbText')), 'Wrong winner shown here');
    await t.runAsync(() async { await t.tap(find.byKey(const Key('fbSend'))); await Future<void>.delayed(const Duration(milliseconds: 300)); });
    expect(s.feedback.single, containsPair('gameId', 'g9'));
    expect(s.feedback.single, containsPair('kind', 'problem'));
  });

  for (final (lang, size, text) in [('ar', const Size(360, 640), 1.3), ('en', const Size(320, 568), 1.3)]) {
    testWidgets('S19-1 AC5: the form fits $lang ${size.width.toInt()}x${size.height.toInt()} x$text', (t) async {
      final s = FakeServer(), tok = s.user('Sami');
      await _open(t, s, tok, (a) => FeedbackScreen(account: a.account), lang: lang, size: size, text: text);
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('fbSend')), findsOneWidget);
    });
  }

  testWidgets('[Quin Q7, Q16] P2 on the end screen: a seated player gets "Report a problem with this game"; a spectator does not', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(withGame(roomMsg(1, status: 'game')));
    r.last.push(view(1, 'end', ph: 'end', extra: {'winner': 'citizens', 'recap': recap, 'roles': recap['roles']}));
    await frames(t, 40);
    expect(find.byKey(const Key('reportGame')), findsOneWidget);
    r.last.push(view(2, 'end', ph: 'end', extra: {'winner': 'citizens', 'recap': recap, 'roles': recap['roles'], 'seat': null}));
    await frames(t, 40);
    expect(find.byKey(const Key('reportGame')), findsNothing);
  });

  testWidgets('[Quin Q7, Q16] P2 in History: only on a game I played; it opens the form with the game attached', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    final me = s.idOf('Sami');
    Map<String, Object?> game(String? uid) => {'id': 'g1', 'winner': 'citizens', 'days': 1, 'valid': true, 'host': false, 'rules': {}, 'log': [], 'stats': null, 'sheikh': null,
      'players': [{'seat': 0, 'userId': uid, 'name': 'Sami', 'role': 'citizen', 'alive': true}, {'seat': 1, 'userId': null, 'name': 'X', 'role': 'mafia', 'alive': false}]};
    s.gameDetails['g1'] = game(me);
    s.gameDetails['g2'] = game(null);
    final a = await _open(t, s, tok, (a) => GameDetail(account: a.account, id: 'g2'));
    expect(find.byKey(const Key('reportGame')), findsNothing, reason: 'not my game (the admin opening one from the box)');
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => GameDetail(account: a.account, id: 'g1')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await frames(t);
    await tapKey(t, 'reportGame');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await frames(t);
    expect(find.byKey(const Key('fbGame')), findsOneWidget);
  });

  testWidgets('[Quin Q16] S19-3 AC1: the admin sees Suggestions with the unread count; a player does not see it', (t) async {
    final s = FakeServer(), tok = s.user('Boss');
    s.user('Sami');
    s.admin = s.idOf('Boss');
    s.feedback.add({'id': 'f1', 'by': s.idOf('Sami'), 'kind': 'idea', 'text': 'A Medium role please', 'status': 'new', 'at': 1795700000000, 'shot': false, 'info': {}});
    await _open(t, s, tok, (a) => ProfileScreen(account: a.account));
    await t.scrollUntilVisible(find.byKey(const Key('feedbackBox')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.descendant(of: find.byKey(const Key('feedbackBox')), matching: find.text('1')), findsOneWidget);
  });

  testWidgets('[Quin Q16] a player\'s profile has no Suggestions box', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await _open(t, s, tok, (a) => ProfileScreen(account: a.account));
    await t.scrollUntilVisible(find.byKey(const Key('accountId')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('feedbackBox')), findsNothing);
  });

  testWidgets('[Quin Q9] counted as the server counts: over 1000 characters is said on the phone', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await _open(t, s, tok, (a) => FeedbackScreen(account: a.account));
    await t.enterText(find.byKey(const Key('fbText')), '😀' * 1001);
    await tapKey(t, 'fbSend');
    await frames(t);
    expect(s.feedback, isEmpty);
  });
}
