// 1.2.1 hotfix: no Old tab or filter (the old app's games are in Online); a profile is the same from everywhere.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show frames;
import 'sprint8_test.dart' show row, signedIn, statsOf;

void main() {
  setUpAll(setUpHarness);

  testWidgets('Stats: no Old filter; a row opens the same profile whatever the board shows', (t) async {
    final s = FakeServer()..statsAnswer = statsOf([row('u:1', 'Dareer', rank: 1)]);
    await signedIn(t, s);
    await tapKey(t, 'stats');
    await frames(t);
    expect(find.byKey(const Key('src_old')), findsNothing);
    expect(find.byKey(const Key('src_online')), findsOneWidget);
    await tapKey(t, 'src_wifi');
    await frames(t);
    await tapKey(t, 'days_30');
    await frames(t);
    expect(s.statsAsked.last, 'source=wifi&days=30');
    await tapKey(t, 'row_u:1');
    await frames(t);
    expect(s.playerAsked.last, 'key=u%3A1&source=all&days=0', reason: 'as from History: every game, all time');
  });

  testWidgets('History: two tabs; old games I played sit with the online ones by date, marked, and open their page', (t) async {
    final s = FakeServer()
      ..games = [{'id': 'n1', 'winner': 'citizens', 'days': 2, 'valid': true, 'playedAt': 300, 'seat': 0, 'role': 'doctor', 'alive': true, 'players': 5, 'names': ['Sami', 'A', 'B', 'C', 'D']}]
      ..oldGamesAnswer = [
        {'id': 'o1', 'playedAt': 200, 'valid': true, 'status': 'counted', 'winner': 'mafia', 'days': 1, 'names': ['Sami', 'Dareer', 'Halawy', 'Fater'],
          'roles': ['mafia', 'doctor', 'citizen', 'citizen'], 'alive': [true, true, false, true], 'hist': ['Night 1: Halawy was killed'], 'seat': 0},
        {'id': 'o2', 'playedAt': 400, 'valid': true, 'status': 'counted', 'winner': 'mafia', 'days': 1, 'names': ['Dareer', 'Halawy', 'Fater', 'Wessam'],
          'roles': ['mafia', 'doctor', 'citizen', 'citizen'], 'alive': [true, true, true, true], 'hist': [], 'seat': null},
      ];
    await signedIn(t, s);
    await t.scrollUntilVisible(find.byKey(const Key('history')), 200, scrollable: find.byType(Scrollable).first);
    await tapKey(t, 'history');
    await frames(t);
    expect(find.byKey(const Key('tabOld')), findsNothing);
    expect(find.byType(Tab), findsNWidgets(2));
    expect(find.byKey(const Key('game_o2')), findsNothing, reason: "the admin's list had every old game; Online has mine");
    expect(find.text('2 GAMES'), findsOneWidget);
    double y(String k) => t.getTopLeft(find.byKey(Key(k))).dy;
    expect(y('game_n1') < y('game_o1'), isTrue, reason: 'newest first');
    expect(find.text('You played Mafia · 4 players · 1 round · Old app'), findsOneWidget);
    await tapKey(t, 'game_o1');
    await frames(t);
    expect(find.text('Night 1: Halawy was killed'), findsOneWidget);
  });

  testWidgets('[Quin Q4] old games that fail to load say so; Try again brings them', (t) async {
    final s = FakeServer()
      ..games = [{'id': 'n1', 'winner': 'citizens', 'days': 2, 'valid': true, 'playedAt': 300, 'seat': 0, 'role': 'doctor', 'alive': true, 'players': 5, 'names': ['Sami', 'A', 'B', 'C', 'D']}]
      ..oldGamesDown = true
      ..oldGamesAnswer = [{'id': 'o1', 'playedAt': 200, 'valid': true, 'status': 'counted', 'winner': 'mafia', 'days': 1, 'names': ['Sami', 'Dareer', 'Halawy', 'Fater'],
        'roles': ['mafia', 'doctor', 'citizen', 'citizen'], 'alive': [true, true, false, true], 'hist': [], 'seat': 0}];
    await signedIn(t, s);
    await t.scrollUntilVisible(find.byKey(const Key('history')), 200, scrollable: find.byType(Scrollable).first);
    await tapKey(t, 'history');
    await frames(t);
    expect(find.byKey(const Key('game_n1')), findsOneWidget, reason: 'the online games show anyway');
    expect(find.text("Your old app games didn't load."), findsOneWidget);
    s.oldGamesDown = false;
    await tapKey(t, 'oldRetry');
    await frames(t);
    expect(find.byKey(const Key('oldFailed')), findsNothing);
    expect(find.byKey(const Key('game_o1')), findsOneWidget);
  });
}
