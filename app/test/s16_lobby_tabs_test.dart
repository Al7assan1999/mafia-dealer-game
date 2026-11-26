// [BA] S16-1 (docs/sprint-16-prd.md): the side tabs covered the ⋮ menus (and could cover the role steppers) in a lobby.
// One file per Sprint 16 change, so each can be reverted on its own.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'online_test.dart' show frames, openRoom, roomMsg;

void main() {
  setUpAll(setUpHarness);

  // [1.1.1 hotfix, his note] reverted: the cards use the whole width again and the tabs float over them; a tab over a
  // ⋮ menu is dragged out of the way
  testWidgets('lobby: the cards use the whole width; the side tab drags off whatever it covers', (t) async {
    final r = (await openRoom(t)).room;
    r.last.push(roomMsg(1));
    r.last.push({'t': 'view', 'rev': 1, 'view': null});
    await frames(t);
    final chat = find.byKey(const Key('chat')), menus = find.byType(PopupMenuButton<String>);
    expect(t.getRect(menus.first).right, greaterThan(t.getRect(chat).left), reason: 'no gutter kept for the tabs');
    final y0 = t.getTopLeft(chat).dy;
    await t.drag(chat, const Offset(0, 300));
    await frames(t);
    expect(t.getTopLeft(chat).dy, greaterThan(y0 + 200));
  });
}
