// On the emulator against the local Worker: chat with a scripted player in a real room (both ways, a reply), then
// report their message with "also block": the server takes the report, and their next message never arrives.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/app.dart';
import 'package:mafia_dealer/features/room/room_screen.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/state/room_conn.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/driver.dart';

final local = apiBase.contains('10.0.2.2') || apiBase.contains('localhost');

Future<Api> signUp(String email, String handle) async {
  final a = Api();
  await a.post('/v1/auth/email/start', {'email': email});
  String? code;
  for (var i = 0; i < 50 && code == null; i++) {
    code = (jsonDecode((await http.get(Uri.parse('$apiBase/v1/test/last-code/$email'))).body) as Map)['code'] as String?;
    if (code == null) await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  a.token = (await a.post('/v1/auth/email/verify', {'email': email, 'code': code, 'device': 'bot'}))['token'] as String;
  await a.patch('/v1/me', {'handle': handle, 'display': handle});
  return a;
}

Future<void> waitUntil(WidgetTester t, bool Function() ok, String what) async {
  for (var i = 0; i < 300; i++) { if (ok()) return; await t.pump(const Duration(milliseconds: 100)); }
  throw TestFailure('timed out waiting for $what');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chat both ways, then report + block: their next message never arrives', (t) async {
    await (await SharedPreferences.getInstance()).clear();
    final run = Random().nextInt(1 << 30).toRadixString(36);
    final prefs = await Prefs.load(), audio = Audio(prefs), account = Account(Api(), MemoryTokens(), prefs);
    prefs.guideSeen = true;
    await audio.init();
    final me = await signUp('c$run@example.com', 'c_$run');
    account.api.token = me.token;
    await account.refresh();
    await t.pumpWidget(App(prefs: prefs, audio: audio, account: account));
    await t.pump(const Duration(milliseconds: 500));
    await tapKey(t, 'online');
    await tapKey(t, 'createRoom');
    await waitFor(t, find.byType(RoomScreen));
    final conn = (t.state(find.byType(RoomScreen, skipOffstage: false)) as dynamic).conn as RoomConn;
    await waitUntil(t, () => conn.room != null, 'the room');

    // a scripted player joins and says hello
    final bot = await signUp('d$run@example.com', 'd_$run');
    final got = <Map<String, Object?>>[];
    final ws = await WebSocket.connect(bot.socket('/v1/rooms/${conn.code}/ws?v=100017').toString(), protocols: ['mafia.v1', bot.token!]);
    ws.listen((raw) { if (raw != 'pong') got.add(jsonDecode(raw as String) as Map<String, Object?>); });
    await waitUntil(t, () => conn.members.length == 2, 'the bot in the room');
    ws.add(jsonEncode({'t': 'chat', 'to': -1, 'text': 'hello from the bot', 'cid': 'b1'}));
    await waitUntil(t, () => conn.chat.values.any((m) => m['text'] == 'hello from the bot'), 'the bot message');
    expect(conn.unreadTotal, 1);

    // the app answers
    await tapKey(t, 'chat');
    await waitFor(t, find.byKey(const Key('chatText'))); // the chat page slides in first
    await t.enterText(find.byKey(const Key('chatText')), 'hello bot');
    await tapKey(t, 'chatSend');
    await waitUntil(t, () => got.any((m) => m['t'] == 'chat' && (m['msg'] as Map)['text'] == 'hello bot'), 'the bot hears the app');
    await waitUntil(t, () => conn.outbox.isEmpty, 'the message confirmed');

    // report the bot's message, with "also block"
    final id = conn.chat.values.firstWhere((m) => m['text'] == 'hello from the bot')['id'];
    await t.longPress(find.byKey(Key('msg_$id')));
    await t.pump(const Duration(milliseconds: 500));
    await tapKey(t, 'menuReport');
    await tapKey(t, 'reason_spam');
    await tapKey(t, 'sendReport');
    await waitFor(t, find.text('Thanks. The report was sent.'));

    // the bot writes again: blocked, it never reaches the app (the bot still sees its own message)
    ws.add(jsonEncode({'t': 'chat', 'to': -1, 'text': 'after the block', 'cid': 'b2'}));
    for (var i = 0; i < 20 && !got.any((m) => m['cid'] == 'b2'); i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(got.any((m) => m['cid'] == 'b2'), isTrue, reason: 'the bot got its own confirmation');
    await t.pump(const Duration(seconds: 1));
    expect(conn.chat.values.any((m) => m['text'] == 'after the block'), isFalse);
    expect(((await bot.get('/v1/friends'))['friends'] as List), isEmpty);

    await ws.close();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }, skip: !local);
}
