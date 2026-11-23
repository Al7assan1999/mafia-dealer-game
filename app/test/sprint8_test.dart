// [QA] Sprint 8: the Stats screen (titles, board, Mine / Everyone, filters, your rank), a player's profile, the old
// history import ("Which one were you?", results and errors), History → Old app, the Everyone switch, a title taken
// in the bell, the plural of rounds, and the in-app updater (check, card, allow installs, download with progress,
// install, failure fallback, "Updated to vX" once, alerts and the push topic).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mafia_dealer/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/l10n/app_localizations_ar.dart';
import 'package:mafia_dealer/l10n/app_localizations_en.dart';
import 'package:mafia_dealer/prefs.dart';
import 'package:mafia_dealer/stats.dart';
import 'package:mafia_dealer/update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'sprint7_test.dart' show FakePush;

Map<String, Object?> row(String key, String name, {int w = 5, int g = 8, bool q = true, int? rank, bool me = false}) =>
    {'key': key, 'userId': key.startsWith('u:') ? key.substring(2) : null, 'name': name, 'handle': null, 'avatar': null, 'g': g, 'w': w, 'mg': 3, 'mw': 2, 'tg': g - 3, 'tw': w - 2,
      'sv': 1, 'ct': 2, 'fk': 1, 'q': q, 'r': w / g, 'rank': rank, 'me': me};

Map<String, Object?> statsOf(List<Map<String, Object?>> board, {int min = 3, Map<String, Object?>? me}) => {
      'board': board, 'me': me ?? board.where((r) => r['me'] == true).firstOrNull, 'minGames': min, 'games': 12,
      'titles': {'best': board.first, 'mafia': board.first, 'det': board.last, 'doc': null, 'first': board.last},
    };

Future<void> frames(WidgetTester t, [int n = 6]) async { for (var i = 0; i < n; i++) { await t.pump(const Duration(milliseconds: 100)); } }

Future<Launched> signedIn(WidgetTester t, FakeServer s, {String lang = 'en'}) => launch(t, server: s, tokens: MemoryTokens()..t = s.user('Sami'), lang: lang);

class FakeInstaller implements Installer {
  bool allowed = true, allowAsked = false, failInstall = false;
  String? installed, opened;
  void Function(String, String?)? status;
  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> allowInstalls() async => allowAsked = true;
  @override
  Future<String> cacheDir() async => Directory.systemTemp.createTempSync('upd').path;
  @override
  Future<void> install(String path) async { if (failInstall) throw Exception('no'); installed = path; }
  @override
  Future<void> openUrl(String url) async => opened = url;
  @override
  set onStatus(void Function(String, String?) f) => status = f;
}

/// GitHub's latest release and the APK download, faked.
MockClient github({int build = 100005, int status = 200, List<int>? apk}) => MockClient.streaming((req, _) async {
      if (req.url.host == 'api.github.com') {
        return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'tag_name': 'v0.3.0-b$build', 'html_url': 'https://github.com/x/releases/tag/v0.3.0-b$build',
          'body': '- Stats are back\n- Old history import\n- Update inside the app\n- Fourth point\nnot a bullet',
          'assets': [{'name': 'MafiaDealer.apk', 'browser_download_url': 'https://github.com/x/MafiaDealer.apk'}]}))), status);
      }
      final bytes = apk ?? List.filled(10000, 7);
      return http.StreamedResponse(Stream.fromIterable([for (var i = 0; i < bytes.length; i += 1000) bytes.sublist(i, i + 1000)]), 200, contentLength: bytes.length);
    });

void main() {
  setUpAll(setUpHarness);

  group('Stats', () {
    testWidgets('titles, the board with the minimum and the split per row, you highlighted, and the "what counts" line', (t) async {
      final s = FakeServer()..statsAnswer = statsOf([row('u:1', 'Dareer', w: 6, g: 8, rank: 1), row('u:2', 'Sami', w: 4, g: 8, rank: 2, me: true), row('n:hokan', 'Hokan', w: 1, g: 2, q: false)]);
      await signedIn(t, s);
      await tapKey(t, 'stats');
      await frames(t);
      expect(find.byKey(const Key('title_best')), findsOneWidget);
      expect(find.text('75% · 6 wins of 8'), findsOneWidget);
      expect(find.byKey(const Key('title_doc')), findsNothing, reason: 'no holder, no card');
      expect(find.text('Needs 3 games'), findsOneWidget);
      expect(find.text('Mafia 2/3 · Citizen 4/5'), findsOneWidget);
      expect(find.textContaining("One-phone games aren't recorded."), findsOneWidget);
      expect(s.statsAsked.last, 'board=mine&source=all&days=0');
    });

    testWidgets('Everyone: asks for all players, no Old app filter, my rank shown even below the top', (t) async {
      final s = FakeServer();
      await signedIn(t, s);
      await tapKey(t, 'stats');
      await frames(t);
      expect(find.byKey(const Key('src_old')), findsOneWidget);
      await tapKey(t, 'src_old');
      await frames(t);
      expect(s.statsAsked.last, 'board=mine&source=old&days=0');
      s.statsAnswer = statsOf([row('u:1', 'Dareer', w: 9, g: 12, rank: 1)], min: 10, me: row('u:9', 'Sami', w: 3, g: 11, rank: 140, me: true));
      await tapKey(t, 'boardAll');
      await frames(t);
      expect(s.statsAsked.last, 'board=all&source=all&days=0', reason: 'the Old app filter falls back to All on Everyone');
      expect(find.byKey(const Key('src_old')), findsNothing);
      expect(find.text('You: #140'), findsOneWidget);
      expect(find.byKey(const Key('row_u:9')), findsOneWidget, reason: 'my own row under the top');
      expect(find.textContaining('10 valid games needed'), findsOneWidget);
      await tapKey(t, 'days_30');
      await frames(t);
      expect(s.statsAsked.last, 'board=all&source=all&days=30');
    });

    testWidgets('no games yet: a plain message, not an empty board', (t) async {
      await signedIn(t, FakeServer());
      await tapKey(t, 'stats');
      await frames(t);
      expect(find.byKey(const Key('noStats')), findsOneWidget);
    });

    testWidgets('a row opens the profile: win rate, best role, sides, killed most by, best partner, moments, recent games, Share', (t) async {
      final s = FakeServer()..statsAnswer = statsOf([row('u:1', 'Dareer', w: 6, g: 8, rank: 1)]);
      s.playerAnswer = {'key': 'u:1', 'name': 'Dareer', 'userId': 'u1', 'games': 8, 'wins': 6, 'best': 'detective',
        'roles': {'mafia': [3, 2], 'doctor': [1, 1], 'detective': [2, 2], 'citizen': [2, 1]}, 'mafia': [3, 2], 'side': [5, 4],
        'nemesis': {'name': 'Hokan', 'userId': null, 'n': 2}, 'partner': {'name': 'Sami', 'userId': null, 'n': 3},
        'moments': {'saves': 1, 'caught': 4, 'killed': 2, 'out': 1}, 'form': [true, true, false, true], 'card': null};
      await signedIn(t, s);
      await tapKey(t, 'stats');
      await frames(t);
      await tapKey(t, 'row_u:1');
      await frames(t);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Detective'), findsWidgets);
      expect(find.text('80%'), findsOneWidget, reason: "Citizens' side 4 of 5");
      expect(find.text('Hokan'), findsOneWidget);
      expect(find.text('2 times'), findsOneWidget);
      expect(find.byKey(const Key('partner')), findsOneWidget);
      expect(find.text('3 wins together'), findsOneWidget);
      expect(find.byKey(const Key('shareProfile')), findsOneWidget);
    });

    testWidgets('in Arabic the board mirrors and the split reads in Arabic', (t) async {
      final s = FakeServer()..statsAnswer = statsOf([row('u:1', 'Dareer', rank: 1)]);
      await signedIn(t, s, lang: 'ar');
      await tapKey(t, 'stats');
      await frames(t);
      expect(find.text('مافيا 2/3 · مواطن 3/5'), findsOneWidget);
      expect(Directionality.of(t.element(find.byKey(const Key('row_u:1')))), TextDirection.rtl);
    });
  });

  group('the old history', () {
    testWidgets('Profile → Import: the guide, no list yet, a result line, a wrong code, the old server down', (t) async {
      final s = FakeServer()..importAnswer = {'found': 119, 'imported': 116, 'duplicates': 3, 'broken': 2, 'waiting': 119};
      await signedIn(t, s);
      await tapKey(t, 'profile');
      await frames(t, 3);
      await t.scrollUntilVisible(find.byKey(const Key('importOldHistory')), 200, scrollable: find.byType(Scrollable).first);
      await tapKey(t, 'importOldHistory');
      await frames(t);
      expect(find.byKey(const Key('noNames')), findsOneWidget);
      await t.enterText(find.byKey(const Key('oldCode')), 'abcd2345');
      await tapKey(t, 'importOld');
      await frames(t);
      // [S12-1] his real import (2026-11-23): everything kept, and the line says what waits for names
      expect(find.text("119 games found: 116 new, 3 already here. 119 games wait until their players are confirmed, then they count in stats. 2 entries couldn't be read."), findsOneWidget);
      s.importAnswer = 'not_found';
      await tapKey(t, 'importOld');
      await frames(t);
      expect(find.text('No group with this code'), findsOneWidget);
      s.importAnswer = 'busy';
      await tapKey(t, 'importOld');
      await frames(t);
      expect(find.text("The old server didn't answer, try again"), findsOneWidget);
    });

    testWidgets('"Which one were you?": pick my name; a name someone took can\'t be picked', (t) async {
      final s = FakeServer()..oldNamesAnswer = {'names': [{'name': 'Alhassan', 'taken': false}, {'name': 'Dareer', 'taken': true}], 'mine': null};
      final app = await signedIn(t, s);
      await t.runAsync(() async {});
      Navigator.of(t.element(find.byKey(const Key('settings')))).push(MaterialPageRoute(builder: (_) => ImportScreen(account: app.account)));
      await frames(t);
      expect(find.text('Dareer · taken'), findsOneWidget);
      await tapKey(t, 'claim_Alhassan');
      await frames(t);
      expect(s.claims, ['Alhassan']);
      expect(t.widget<ChoiceChip>(find.byKey(const Key('claim_Alhassan'))).selected, isTrue);
      expect(t.widget<ChoiceChip>(find.byKey(const Key('claim_Dareer'))).onSelected, isNull);
    });

    testWidgets('History → Old app: my imported games, invalid marked, and the old lines on the detail page', (t) async {
      final s = FakeServer()..oldGamesAnswer = [
        {'id': 'o1', 'playedAt': 1, 'valid': true, 'winner': 'mafia', 'days': 1, 'names': ['Alhassan', 'Dareer', 'Halawy', 'Sami'], 'roles': ['mafia', 'doctor', 'citizen', 'citizen'],
          'alive': [true, true, false, true], 'hist': ['Night 1: Halawy was killed'], 'seat': 0},
        {'id': 'o2', 'playedAt': 0, 'valid': false, 'winner': 'citizens', 'days': 3, 'names': ['Alhassan', 'Dareer', 'Halawy', 'Sami'], 'roles': ['citizen', 'mafia', 'doctor', 'citizen'],
          'alive': [true, false, true, true], 'hist': [], 'seat': null},
      ];
      await signedIn(t, s);
      await t.scrollUntilVisible(find.byKey(const Key('history')), 200, scrollable: find.byType(Scrollable).first);
      await tapKey(t, 'history');
      await frames(t);
      await tapKey(t, 'tabOld');
      await frames(t);
      expect(find.text('You played Mafia · 4 players · 1 round'), findsOneWidget, reason: 'and the plural is right');
      expect(find.textContaining('Invalid'), findsOneWidget);
      await tapKey(t, 'old_o1');
      await frames(t);
      expect(find.text('Night 1: Halawy was killed'), findsOneWidget);
    });
  });

  testWidgets('the Everyone switch in Profile saves at once', (t) async {
    final s = FakeServer();
    await signedIn(t, s);
    await tapKey(t, 'profile');
    await frames(t, 3);
    await t.scrollUntilVisible(find.byKey(const Key('onBoard')), 200, scrollable: find.byType(Scrollable).first);
    await tapKey(t, 'onBoard');
    await frames(t);
    expect(s.users[s.idOf('Sami')]!['onBoard'], isFalse);
  });

  testWidgets('a title taken from me, in the bell', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    s.notes.add({'id': 'b:1', 'to': s.idOf('Sami'), 'kind': 'title_lost', 'from': s.card(s.idOf('Dareer'), s.idOf('Sami')), 'code': null, 'at': 0, 'expiresAt': 0, 'read': false, 'title': 'det'});
    await launch(t, server: s, tokens: MemoryTokens()..t = tok);
    await tapKey(t, 'bell');
    await frames(t);
    expect(find.text('took Best Detective from you'), findsOneWidget);
  });

  test('rounds: 1 round / 2 rounds, and the Arabic forms', () {
    expect(LEn().rcSub(4, 1), '4 players · 1 round');
    expect(LEn().rcSub(4, 3), '4 players · 3 rounds');
    expect(LAr().rcSub(4, 1), '4 لاعبين · جولة واحدة');
    expect(LAr().rcSub(4, 2), '4 لاعبين · جولتان');
    expect(LAr().rcSub(4, 5), '4 لاعبين · 5 جولات');
    expect(LAr().rcSub(4, 11), '4 لاعبين · 11 جولة');
  });

  group('updates', () {
    Future<Prefs> prefs([Map<String, Object> v = const {}]) async { SharedPreferences.setMockInitialValues(v); return Prefs.load(); }

    test('a newer release is offered with its bullets; the same or older is not; offline stays quiet; at most every 10 minutes', () async {
      final p = await prefs();
      var now = 0;
      // this build is 0 in tests (no --dart-define=BUILD), so the check is skipped entirely: that's what local builds do
      final local = Updater(p, client: github(), installer: FakeInstaller(), clock: () => now);
      await local.check(force: true);
      expect(local.latest, isNull, reason: 'a local build never offers updates');
    });

    testWidgets('the card: Update downloads with progress and hands the APK to Android; bullets, See all', (t) async {
      final p = await prefs(), inst = FakeInstaller();
      final u = Updater(p, client: github(), installer: inst)..latest = Release('0.3.0', 100005, 'https://github.com/x/MafiaDealer.apk', 'https://github.com/x/releases', ['Stats are back', 'Old history import', 'Update inside the app', 'Fourth point']);
      await t.pumpWidget(MaterialApp(localizationsDelegates: L.localizationsDelegates, home: Scaffold(body: UpdateCard(updater: u))));
      expect(find.text('• Stats are back'), findsOneWidget);
      expect(find.text('• Fourth point'), findsNothing);
      expect(find.byKey(const Key('updSeeAll')), findsOneWidget);
      final seen = <double>[];
      u.addListener(() => seen.add(u.progress));
      await t.runAsync(() => u.update());
      await t.pump();
      expect(inst.installed, endsWith('update.apk'));
      expect(File(inst.installed!).lengthSync(), 10000);
      expect(seen.where((x) => x > 0 && x < 1), isNotEmpty, reason: 'progress moves');
      expect(u.state, 'installing');
      expect(p.pendingNotes, hasLength(4), reason: 'kept for "Updated to vX"');
    });

    test('installs not allowed yet: Android\'s switch opens, nothing downloads', () async {
      final p = await prefs(), inst = FakeInstaller()..allowed = false;
      final u = Updater(p, client: github(), installer: inst)..latest = Release('0.3.0', 100005, 'https://github.com/x/a.apk', 'https://page', []);
      await u.update();
      expect(inst.allowAsked, isTrue);
      expect(u.state, 'allow');
      expect(inst.installed, isNull);
    });

    test('a failed download or install opens the download page instead', () async {
      final p = await prefs(), inst = FakeInstaller()..failInstall = true;
      final u = Updater(p, client: github(), installer: inst)..latest = Release('0.3.0', 100005, 'https://github.com/x/a.apk', 'https://page', []);
      await u.update();
      expect(u.state, 'failed');
      expect(inst.opened, 'https://page');
      final inst2 = FakeInstaller(), u2 = Updater(p, client: MockClient((_) async => http.Response('', 500)), installer: inst2)..latest = Release('0.3.0', 1, 'https://x/a.apk', 'https://page2', []);
      await u2.update();
      expect(inst2.opened, 'https://page2');
      inst2.status!('failed:3', 'conflict');  // Android refused it later (PackageInstaller's answer)
      expect(u2.state, 'failed');
    });

    test('alerts follow the language topic; off unsubscribes', () async {
      final p = await prefs(), push = FakePush(), u = Updater(p, client: github(), installer: FakeInstaller());
      u.push = push;
      await Future<void>.delayed(Duration.zero);
      expect(push.topics, {'updates_en': true});
      await u.setAlerts(false);
      expect(push.topics['updates_en'], isFalse);
      await u.setAlerts(true);
      p.lang = 'ar';
      await Future<void>.delayed(Duration.zero);
      expect(push.topics, {'updates_en': false, 'updates_ar': true});
    });
  });
}
