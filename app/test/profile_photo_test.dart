// A player's photo on their profile opens full size; a preset picture doesn't open anything.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/features/stats/player_screen.dart';
import 'package:mafia_dealer/state/active_room.dart';
import 'package:mafia_dealer/state/models.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show frames;

void main() {
  setUpAll(setUpHarness);

  testWidgets('tapping a profile photo opens it full size; a preset stays put', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    final d = s.users[s.idOf('Dareer')]!;
    Future<void> open(Map<String, Object?> avatar) async {
      ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => PlayerScreen(account: a.account, playerKey: 'u:${d['id']}',
          person: Person({'id': d['id'], 'handle': d['handle'], 'display': d['display'], 'avatar': avatar, 'fav': '', 'rel': 'none'}))));
      await frames(t);
    }

    await open({'photo': 3});
    await tapKey(t, 'profilePhoto');
    await frames(t);
    expect(find.byKey(const Key('profilePhotoFull')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget, reason: 'pinch to zoom');
    ActiveRoom.navigatorKey.currentState!..pop()..pop();
    await frames(t);

    await open({'preset': 2});
    await tapKey(t, 'profilePhoto');
    await frames(t);
    expect(find.byKey(const Key('profilePhotoFull')), findsNothing);
    expect(find.byKey(const Key('profileName')), findsOneWidget);
  });
}
