// [1.3.1, his note] The modes section is folded to the chosen mode; it opens with a tap and folds again after a pick.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/features/offline/setup_screen.dart';
import 'package:mafia_engine/mafia_engine.dart' show modes;

import 'harness.dart';
import 's17_modes_test.dart' show openModes, pumpHome, tapIn;

void main() {
  setUpAll(setUpHarness);

  testWidgets('folded: only the chosen mode; open: every mode; a pick folds it to the new one; Hide folds it too', (t) async {
    await pumpHome(t, (p) => SetupScreen(prefs: p, audio: Audio(p)));
    expect(find.byKey(const Key('mode_classic')), findsOneWidget);
    for (final m in modes.where((m) => m != 'classic')) { expect(find.byKey(Key('mode_$m')), findsNothing); }
    expect(find.text('Change'), findsOneWidget);
    await openModes(t);
    for (final m in modes) { expect(find.byKey(Key('mode_$m')), findsOneWidget); }
    await tapIn(t, 'mode_avenger');
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('modesList')), findsNothing, reason: 'a pick folds the list');
    expect(find.byKey(const Key('mode_avenger')), findsOneWidget);
    expect(find.byKey(const Key('mode_classic')), findsNothing);
    await openModes(t);
    await tapIn(t, 'modesToggle');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('modesList')), findsNothing, reason: 'Hide folds it');
    expect(find.byKey(const Key('mode_avenger')), findsOneWidget, reason: 'still Avenger');
  });
}
