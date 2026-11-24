// [BA] S16-1 (docs/sprint-16-prd.md): the side tabs covered the ⋮ menus (and could cover the role steppers) in a lobby.
// One file per Sprint 16 change, so each can be reverted on its own.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'online_test.dart' show frames, openRoom, roomMsg;

void main() {
  setUpAll(setUpHarness);

  testWidgets('lobby: no ⋮ menu or role stepper sits under the side tabs, wherever the tab is dragged', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    await frames(t);
    final tab = t.getRect(find.byKey(const Key('chat')));
    final under = [...find.byType(PopupMenuButton<String>).evaluate(), ...find.byKey(const Key('plus_mafia')).evaluate()];
    expect(under, isNotEmpty);
    for (final e in under) {
      expect(t.getRect(find.byWidget(e.widget)).right, lessThanOrEqualTo(tab.left), reason: 'clear of the tab at any height');
    }
  });
}
