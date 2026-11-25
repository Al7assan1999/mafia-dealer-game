// 1.0.1 hotfixes (playtest): the host's Valid / Invalid at the end (a tick, and a note of what it means); an out host still runs the day and sees the morning;
// the host's Start doesn't skip everyone's role card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'driver.dart';
import 'harness.dart';
import 'online_test.dart' show openRoom, roomMsg, view, frames, member;

Map<String, Object?> recap = {'winner': 'citizens', 'day': 2, 'sheikh': 1, 'roles': ['doctor', 'mafia', 'citizen', 'citizen'], 'alive': [true, false, true, true],
  'stats': {'first': 2, 'kills': [0, 0, 0, 0], 'outs': [0, 0, 0, 0], 'saves': [0, 0, 0, 0], 'caught': []}};

Map<String, Object?> withGame(Map<String, Object?> m, {bool? valid}) => {...m, 'room': {...(m['room'] as Map), 'gameId': 'g1', 'valid': valid}};

void main() {
  setUpAll(setUpHarness);

  testWidgets('the end: the host marks the game Invalid, then Valid again', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(withGame(roomMsg(1, status: 'game'), valid: true));
    r.last.push(view(1, 'end', ph: 'end', extra: {'winner': 'citizens', 'recap': recap, 'roles': recap['roles']}));
    await frames(t, 40);
    expect(find.descendant(of: find.byKey(const Key('markValid')), matching: find.byIcon(Icons.check)), findsOneWidget);
    await tapKey(t, 'markInvalid');
    expect(r.last.msgs.last, {'t': 'mark', 'valid': false});
    expect(find.text("This game won't count in stats"), findsOneWidget);
    r.last.push(withGame(roomMsg(2, status: 'game'), valid: false));
    await frames(t);
    expect(find.descendant(of: find.byKey(const Key('markInvalid')), matching: find.byIcon(Icons.check)), findsOneWidget);
    await tapKey(t, 'markValid');
    expect(r.last.msgs.last, {'t': 'mark', 'valid': true});
  });

  testWidgets('an out host still runs the day timer and the votes, and sees the morning result', (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    r.last.push(roomMsg(1, status: 'game'));
    r.last.push(view(1, 'morning', ph: 'dead', extra: {'alive': false, 'result': {'k': 'killed', 'seat': 0, 'role': 'doctor'}}));
    await frames(t);
    expect(find.text('P1'), findsWidgets);
    expect(find.byKey(const Key('startDay')), findsOneWidget);
    r.last.push(view(2, 'day', ph: 'dead', extra: {'alive': false, 'timer': {'left': 180}}));
    await frames(t);
    await tapKey(t, 'timerGo');
    expect(r.last.msgs.last, {'t': 'timer', 'op': 'start'});
    expect(find.byKey(const Key('secretVote')), findsOneWidget);
    // while the others act at night, the out host still sees "You are out"
    r.last.push(view(3, 'night', ph: 'dead', extra: {'alive': false}));
    await frames(t);
    expect(find.text('You are out'), findsOneWidget);
  });

  testWidgets("the host's Start is not on the role card; once ready it asks before skipping the others' cards", (t) async {
    final r = (await openRoom(t, narrate: false)).room;
    final ms = [member(0, host: true, seat: 0), member(1, seat: 1), member(2, seat: 2), member(3, seat: 3)];
    r.last.push(roomMsg(1, status: 'game', members: ms, deal: 1));
    r.last.push(view(1, 'deal'));
    await frames(t);
    expect(find.byKey(const Key('memorized')), findsOneWidget);
    expect(find.byKey(const Key('start')), findsNothing);
    r.last.push(roomMsg(2, status: 'game', deal: 1, members: [member(0, host: true, seat: 0, ready: true), ...ms.skip(1)]));
    await frames(t);
    await tapKey(t, 'start');
    await t.tap(find.text('Cancel')); await frames(t);
    expect(r.last.msgs.where((m) => m['t'] == 'start'), isEmpty);
    await tapKey(t, 'start');
    await t.tap(find.text('Start now').last); await frames(t);
    expect(r.last.msgs.last, {'t': 'start'});
  });
}
