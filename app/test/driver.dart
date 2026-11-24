// Plays the offline game through the real UI, like a table of players would: shared by the widget tests (fake time)
// and the emulator test (real time).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/features/offline/game_screen.dart';
import 'package:mafia_engine/mafia_engine.dart';

OfflineGame gameOf(WidgetTester t) => (t.state(find.byType(GameScreen)) as dynamic).game as OfflineGame;

/// Pumps until [f] finds something (up to [seconds]).
Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 20}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (f.evaluate().isNotEmpty) return;
    await t.pump(const Duration(milliseconds: 100));
  }
  throw TestFailure('not found: $f');
}

/// Tap every button twice (a nervous player), to prove a second tap never acts again.
bool doubleTaps = false;

/// Every (screen, seat) the driver saw, in order: to check nobody was skipped.
final seen = <(Screen, int)>[];

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await waitFor(t, f);
  await t.pump(const Duration(milliseconds: 400)); // let a page or sheet finish sliding in
  if (f.evaluate().isEmpty) return; // the screen moved on by itself meanwhile (a reveal timer)
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  if (doubleTaps) await t.tap(f, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 50));
}

/// Fills the setup with [names] and deals.
Future<void> setUpGame(WidgetTester t, List<String> names) async {
  await tapKey(t, 'newGame');
  await waitFor(t, find.byKey(const Key('deal')));
  await t.pump(const Duration(milliseconds: 400));
  for (var i = 6; i < names.length; i++) { await tapKey(t, 'addPlayer'); }
  for (var i = 5; i >= names.length; i--) { await tapKey(t, 'remove$i'); }
  for (var i = 0; i < names.length; i++) {
    final f = find.byKey(Key('name$i'));
    await t.ensureVisible(f);
    await t.enterText(f, names[i]);
  }
  await t.pump();
  await tapKey(t, 'deal');
  await waitFor(t, find.byType(GameScreen));
}

/// Plays from wherever the game is to the end. Votes for a Mafia when it can (so games end), by table decision on
/// even days and by secret ballot on odd days. Returns the number of screens passed.
Future<int> playToEnd(WidgetTester t) async {
  var screens = 0;
  for (; screens < 400; screens++) {
    await t.pump(const Duration(milliseconds: 100));
    final g = gameOf(t), s = g.s;
    if (seen.isEmpty || seen.last != (g.screen, g.who)) seen.add((g.screen, g.who));
    int? mafiaAlive() { for (final i in aliveSeats(s)) { if (s.roles[i] == Role.mafia) return i; } return null; }
    switch (g.screen) {
      case Screen.dealPass || Screen.nightPass || Screen.ballotPass:
        await tapKey(t, 'open');
      case Screen.dealCard:
        final card = find.byKey(const Key('roleCard'));
        await waitFor(t, card);
        final hold = await t.startGesture(t.getCenter(card));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('roleName')), findsOneWidget, reason: 'the role shows while held');
        await hold.up();
        await t.pump();
        expect(find.byKey(const Key('roleName')), findsNothing, reason: 'and hides on release');
        await tapKey(t, 'memorized');
      case Screen.nightPick:
        final no = g.view(g.who).night!;
        if (no.key != 'none') await tapKey(t, 'opt_${no.opts.firstWhere((o) => !o.disabled).seat}');
        await tapKey(t, 'confirm');
      case Screen.nightLocked:
        await tapKey(t, 'nightNext');
      case Screen.ballotVoted:
        await tapKey(t, 'ballotNext');
      case Screen.dawn:
        await tapKey(t, 'dawn');
      case Screen.morning:
        if (!g.revealed) { await tapKey(t, 'revealNow'); } else { await tapKey(t, 'startDay'); }
      case Screen.verdict:
        if (!g.revealed) { await tapKey(t, 'revealNow'); } else { await tapKey(t, 'nextNight'); }
      case Screen.day:
        final m = mafiaAlive();
        if (s.day.isOdd) {
          await tapKey(t, 'ballot');
        } else {
          await tapKey(t, 'decideTogether');
          await tapKey(t, 'opt_${m ?? 'none'}');
          await tapKey(t, 'decide');
        }
      case Screen.ballotPick:
        final m = mafiaAlive();
        await tapKey(t, m != null && m != g.who ? 'opt_$m' : 'opt_none');
        await tapKey(t, 'castVote');
      case Screen.end:
        if (!g.revealed) { await tapKey(t, 'revealNow'); continue; }
        await waitFor(t, find.byKey(const Key('playAgain')));
        return screens;
    }
  }
  throw TestFailure('the game did not end');
}
