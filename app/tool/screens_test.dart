// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
// Renders the real screens to images for the [BA] player walkthrough and the [QA] UX pass (docs/team-workflow.md).
// Not part of the normal test run. Run:
//   flutter test --update-goldens tool/screens_test.dart
// The images land in build/screens/ (git-ignored): <lang>_<nn>_<screen>.png at a small phone (360x640).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/account.dart';
import 'package:mafia_dealer/game.dart';

import '../test/driver.dart';
import '../test/fake_server.dart';
import '../test/harness.dart';
import '../test/online_test.dart' show FakeRoom, member, nightOpts, openRoom, roomMsg, view;

Future<void> shot(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 500));
  await expectLater(find.byWidgetPredicate((w) => w is MaterialApp).first, matchesGoldenFile('../build/screens/$name.png'));
}

void main() {
  setUpAll(() async {
    await setUpHarness();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(File('${Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/WGN/sdk/flutter'}/bin/cache/artifacts/material_fonts/materialicons-regular.otf').readAsBytesSync())));
    await icons.load();
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('$lang: offline game, every screen', (t) async {
      await launch(t, size: const Size(360, 640), lang: lang);
      await shot(t, '${lang}_01_home');
      await tapKey(t, 'newGame');
      await t.pump(const Duration(milliseconds: 500));
      await shot(t, '${lang}_02_setup');
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 500));
      await setUpGame(t, ['Dareer', 'Halawy', 'Farouq', 'Sami', 'Hokan']);
      final seen = <String>{};
      for (var i = 0; i < 300; i++) {
        await t.pump(const Duration(milliseconds: 100));
        final g = gameOf(t), k = '${g.screen.name}${g.revealed ? '' : '_held'}';
        if (seen.add(k)) await shot(t, '${lang}_1${seen.length.toString().padLeft(2, '0')}_$k');
        switch (g.screen) {
          case Screen.dealPass || Screen.nightPass || Screen.ballotPass: await tapKey(t, 'open');
          case Screen.dealCard:
            final hold = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
            await t.pump(const Duration(milliseconds: 300));
            if (seen.add('card_held')) await shot(t, '${lang}_1${seen.length.toString().padLeft(2, '0')}_card_held');
            await hold.up();
            await t.pump();
            await tapKey(t, 'memorized');
          case Screen.nightPick:
            final no = g.view(g.who).night!;
            if (no.key != 'none') await tapKey(t, 'opt_${no.opts.firstWhere((o) => !o.disabled).seat}');
            await tapKey(t, 'confirm');
          case Screen.nightLocked: await tapKey(t, 'nightNext');
          case Screen.ballotVoted: await tapKey(t, 'ballotNext');
          case Screen.dawn: await tapKey(t, 'dawn');
          case Screen.morning: await tapKey(t, g.revealed ? 'startDay' : 'revealNow');
          case Screen.verdict: await tapKey(t, g.revealed ? 'nextNight' : 'revealNow');
          case Screen.day:
            if (g.s.day == 1) { await tapKey(t, 'ballot'); } else { await tapKey(t, 'decideTogether'); await shot(t, '${lang}_199_deciding'); await tapKey(t, 'opt_none'); await tapKey(t, 'decide'); }
          case Screen.ballotPick: await tapKey(t, 'opt_none'); await tapKey(t, 'castVote');
          case Screen.end:
            if (!g.revealed) { await tapKey(t, 'revealNow'); continue; }
            await t.pump(const Duration(milliseconds: 500));
            if (seen.add('end_shown')) await shot(t, '${lang}_1${seen.length.toString().padLeft(2, '0')}_end');
            await t.pumpWidget(const SizedBox());
            return;
        }
      }
    });

    testWidgets('$lang: account and friends', (t) async {
      final s = FakeServer(), tok = s.user('Sami');
      s.user('Hokan');
      s.user('Dareer');
      final me = s.idOf('Sami'), d = s.idOf('Dareer');
      s.friendships.add(me.compareTo(d) < 0 ? (me, d, d) : (d, me, d));
      s.friends.add(me.compareTo(s.idOf('Hokan')) < 0 ? (me, s.idOf('Hokan')) : (s.idOf('Hokan'), me));
      s.note(me, d, 'friend_request');
      await launch(t, size: const Size(360, 640), lang: lang, server: s, tokens: MemoryTokens()..t = tok);
      await t.pump(const Duration(seconds: 1));
      await shot(t, '${lang}_21_home_signed_in');
      await tapKey(t, 'friends');
      await shot(t, '${lang}_22_friends');
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 500));
      await tapKey(t, 'profile');
      await shot(t, '${lang}_23_profile');
      await t.scrollUntilVisible(find.byKey(const Key('blockedList')), 300, scrollable: find.byType(Scrollable).first);
      await shot(t, '${lang}_23b_profile_safety');
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 500));
      await tapKey(t, 'bell');
      await shot(t, '${lang}_24_bell');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('$lang: guide', (t) async {
      await launch(t, size: const Size(360, 640), lang: lang);
      await shot(t, '${lang}_03_home_guide_offer');
      await tapKey(t, 'openGuide');
      await shot(t, '${lang}_04_guide');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('$lang: sign-in', (t) async {
      await launch(t, size: const Size(360, 640), lang: lang);
      await tapKey(t, 'signIn');
      await shot(t, '${lang}_25_sign_in');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('$lang: online room', (t) async {
      final FakeRoom r = (await openRoom(t, size: const Size(360, 640), lang: lang)).room;
      r.last.push(roomMsg(1, members: [member(0, host: true), member(1, ready: true), member(2), member(3, online: false)]));
      r.last.push({'t': 'view', 'rev': 1, 'view': null});
      await shot(t, '${lang}_31_lobby');
      r.last.push(roomMsg(2, status: 'game', members: [member(0, host: true, seat: 0), member(1, seat: 1), member(2, seat: 2), member(3, seat: 3, online: false)]));
      r.last.push(view(2, 'night', ph: 'night', extra: {'night': nightOpts}));
      await shot(t, '${lang}_32_online_night');
      r.last.push(view(3, 'morning', extra: {'result': {'k': 'killed', 'seat': 2, 'role': 'citizen'}}));
      await shot(t, '${lang}_33_online_morning');
      r.last.push(view(4, 'day', extra: {'timer': {'left': 154}}));
      await shot(t, '${lang}_34_online_day_host');
      r.last.push(view(5, 'day', extra: {'timer': {'left': 154}, 'roster': [{'name': 'P1', 'alive': true}, {'name': 'P2', 'alive': true}, {'name': 'P3', 'alive': false}, {'name': 'P4', 'alive': true}]}));
      await shot(t, '${lang}_34b_online_day_roster');
      final now = DateTime.now().millisecondsSinceEpoch;
      r.last.push({'t': 'chatAll', 'msgs': [
        {'id': 1, 'from': 2, 'to': -1, 'text': lang == 'ar' ? 'من الذي يكذب؟' : 'Who is lying here?', 'at': now},
        {'id': 2, 'from': 1, 'to': -1, 'text': lang == 'ar' ? 'ليس أنا 😇' : 'Not me 😇', 'at': now, 'reply': 1, 'rx': {'0': ['u2'], '4': ['u3', 'u4']}},
        {'id': 3, 'from': 3, 'to': -1, 'text': '@P2 you voted weird yesterday', 'at': now, 'edited': true},
      ]});
      await tapKey(t, 'chat');
      await shot(t, '${lang}_36_chat');
      await t.longPress(find.byKey(const Key('msg_1')));
      await shot(t, '${lang}_37_chat_menu');
      await tapKey(t, 'menuReport');
      await shot(t, '${lang}_38_report');
      await t.tap(find.text(lang == 'ar' ? 'إلغاء' : 'Cancel'));
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 500));
      r.refuse = true;
      r.last.drop();
      await t.pump(const Duration(seconds: 4));
      await shot(t, '${lang}_35_connection_lost');
    });
  }
}
