// 1.1.1 hotfix, as the TypeScript engine (hotfix111.test.ts): an out seat follows the vote live, open or secret.
import 'dart:collection';

import 'package:mafia_engine/mafia_engine.dart';
import 'package:test/test.dart';

void main() {
  test('1.1.1: an out seat sees every vote as it comes in; a living seat only the count in a secret vote', () {
    final s = createGame(Setup([for (var i = 0; i < 6; i++) 'P${i + 1}'], const Counts(2, 1, 0), defaultRules), seeded(1)).state!
      ..phase = Phase.vote
      ..alive = [true, true, false, true, true, true]
      ..vote = Vote(7, false, SplayTreeMap.of({0: 3, 4: 'none'}));
    final out = viewFor(s, 2, 0), alive = viewFor(s, 3, 0);
    expect(out.ph, 'dead');
    expect(out.board, [(seat: 0, v: 3), (seat: 1, v: null), (seat: 3, v: null), (seat: 4, v: 'none'), (seat: 5, v: null)]);
    expect(alive.board, isNull, reason: 'a secret vote stays secret for the living');
    expect(viewFor(s, null, 0).board, isNull);
    expect(viewFor(s..phase = Phase.day..vote = null, 2, 0).board, isNull, reason: 'only during the vote');
  });
}
