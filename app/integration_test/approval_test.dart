// On the emulator against a real local Worker (CI: `wrangler dev --var MAIL_LOG:1`, with the local D1's
// wifi_rules.minSecondsPerRound set to 0, since a scripted game takes seconds): a signed-in host plays a whole Wi-Fi game
// with three signed-in scripted phones, taps "Add to online history" on the end screen, the three confirm, and the
// game is approved: the host hears it live in the bell, and it is in Wi-Fi history but not online history.
// Skipped against the real server.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mafia_dealer/account.dart';
import 'package:mafia_dealer/api.dart';
import 'package:mafia_dealer/audio.dart';
import 'package:mafia_dealer/lan/wifi_screen.dart';
import 'package:mafia_dealer/main.dart';
import 'package:mafia_dealer/online.dart';
import 'package:mafia_dealer/prefs.dart';
import 'package:mafia_dealer/room.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/driver.dart';
import 'account_test.dart' show codeFor, local;
import 'wifi_test.dart' show Bot, waitUntil;

/// An account made through the API (as another phone would): its session token and id.
Future<(Api, String)> signUp(String email, String handle) async {
  final a = Api();
  await a.post('/v1/auth/email/start', {'email': email});
  final r = await a.post('/v1/auth/email/verify', {'email': email, 'code': await codeFor(email), 'device': 'test'});
  a.token = r['token'] as String;
  await a.patch('/v1/me', {'handle': handle, 'display': handle});
  return (a, (r['user'] as Map)['id'] as String);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a signed-in Wi-Fi game added to online history: asked on the end screen, confirmed by all, approved', (t) async {
    if (!local) return;
    await (await SharedPreferences.getInstance()).clear();
    final run = Random().nextInt(1 << 30).toRadixString(36);
    final (hostApi, _) = await signUp('h$run@example.com', 'h_$run');
    final bots = <(Bot, Api)>[];
    for (final n in ['x', 'y', 'z']) {
      final (api, id) = await signUp('$n$run@example.com', '${n}_$run');
      bots.add((Bot('$n$run', userId: id), api));
    }
    final prefs = await Prefs.load(), audio = Audio(prefs), account = Account(Api(), MemoryTokens()..t = hostApi.token, prefs);
    prefs.guideSeen = true;
    await audio.init();
    await account.restore();
    expect(account.signedIn, isTrue);
    await t.pumpWidget(App(prefs: prefs, audio: audio, account: account));
    await t.pump(const Duration(milliseconds: 500));
    await tapKey(t, 'wifi');
    await tapKey(t, 'hostRoom');
    await waitFor(t, find.byType(RoomScreen));
    RoomConn conn() => (t.state(find.byType(RoomScreen, skipOffstage: false)) as dynamic).conn as RoomConn;
    await waitUntil(t, () => conn().room != null, 'the room');
    final code = conn().code;
    for (final (b, _) in bots) { await b.join(code); }
    await waitUntil(t, () => conn().members.length == 4, '4 players');

    for (var step = 0; step < 400; step++) {
      await t.pump(const Duration(milliseconds: 200));
      final v = conn().view;
      bool on(String k) => find.byKey(Key(k)).evaluate().isNotEmpty;
      if (v == null) { if (on('deal')) await tapKey(t, 'deal'); continue; }
      if (v['phase'] == 'end') { if (on('revealNow')) { await tapKey(t, 'revealNow'); continue; } break; }
      if (v['phase'] == 'deal') {
        if (on('roleCard')) {
          final hold = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
          await t.pump(const Duration(milliseconds: 300));
          await hold.up();
          await t.pump();
          await tapKey(t, 'memorized');
        }
        continue;
      }
      if (v['ph'] == 'night') {
        final no = v['night'] as Map, opt = (no['opts'] as List).cast<Map>().where((o) => o['disabled'] != true).firstOrNull;
        if (no['key'] != 'none' && opt != null) await tapKey(t, 'opt_${opt['seat']}');
        await tapKey(t, 'confirm');
        continue;
      }
      if (v['ph'] == 'vote') {
        final o = (v['voteOpts'] as List).cast<Map>().where((x) => x['seat'] != v['seat']).toList();
        await tapKey(t, o.isEmpty ? 'opt_none' : 'opt_${o.first['seat']}');
        await tapKey(t, 'castVote');
        continue;
      }
      if (on('revealNow')) { await tapKey(t, 'revealNow'); continue; }
      for (final k in ['startDay', 'secretVote', 'nextNight']) { if (on(k)) { await tapKey(t, k); break; } }
    }
    expect(conn().view?['phase'], 'end');
    await waitUntil(t, () => prefs.wifiGames.isNotEmpty, 'the game kept on the phone');
    final kept = prefs.wifiGames.first;
    expect(kept['host'], isTrue);
    expect((kept['accounts'] as List).every((x) => x != null), isTrue, reason: 'every seat signed in');

    // the host asks from the end screen
    await tapKey(t, 'addOnline');
    await waitUntil(t, () => prefs.wifiGames.first['req'] != null, 'the request');
    final req = Map<String, Object?>.from(prefs.wifiGames.first['req'] as Map);
    expect(req['status'], 'pending', reason: 'rejected: ${req['reason']}');
    await waitFor(t, find.text('Waiting for 3 of 4 to confirm'));

    // each player confirms from their bell (here through the API)
    final before = account.unread;
    final answers = <String>[];
    for (final (_, api) in bots) {
      final bell = (await api.get('/v1/notifications'))['notifications'] as List;
      expect(bell.where((n) => (n as Map)['kind'] == 'wifi_confirm'), hasLength(1));
      answers.add((await api.post('/v1/wifi-requests/${req['id']}/answer', {'yes': true}))['status'] as String);
    }
    expect(answers, ['pending', 'pending', 'approved']);

    // the host hears it live (its app is open: the hub, not a push) and History has it
    await waitUntil(t, () => account.unread > before, 'the result in the bell');
    expect(account.notes.first.kind, 'wifi_result');
    final mine = await account.wifiRequests();
    expect(mine.single['status'], 'approved');
    expect(await account.games(), isEmpty, reason: 'online history stays online games');

    for (final (b, _) in bots) { await b.ws?.close(); }
    await LanHost.stop();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  });
}
