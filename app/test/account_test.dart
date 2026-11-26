// Accounts and friends through the real UI against a fake server: every sign-in path and its errors, the profile,
// friends, the bell, account deletion, saved names, and no network at all.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/features/account/profile_screen.dart';
import 'package:mafia_dealer/core/ui.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';

Future<void> settleUi(WidgetTester t) async { for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 100)); } }

Future<void> type(WidgetTester t, String key, String text) async {
  final f = find.byKey(Key(key));
  await waitFor(t, f);
  await t.pump(const Duration(milliseconds: 400));
  await t.enterText(f, text);
  await t.pump();
}

/// Signs in with an email code, as a player would.
Future<void> emailSignIn(WidgetTester t, String email, {String code = '123456'}) async {
  await tapKey(t, 'signIn');
  await type(t, 'email', email);
  await tapKey(t, 'sendCode');
  await settleUi(t);
  await type(t, 'code', code);
  await tapKey(t, 'verify');
  await settleUi(t);
}

String? errorShown(WidgetTester t) => find.byKey(const Key('error')).evaluate().isEmpty ? null : t.widget<Text>(find.byKey(const Key('error'))).data;

void main() {
  setUpAll(setUpHarness);

  testWidgets('email sign-in: wrong code, then the right one; a new account picks a free @handle', (t) async {
    final s = FakeServer()..user('Taken');
    final app = await launch(t, server: s);
    await emailSignIn(t, 'new@example.com', code: '000000');
    expect(errorShown(t), 'That code is wrong or has expired.');
    await type(t, 'code', '123456');
    await tapKey(t, 'verify');
    await settleUi(t);
    expect(find.byKey(const Key('handle')), findsOneWidget, reason: 'a new account chooses its handle first');
    await type(t, 'handle', 'ab');
    await tapKey(t, 'saveHandle');
    expect(errorShown(t), contains('3-20'));
    await type(t, 'handle', '@taken');
    await type(t, 'display', 'Newbie');
    await tapKey(t, 'saveHandle');
    await settleUi(t);
    expect(errorShown(t), 'That username is taken');
    expect(find.byKey(const Key('handleTaken')), findsOneWidget, reason: '[1.1.1 hotfix] and an alert');
    await t.tap(find.text('OK'));
    await settleUi(t);
    await type(t, 'handle', 'newbie_1');
    await tapKey(t, 'saveHandle');
    await settleUi(t);
    expect(app.account.handle, 'newbie_1');
    expect(app.account.display, 'Newbie');
    expect(find.byKey(const Key('saveProfile')), findsOneWidget, reason: 'then the profile');
    // [BA P4] the sign-up ends with Done, back to Home; the profile opened from Home has no Done
    await tapKey(t, 'profileDone');
    await settleUi(t);
    expect(find.byKey(const Key('saveProfile')), findsNothing);
    await tapKey(t, 'profile');
    await settleUi(t);
    expect(find.byKey(const Key('saveProfile')), findsOneWidget);
    expect(find.byKey(const Key('profileDone')), findsNothing);
  });

  testWidgets('"slow down", no network, and a bad email each say what happened; nothing hangs', (t) async {
    final s = FakeServer(), app = await launch(t, server: s);
    await tapKey(t, 'signIn');
    await type(t, 'email', 'not-an-email');
    await tapKey(t, 'sendCode');
    expect(errorShown(t), "That doesn't look like an email address");
    s.slow = true;
    await type(t, 'email', 'a@example.com');
    await tapKey(t, 'sendCode');
    await settleUi(t);
    expect(errorShown(t), 'Too many tries. Wait a little and try again.');
    s.offline = true;
    await tapKey(t, 'sendCode');
    await settleUi(t);
    expect(errorShown(t), 'No connection. Check the internet and try again.');
    expect(app.account.signedIn, isFalse);
  });

  testWidgets('Google: signs in; cancelling says nothing; without Google Cloud set up the button is off', (t) async {
    final g = FakeGoogle()..cancel = true, s = FakeServer();
    final app = await launch(t, server: s, google: g);
    await tapKey(t, 'signIn');
    await tapKey(t, 'google');
    await settleUi(t);
    expect(errorShown(t), isNull);
    expect(app.account.signedIn, isFalse);
    g.cancel = false;
    await tapKey(t, 'google');
    await settleUi(t);
    expect(app.account.signedIn, isTrue);
    expect(app.account.handle, 'gUser');
  });

  testWidgets('Google not configured: the button says so and does nothing', (t) async {
    await launch(t, google: FakeGoogle()..available = false);
    await tapKey(t, 'signIn');
    await settleUi(t);
    expect(find.text('Google sign-in is not set up yet'), findsOneWidget);
    await tapKey(t, 'google');
    expect(find.byKey(const Key('email')), findsOneWidget, reason: 'still on the sign-in screen');
  });

  testWidgets('a saved session signs in silently; offline it shows the cached profile; a refused session signs out and keeps the game', (t) async {
    final s = FakeServer(), tok = s.user('Sami'), tokens = MemoryTokens()..t = tok;
    final app = await launch(t, server: s, tokens: tokens);
    await settleUi(t);
    expect(find.text(atHandle('Sami')), findsOneWidget); // [S15-1] the @handle next to the avatar again
    // offline at the next start: the cached profile, marked offline; offline play still works
    s.offline = true;
    final again = await launch(t, server: s, tokens: tokens, prefs: app.prefs);
    await settleUi(t);
    expect(find.text(atHandle('Sami')), findsOneWidget); // [S15-1] the @handle next to the avatar again
    expect(find.text('Offline'), findsOneWidget);
    expect(again.account.signedIn, isTrue);
    await setUpGame(t, ['Dareer', 'Halawy', 'Farouq', 'Sami']);
    expect(app.prefs.game, isNotNull);
    // the server no longer knows the session: signed out cleanly, the game in progress stays
    s.offline = false;
    s.sessions.clear();
    await t.runAsync(() => again.account.refresh().catchError((_) {}));
    expect(again.account.signedIn, isFalse);
    expect(tokens.t, isNull);
    expect(app.prefs.game, isNotNull);
  });

  testWidgets('profile: name, handle, favourite role, show online, a preset and a photo (cropped, under 150 KB)', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    final app = await launch(t, server: s, tokens: MemoryTokens()..t = tok);
    await settleUi(t);
    await tapKey(t, 'profile');
    await type(t, 'display', 'Sami K');
    await t.tap(find.byKey(const Key('showOnline')));
    await tapKey(t, 'saveProfile');
    await settleUi(t);
    final me = s.users[s.idOf('Sami')]!;
    expect(me['display'], 'Sami K');
    expect(me['showOnline'], false);
    await tapKey(t, 'preset4');
    await settleUi(t);
    expect(me['avatar'], {'preset': 4});
    // a big photo from the gallery: cropped square and compressed on the phone
    final big = img.encodePng(img.Image(width: 3000, height: 2000)..clear(img.ColorRgb8(200, 30, 30)));
    ProfileScreen.testPicker = () async => Uint8List.fromList(big);
    addTearDown(() => ProfileScreen.testPicker = null);
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('photo')));
      await Future<void>.delayed(const Duration(seconds: 2)); // decoding a 3000 px picture takes real time
    });
    await settleUi(t);
    expect(me['avatar'], {'photo': 1});
    final sent = img.decodeJpg(Uint8List.fromList(s.lastPhoto!))!;
    expect(s.lastPhoto!.length, lessThanOrEqualTo(150000));
    expect([sent.width, sent.height], [256, 256]);
    expect(app.account.card!.photo, 1);
  });

  testWidgets('profile: devices that fail to load say why and load on Try again (not an empty list)', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    await launch(t, server: s, tokens: MemoryTokens()..t = tok);
    await settleUi(t);
    s.offline = true;
    await tapKey(t, 'profile');
    await settleUi(t);
    expect(find.byKey(const Key('devicesErr')), findsOneWidget);
    expect(find.textContaining('Android phone'), findsNothing);
    s.offline = false;
    await t.ensureVisible(find.byKey(const Key('devicesErr')));
    await t.tap(find.descendant(of: find.byKey(const Key('devicesErr')), matching: find.byType(TextButton)));
    await settleUi(t);
    expect(find.byKey(const Key('devicesErr')), findsNothing);
    expect(find.textContaining('Android phone'), findsOneWidget);
  });

  testWidgets('friends: add by @handle, accept, asked both ways at once, unfriend asks first; the bell', (t) async {
    final s = FakeServer(), tok = s.user('Sami');
    s.user('Hokan');
    s.user('Dareer');
    final dareer = s.idOf('Dareer'), me = s.idOf('Sami');
    // Dareer already asked Sami
    s.friendships.add(me.compareTo(dareer) < 0 ? (me, dareer, dareer) : (dareer, me, dareer));
    s.note(me, dareer, 'friend_request');
    final app = await launch(t, server: s, tokens: MemoryTokens()..t = tok);
    await settleUi(t);
    expect(app.account.unread, 1);
    await tapKey(t, 'bell');
    await settleUi(t);
    expect(find.text('wants to be your friend'), findsOneWidget);
    await t.pump(const Duration(seconds: 3)); // the bell's "seen" moment
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settleUi(t);
    expect(app.account.unread, 0, reason: 'after a moment on screen the bell counts as read (N8)');
    await t.tapAt(const Offset(200, 40)); // close the sheet
    await settleUi(t);
    await openFriends(t);
    // [1.1.1 hotfix] the button next to the box searches; a request goes from a result's Add
    await type(t, 'addHandle', '@hokan');
    await tapKey(t, 'searchFriend');
    await t.pump(const Duration(milliseconds: 400));
    await settleUi(t);
    expect(app.account.outgoing, isEmpty, reason: 'Search never sends a request for the typed text');
    await tapKey(t, 'foundAdd_Hokan');
    await settleUi(t);
    expect(app.account.outgoing.map((p) => p.handle), ['Hokan']);
    await type(t, 'addHandle', 'nobody_here');
    await t.pump(const Duration(milliseconds: 400));
    await settleUi(t);
    expect(find.byKey(const Key('searchNone')), findsOneWidget);
    // someone who already asked me: Accept, right in the results
    await type(t, 'addHandle', 'Dareer');
    await t.pump(const Duration(milliseconds: 400));
    await settleUi(t);
    await tapKey(t, 'foundAccept_Dareer');
    await settleUi(t);
    await type(t, 'addHandle', '');
    await settleUi(t);
    expect(app.account.friends.map((p) => p.handle), ['Dareer']);
    await tapKey(t, 'safety_Dareer'); // the ⋮ menu: Remove friend, Block, Report
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Remove friend').last);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Remove Dareer?'), findsOneWidget);
    await t.tap(find.text('Remove friend').last);
    await settleUi(t);
    expect(app.account.friends, isEmpty);
  });

  testWidgets('delete account: typing "delete" is required; afterwards the phone is signed out and offline play works', (t) async {
    final s = FakeServer(), tok = s.user('Sami'), tokens = MemoryTokens()..t = tok;
    final app = await launch(t, server: s, tokens: tokens);
    await settleUi(t);
    await tapKey(t, 'profile');
    await tapKey(t, 'deleteAccount');
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const Key('confirmDelete')));
    await t.pump();
    expect(find.byKey(const Key('typeDelete')), findsOneWidget, reason: 'disabled until "delete" is typed');
    await t.enterText(find.byKey(const Key('typeDelete')), 'delete');
    await t.pump();
    await t.tap(find.byKey(const Key('confirmDelete')));
    await settleUi(t);
    expect(s.users.containsKey(s.sessions[tok]), isFalse);
    expect(app.account.signedIn, isFalse);
    expect(tokens.t, isNull);
    expect(app.prefs.me, isNull);
    await waitFor(t, find.byKey(const Key('signIn')));
    await t.pump(const Duration(seconds: 5)); // the "Account deleted" message goes away
    await setUpGame(t, ['Dareer', 'Halawy', 'Farouq', 'Sami']);
  });

  testWidgets('saved names: the first sign-in moves the phone\'s names into the account; the setup then uses them', (t) async {
    final s = FakeServer(), tok = s.user('Sami', email: 'sami@example.com');
    s.saved[s.idOf('Sami')] = {'names': ['Farouq', 'Hokan']};
    final app = await launch(t, server: s, stored: {'roster': ['Dareer', 'hokan']});
    expect(tok, isNotEmpty);
    await emailSignIn(t, 'sami@example.com');
    await settleUi(t);
    expect(s.saved[s.idOf('Sami')]!['names'], ['Dareer', 'hokan', 'Farouq'], reason: 'merged, no duplicates');
    expect(app.prefs.roster, isEmpty, reason: 'and gone from the phone');
    expect(app.account.names, ['Dareer', 'hokan', 'Farouq']);
  });

  for (final (size, lang, text) in [(const Size(360, 640), 'ar', 1.3), (const Size(412, 915), 'en', 1.3)]) {
    testWidgets('account screens fit: ${size.width.toInt()}x${size.height.toInt()} $lang x$text', (t) async {
      final s = FakeServer(), tok = s.user('Sami');
      s.user('Hokan');
      await launch(t, server: s, tokens: MemoryTokens()..t = tok, size: size, lang: lang, text: text);
      await settleUi(t);
      await tapKey(t, 'profile');
      await settleUi(t);
      await t.scrollUntilVisible(find.byKey(const Key('deleteAccount')), 300, scrollable: find.byType(Scrollable).first);
      await t.binding.handlePopRoute();
      await settleUi(t);
      await openFriends(t);
      await settleUi(t);
      await tapKey(t, 'tabSent');
      await settleUi(t);
    });
  }
}
