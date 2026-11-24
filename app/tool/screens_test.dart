// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
// Renders the real screens to images for the [BA] player walkthrough and the [QA] UX pass (docs/team-workflow.md).
// Not part of the normal test run. Run:
//   flutter test --update-goldens tool/screens_test.dart
// The images land in build/screens/ (git-ignored): <lang>_<nn>_<screen>.png at a small phone (360x640).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/features/intro/intro_screen.dart';

import '../test/driver.dart';
import '../test/fake_server.dart';
import '../test/harness.dart';
import '../test/sprint7_test.dart' show wifiRecord;
import '../test/sprint8_test.dart' show row, statsOf;
import 'package:mafia_dealer/features/stats/stats_screen.dart';
import 'package:mafia_dealer/features/old_history/import_screen.dart';
import 'package:mafia_dealer/features/update/updater.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/online_test.dart' show FakeRoom, member, nightOpts, openRoom, roomMsg, view;
import 'package:mafia_dealer/features/wifi/lan.dart';
import 'package:mafia_dealer/features/wifi/wifi_screen.dart';

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

    testWidgets('$lang: Sprint 7 (history, the bell with a Wi-Fi request, settings)', (t) async {
      final s = FakeServer(), tok = s.user('Sami');
      for (final h in ['Dareer', 'Hokan', 'Fater']) { s.user(h); }
      final me = s.idOf('Sami'), ids = [me, s.idOf('Dareer'), s.idOf('Hokan'), s.idOf('Fater')];
      s.wifiNote(me, s.idOf('Dareer'), 'wifi_confirm', {'request': 'r1', 'status': 'pending', 'reason': null, 'players': 4, 'winner': 'citizens',
        'playedAt': DateTime(2026, 11, 23).millisecondsSinceEpoch, 'seat': 0, 'role': 'doctor'});
      s.wifiNote(me, me, 'wifi_result', {'request': 'r2', 'status': 'approved', 'reason': null, 'players': 4, 'winner': 'citizens', 'playedAt': DateTime(2026, 11, 22).millisecondsSinceEpoch, 'seat': 0, 'role': 'mafia'});
      s.wifiGames = [{'id': 'w1', 'key': 'g2', 'status': 'pending', 'reason': null, 'playedAt': 2, 'players': 4, 'winner': 'citizens', 'host': true, 'waiting': 2, 'total': 4, 'gameId': null, 'seat': 0, 'role': 'mafia', 'record': null}];
      final app = await launch(t, size: const Size(360, 640), lang: lang, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
      final rec = wifiRecord(), names = ['A', 'B', 'C', 'D'];
      app.prefs.addWifiGame({'id': 'g1', 'record': rec, 'names': names, 'mySeat': 0, 'at': 1, 'code': '1', 'host': true, 'accounts': [me, ids[1], null, ids[3]]});
      app.prefs.addWifiGame({'id': 'g2', 'record': rec, 'names': names, 'mySeat': 0, 'at': 2, 'code': '1', 'host': true, 'accounts': ids});
      app.prefs.addWifiGame({'id': 'g3', 'record': rec, 'names': names, 'mySeat': 0, 'at': 3, 'code': '1', 'host': true, 'accounts': ids});
      await t.pump(const Duration(seconds: 1));
      await tapKey(t, 'bell');
      await shot(t, '${lang}_51_bell_wifi');
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 500));
      await t.scrollUntilVisible(find.byKey(const Key('history')), 200, scrollable: find.byType(Scrollable).first);
      await tapKey(t, 'history');
      await t.pump(const Duration(milliseconds: 500));
      await tapKey(t, 'tabWifi');
      await t.pump(const Duration(milliseconds: 500));
      await shot(t, '${lang}_52_history_wifi');
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 500));
      await tapKey(t, 'settings');
      await shot(t, '${lang}_53_settings');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('$lang: Sprint 8 (stats, profile, import, update card)', (t) async {
      final s = FakeServer()..statsAnswer = statsOf([row('u:1', 'Dareer', w: 9, g: 12, rank: 1), row('u:2', 'Sami', w: 7, g: 12, rank: 2, me: true), row('u:3', 'Halawy', w: 7, g: 12, rank: 2),
        row('n:hokan', 'Hokan', w: 1, g: 2, q: false)]);
      s.playerAnswer = {'key': 'u:1', 'name': 'Dareer', 'userId': 'u1', 'games': 12, 'wins': 9, 'best': 'detective',
        'roles': {'mafia': [3, 2], 'doctor': [2, 2], 'detective': [4, 4], 'citizen': [3, 1]}, 'mafia': [3, 2], 'side': [9, 7],
        'nemesis': {'name': 'Hokan', 'userId': null, 'n': 2}, 'partner': {'name': 'Sami', 'userId': null, 'n': 1},
        'moments': {'saves': 2, 'caught': 5, 'killed': 2, 'out': 1}, 'form': [true, true, false, true, true, true, false, true], 'card': null};
      final tok = s.user('Sami');
      final app = await launch(t, size: const Size(360, 640), lang: lang, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
      final u = Updater(app.prefs)..latest = Release('0.3.0', 100005, 'x', 'x', ['Stats are back', 'Import your old history', 'Updates inside the app', 'More']);
      final nav = Navigator.of(t.element(find.byKey(const Key('settings'))));
      nav.push(MaterialPageRoute(builder: (_) => Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [UpdateCard(updater: u)]))));
      await t.pump(const Duration(milliseconds: 600));
      await shot(t, '${lang}_61_update_card');
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => StatsScreen(account: app.account)));
      await t.pump(const Duration(seconds: 1));
      await shot(t, '${lang}_62_stats');
      await t.scrollUntilVisible(find.byKey(const Key('row_u:1')), 300, scrollable: find.byType(Scrollable).last);
      await tapKey(t, 'row_u:1');
      await t.pump(const Duration(seconds: 1));
      await shot(t, '${lang}_63_profile');
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(builder: (_) => ImportScreen(account: app.account)));
      await t.pump(const Duration(seconds: 1));
      await shot(t, '${lang}_64_import');
      await t.pumpWidget(const SizedBox());
    });

    for (final theme in ['noir', 'neon']) {
      testWidgets('$lang $theme: Sprint 10 the intro, each scene at its moment', (t) async {
        IntroScreen.ran = false;
        await launch(t, size: const Size(393, 851), lang: lang, stored: {'introAtStart': true, 'theme': theme});
        // (scene, when in it): dawn, CRACK!, the blood, the three roles, the title
        for (final (i, at) in [(1, 3.0), (2, 1.85), (3, 3.4), (4, 3.0), (5, 1.6), (6, 3.2), (7, 1.6)]) {
          for (var n = 0; n < (at * 10).round(); n++) { await t.pump(const Duration(milliseconds: 100)); }
          await expectLater(find.byWidgetPredicate((w) => w is MaterialApp).first, matchesGoldenFile('../build/screens/${lang}_${theme}_8${i}_intro.png'));
          if (i < 7) { await t.tap(find.byKey(const Key('intro'))); await t.pump(); }
        }
        await t.pumpWidget(const SizedBox());
      });

      testWidgets('$lang $theme: Sprint 9 (Home with the tab, the drawer, Settings, the room bar)', (t) async {
        final s = FakeServer(), tok = s.user('Sami');
        for (final h in ['Dareer', 'Hokan', 'Halawy']) { s.user(h); }
        final me = s.idOf('Sami');
        for (final h in ['Dareer', 'Halawy']) { final d = s.idOf(h); s.friends.add(me.compareTo(d) < 0 ? (me, d) : (d, me)); }
        final h = s.idOf('Hokan');
        s.friendships.add(me.compareTo(h) < 0 ? (me, h, h) : (h, me, h));
        await launch(t, size: const Size(360, 640), lang: lang, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true, 'theme': theme});
        await t.pump(const Duration(seconds: 1));
        await shot(t, '${lang}_${theme}_71_home');
        await t.scrollUntilVisible(find.byKey(const Key('history')), 200, scrollable: find.byType(Scrollable).first);
        await shot(t, '${lang}_${theme}_72_home_tiles');
        await tapKey(t, 'friendsTab');
        await t.pump(const Duration(milliseconds: 600));
        await shot(t, '${lang}_${theme}_73_drawer');
        await t.tapAt(Offset(lang == 'ar' ? 350 : 10, 300)); // the dimmed side (the drawer opens from the left in Arabic)
        await t.pump(const Duration(milliseconds: 600));
        await tapKey(t, 'settings');
        await t.pump(const Duration(milliseconds: 600));
        await shot(t, '${lang}_${theme}_74_settings');
        await t.scrollUntilVisible(find.byKey(const Key('kickMode')), 200, scrollable: find.byType(Scrollable).last);
        await shot(t, '${lang}_${theme}_75_settings_host');
        await t.pumpWidget(const SizedBox());
      });

      testWidgets('$lang $theme: lobby and a game screen', (t) async {
        final r = (await openRoom(t, lang: lang, size: const Size(360, 640))).room;
        final p = await SharedPreferences.getInstance();
        await p.setString('theme', theme);
        C.p = theme == 'neon' ? neonPalette : noirPalette;
        r.last.push(roomMsg(1));
        r.last.push({'t': 'view', 'rev': 1, 'view': null});
        await t.pump(const Duration(seconds: 1));
        await shot(t, '${lang}_${theme}_76_lobby');
        r.last.push(view(2, 'night', ph: 'night', extra: {'night': nightOpts}));
        await t.pump(const Duration(seconds: 1));
        await shot(t, '${lang}_${theme}_77_night');
        C.p = noirPalette;
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('$lang: History signed out', (t) async {
      final app = await launch(t, size: const Size(360, 640), lang: lang, stored: {'guideSeen': true});
      app.prefs.addWifiGame({'id': 'g1', 'record': wifiRecord(), 'names': ['A', 'B', 'C', 'D'], 'mySeat': 1, 'at': 1, 'code': '1', 'host': false, 'accounts': [null, null, null, null]});
      await t.scrollUntilVisible(find.byKey(const Key('history')), 200, scrollable: find.byType(Scrollable).first);
      await tapKey(t, 'history');
      await t.pump(const Duration(milliseconds: 500));
      await shot(t, '${lang}_54_history_signed_out');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('$lang: Wi-Fi', (t) async {
      WifiScreen.testAddresses = ['192.168.43.20'];
      WifiScreen.testScan = () async => [FoundRoom('192.168.43.1', '482913', 'Sami', 4, 'lobby'), FoundRoom('192.168.43.7', '119034', 'Hokan', 7, 'game')];
      addTearDown(() { WifiScreen.testScan = null; WifiScreen.testAddresses = null; });
      final app = await launch(t, size: const Size(360, 640), lang: lang, stored: {'guideSeen': true, 'lanJoin': '{"address":"192.168.43.1","code":"482913","name":"Sami"}'});
      await shot(t, '${lang}_05_home_wifi');
      await tapKey(t, 'wifi');
      await shot(t, '${lang}_41_wifi_found');
      WifiScreen.testScan = () async => [];
      await tapKey(t, 'searchAgain');
      await shot(t, '${lang}_42_wifi_nothing');
      app.prefs.addWifiGame({'id': 'none'});
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
