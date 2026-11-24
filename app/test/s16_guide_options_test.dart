// [BA] S16-3 (docs/sprint-16-prd.md): the old guide's "Options in this app", as the setup's own rules card (read only).
// One file per Sprint 16 change, so each can be reverted on its own.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/ui.dart' show SqSwitchTile;
import 'package:mafia_dealer/features/guide/guide_screen.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

import 'harness.dart';
import 'online_test.dart' show frames;

void main() {
  setUpAll(setUpHarness);

  testWidgets('How to Play shows the game options read only: Classic, and every option on a tap', (t) async {
    await t.pumpWidget(MaterialApp(localizationsDelegates: L.localizationsDelegates, home: const GuideScreen()));
    await frames(t, 2);
    await t.scrollUntilVisible(find.byKey(const Key('rulesToggle')), 300);
    expect(find.byKey(const Key('guideOptions')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('rulesPreset'))).data, 'Classic');
    await t.tap(find.byKey(const Key('rulesToggle')));
    await frames(t, 2);
    await t.scrollUntilVisible(find.text('Mafia can skip a kill'), 200);
    for (final sw in t.widgetList<SqSwitchTile>(find.byType(SqSwitchTile))) { expect(sw.onChanged, isNull, reason: 'nothing changes from the guide'); }
  });
}
