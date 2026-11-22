// On the emulator against a real local Worker (CI: `wrangler dev --var MAIL_LOG:1`, the app built with
// --dart-define=API_BASE=http://10.0.2.2:8787): sign up by email, pick a handle, a second account asks to be friends,
// the request arrives live through the hub, accept it, then delete the account. Skipped against the real server.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mafia_dealer/account.dart';
import 'package:mafia_dealer/api.dart';
import 'package:mafia_dealer/audio.dart';
import 'package:mafia_dealer/main.dart';
import 'package:mafia_dealer/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/driver.dart';

final local = apiBase.contains('10.0.2.2') || apiBase.contains('localhost');

Future<String> codeFor(String email) async {
  for (var i = 0; i < 50; i++) {
    final c = (jsonDecode((await http.get(Uri.parse('$apiBase/v1/test/last-code/$email'))).body) as Map)['code'];
    if (c != null) return c as String;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TestFailure('no code for $email');
}

Future<void> typeKey(WidgetTester t, String key, String text) async {
  final f = find.byKey(Key(key));
  await waitFor(t, f);
  await t.pump(const Duration(milliseconds: 400));
  await t.enterText(f, text);
  await t.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sign up, a friend request arrives live, accept, delete the account', (t) async {
    await (await SharedPreferences.getInstance()).clear();
    final run = Random().nextInt(1 << 30).toRadixString(36), emailA = 'a$run@example.com', emailB = 'b$run@example.com';
    final prefs = await Prefs.load(), audio = Audio(prefs), account = Account(Api(), MemoryTokens(), prefs);
    await audio.init();
    await t.pumpWidget(App(prefs: prefs, audio: audio, account: account));
    await t.pump(const Duration(milliseconds: 500));

    // A signs up in the app
    await tapKey(t, 'signIn');
    await typeKey(t, 'email', emailA);
    await tapKey(t, 'sendCode');
    await typeKey(t, 'code', await codeFor(emailA));
    await tapKey(t, 'verify');
    await typeKey(t, 'handle', 'a_$run');
    await typeKey(t, 'display', 'Player A');
    await tapKey(t, 'saveHandle');
    await waitFor(t, find.byKey(const Key('saveProfile')));
    expect(account.handle, 'a_$run');
    await t.binding.handlePopRoute();
    await waitFor(t, find.byKey(const Key('bell')));

    // B (another phone, here straight through the API) signs up and asks A to be friends
    final b = Api();
    await b.post('/v1/auth/email/start', {'email': emailB});
    b.token = (await b.post('/v1/auth/email/verify', {'email': emailB, 'code': await codeFor(emailB), 'device': 'test'}))['token'] as String;
    await b.patch('/v1/me', {'handle': 'b_$run', 'display': 'Player B'});
    await b.post('/v1/friend-requests', {'handle': 'a_$run'});

    // the request reaches A live, through the hub socket
    for (var i = 0; i < 100 && account.unread == 0; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(account.unread, 1);
    expect(account.incoming.map((p) => p.handle), ['b_$run']);
    await tapKey(t, 'friends');
    await tapKey(t, 'tabRequests');
    await tapKey(t, 'accept_b_$run');
    for (var i = 0; i < 50 && account.friends.isEmpty; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(account.friends.map((p) => p.handle), ['b_$run']);
    expect(((await b.get('/v1/friends'))['friends'] as List).single['handle'], 'a_$run');
    await t.binding.handlePopRoute();

    // A deletes the account
    await tapKey(t, 'profile');
    await waitFor(t, find.byKey(const Key('deleteAccount')));
    await t.scrollUntilVisible(find.byKey(const Key('deleteAccount')), 300, scrollable: find.byType(Scrollable).first);
    await tapKey(t, 'deleteAccount');
    await typeKey(t, 'typeDelete', 'delete');
    await tapKey(t, 'confirmDelete');
    await waitFor(t, find.byKey(const Key('signIn')));
    expect(account.signedIn, isFalse);
    expect(((await b.get('/v1/friends'))['friends'] as List), isEmpty, reason: 'the friendship went with the account');
    account.foreground(false); // the hub socket closes
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }, skip: !local);
}
