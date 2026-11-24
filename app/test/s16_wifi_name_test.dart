// [BA] S16-2 (docs/sprint-16-prd.md): the old Wi-Fi screen's "Your name" card, with its tip for a guest.
// One file per Sprint 16 change, so each can be reverted on its own.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/features/wifi/wifi_screen.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show frames;

void main() {
  setUpAll(setUpHarness);
  setUp(() {
    WifiScreen.testAddresses = ['192.168.43.20'];
    WifiScreen.testScan = () async => [];
  });
  tearDown(() { WifiScreen.testScan = null; WifiScreen.testAddresses = null; });

  testWidgets('Wi-Fi: the name in its own card; a guest gets the sign-in tip', (t) async {
    await launch(t, stored: {'guideSeen': true});
    await tapKey(t, 'wifi');
    await frames(t);
    expect(find.text('YOUR NAME'), findsOneWidget);
    expect(find.byKey(const Key('wifiNameTip')), findsOneWidget);
  });

  testWidgets('Wi-Fi: signed in, the name is filled in and there is no tip', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    await frames(t);
    await tapKey(t, 'wifi');
    await frames(t);
    expect(find.byKey(const Key('wifiNameTip')), findsNothing);
    expect(t.widget<TextField>(find.byKey(const Key('lanName'))).controller!.text, 'Sami');
  });
}
