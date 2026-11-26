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

  testWidgets('[1.3.1, his report] the page of a player WITH games: tapping the photo opens it too', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Dareer');
    final d = s.users[s.idOf('Dareer')]!;
    s.playerAnswer = {'key': 'u:${d['id']}', 'name': 'Dareer', 'userId': d['id'], 'games': 1, 'wins': 1, 'best': 'citizen',
      'roles': {'mafia': [0, 0], 'doctor': [0, 0], 'detective': [0, 0], 'citizen': [1, 1]}, 'mafia': [0, 0], 'side': [1, 1], 'nemesis': null, 'partner': null,
      'moments': {'saves': 0, 'caught': 0, 'killed': 0, 'out': 0}, 'form': [true],
      'card': {'id': d['id'], 'handle': d['handle'], 'display': 'Dareer', 'avatar': {'photo': 4}, 'fav': '', 'rel': 'none'}};
    final a = await launch(t, server: s, tokens: MemoryTokens()..t = tok, stored: {'guideSeen': true});
    ActiveRoom.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => PlayerScreen(account: a.account, playerKey: 'u:${d['id']}')));
    await frames(t);
    expect(find.byKey(const Key('noGamesYet')), findsNothing, reason: 'the page with games');
    await tapKey(t, 'profilePhoto');
    await frames(t);
    expect(find.byKey(const Key('profilePhotoFull')), findsOneWidget);
  });
}
