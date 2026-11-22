// On the emulator against the local Worker (see account_test.dart): the app creates a room and hosts a whole online
// game with three scripted players (real sockets from this test). One joins through a friend invite. Mid-night the
// app's connection is cut and comes back in the same seat. The finished game then shows in History.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mafia_dealer/account.dart';
import 'package:mafia_dealer/api.dart';
import 'package:mafia_dealer/audio.dart';
import 'package:mafia_dealer/main.dart';
import 'package:mafia_dealer/online.dart';
import 'package:mafia_dealer/prefs.dart';
import 'package:mafia_dealer/room.dart';
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

Future<Api> signUp(String email, String handle) async {
  final a = Api();
  await a.post('/v1/auth/email/start', {'email': email});
  a.token = (await a.post('/v1/auth/email/verify', {'email': email, 'code': await codeFor(email), 'device': 'bot'}))['token'] as String;
  await a.patch('/v1/me', {'handle': handle, 'display': handle});
  return a;
}

/// A scripted player: readies, picks the first allowed target at night, votes for the lowest other living seat.
class Bot {
  Bot(this.api);
  final Api api;
  WebSocket? ws;
  Map<String, Object?>? view, room;
  int readyFor = -1;
  final sent = <String>{};

  Future<void> join(String code) async {
    ws = await WebSocket.connect(api.socket('/v1/rooms/$code/ws').toString(), protocols: ['mafia.v1', api.token!]);
    ws!.listen((raw) {
      if (raw == 'pong') return;
      final m = jsonDecode(raw as String) as Map<String, Object?>;
      if (m['t'] == 'room') room = Map<String, Object?>.from(m['room'] as Map);
      if (m['t'] == 'view') { view = m['view'] == null ? null : Map<String, Object?>.from(m['view'] as Map); act(); }
    });
  }

  void send(Map<String, Object?> m) { final s = jsonEncode(m); if (sent.add(s)) ws!.add(s); }

  void act() {
    final v = view;
    if (v == null) return;
    if (v['phase'] == 'deal' && room != null && readyFor != room!['deal']) { readyFor = room!['deal'] as int; send({'t': 'ready', 'deal': readyFor}); }
    if (v['ph'] == 'night') {
      final no = v['night'] as Map, key = no['key'];
      final opt = (no['opts'] as List).cast<Map>().where((o) => o['disabled'] != true).firstOrNull;
      send({'t': 'night', 'choice': key == 'none' ? null : opt?['seat'], 'day': v['day']});
    }
    if (v['ph'] == 'vote') {
      final me = v['seat'], opts = (v['voteOpts'] as List).cast<Map>().where((o) => o['seat'] != me).toList();
      send({'t': 'vote', 'choice': opts.isEmpty ? 'none' : opts.first['seat'], 'id': v['voteId']});
    }
  }
}

Future<void> waitUntil(WidgetTester t, bool Function() ok, String what, {int seconds = 30}) async {
  for (var i = 0; i < seconds * 10; i++) { if (ok()) return; await t.pump(const Duration(milliseconds: 100)); }
  throw TestFailure('timed out waiting for $what');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a whole online game hosted by the app, with a drop mid-night and a friend invite', (t) async {
    await (await SharedPreferences.getInstance()).clear();
    final run = Random().nextInt(1 << 30).toRadixString(36);
    final prefs = await Prefs.load(), audio = Audio(prefs), account = Account(Api(), MemoryTokens(), prefs);
    await audio.init();
    // the app's player signs up through the API (the account test covers the sign-in screens) and starts the app
    final me = await signUp('h$run@example.com', 'h_$run');
    account.api.token = me.token;
    await account.refresh();
    await t.pumpWidget(App(prefs: prefs, audio: audio, account: account));
    await t.pump(const Duration(milliseconds: 500));

    // create the room in the app
    await tapKey(t, 'online');
    await tapKey(t, 'createRoom');
    await waitFor(t, find.byType(RoomScreen));
    final conn = (t.state(find.byType(RoomScreen)) as dynamic).conn as RoomConn;
    await waitUntil(t, () => conn.room != null, 'the room');
    final code = conn.code;

    // two players join with the code; the third is a friend who gets an invite
    final bots = [Bot(await signUp('b1$run@example.com', 'b1_$run')), Bot(await signUp('b2$run@example.com', 'b2_$run'))];
    for (final b in bots) { await b.join(code); }
    final friend = Bot(await signUp('f$run@example.com', 'f_$run'));
    await friend.api.post('/v1/friend-requests', {'handle': 'h_$run'});
    await me.post('/v1/friend-requests', {'handle': 'f_$run'}); // asked both ways: friends
    await tapKey(t, 'inviteFriends');
    await tapKey(t, 'invite_f_$run');
    await t.pump(const Duration(milliseconds: 500));
    final notes = (await friend.api.get('/v1/notifications'))['notifications'] as List;
    expect(notes.cast<Map>().any((n) => n['kind'] == 'invite' && n['code'] == code), isTrue, reason: 'the invite reached the friend');
    await t.tapAt(const Offset(200, 60)); // close the sheet
    await friend.join(code);
    bots.add(friend);
    await waitUntil(t, () => conn.members.length == 4, '4 players');

    // play: the app is the host
    var dropped = false;
    for (var step = 0; step < 300; step++) {
      await t.pump(const Duration(milliseconds: 200));
      final v = conn.view;
      bool on(String k) => find.byKey(Key(k)).evaluate().isNotEmpty;
      if (v == null) { if (on('deal')) await tapKey(t, 'deal'); continue; }
      if (v['phase'] == 'end') {
        if (on('revealNow')) { await tapKey(t, 'revealNow'); continue; }
        if (on('playAgain')) break;
        continue;
      }
      if (v['phase'] == 'deal') {
        if (on('roleCard')) {
          final hold = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
          await t.pump(const Duration(milliseconds: 300));
          await hold.up();
          await t.pump();
          await tapKey(t, 'memorized');
        } else if (on('start')) {
          await tapKey(t, 'start');
        }
        continue;
      }
      if (v['ph'] == 'night' && !dropped) {
        // the network drops in the middle of the night: back in the same seat, still in the night
        dropped = true;
        final seat = v['seat'];
        conn.dropForTest();
        await waitUntil(t, () => conn.open && conn.view?['seat'] == seat, 'reconnected in the same seat');
        expect(conn.view?['phase'], 'night');
        continue;
      }
      if (v['ph'] == 'night') {
        final no = v['night'] as Map, opt = (no['opts'] as List).cast<Map>().where((o) => o['disabled'] != true).firstOrNull;
        if (no['key'] != 'none' && opt != null) await tapKey(t, 'opt_${opt['seat']}');
        await tapKey(t, 'confirm');
        continue;
      }
      if (v['ph'] == 'vote') {
        final opts = (v['voteOpts'] as List).cast<Map>().where((o) => o['seat'] != v['seat']).toList();
        await tapKey(t, opts.isEmpty ? 'opt_none' : 'opt_${opts.first['seat']}');
        await tapKey(t, 'castVote');
        continue;
      }
      if (on('revealNow')) { await tapKey(t, 'revealNow'); continue; }
      for (final k in ['startDay', 'secretVote', 'nextNight']) { if (on(k)) { await tapKey(t, k); break; } }
    }
    expect(dropped, isTrue);
    expect(conn.view?['phase'], 'end');
    await waitUntil(t, () => conn.room?['gameId'] != null, 'the game saved');

    // the finished game is in History
    await tapKey(t, 'leave');
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('Leave room').last);
    await waitFor(t, find.byKey(const Key('history')));
    await tapKey(t, 'history');
    await waitFor(t, find.byKey(Key('game_${conn.room!['gameId']}')));
    for (final b in bots) { await b.ws?.close(); }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }, skip: !local);
}
