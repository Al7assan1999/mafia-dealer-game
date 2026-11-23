// On the emulator: the app hosts a real Wi-Fi room (its server on port 8765, the keep-alive service), three scripted
// phones join over sockets and play. Mid-game the host's room is stopped and resumed from its snapshot (as after the app
// is killed); everyone reconnects into the same seats and the game goes on to the end, kept in History → Wi-Fi.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mafia_dealer/account.dart';
import 'package:mafia_dealer/api.dart';
import 'package:mafia_dealer/audio.dart';
import 'package:mafia_dealer/lan/lan.dart';
import 'package:mafia_dealer/lan/local_room.dart';
import 'package:mafia_dealer/lan/wifi_screen.dart';
import 'package:mafia_dealer/main.dart';
import 'package:mafia_dealer/online.dart';
import 'package:mafia_dealer/prefs.dart';
import 'package:mafia_dealer/room.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/driver.dart';

/// A scripted phone on the Wi-Fi room: readies, picks the first allowed target, votes for the lowest other seat.
class Bot {
  Bot(this.uid);
  final String uid;
  WebSocket? ws;
  Map<String, Object?>? view, room;
  int rev = 0;
  final sent = <String>{};

  Future<void> join(String code) async {
    final q = rev > 0 ? '?rev=$rev' : '';
    ws = await WebSocket.connect('ws://127.0.0.1:$lanPort/v1/rooms/$code/ws$q', protocols: ['mafia.v1', Identity(uid, 'Bot $uid').token()]);
    ws!.listen((raw) {
      if (raw == 'pong') return;
      final m = jsonDecode(raw as String) as Map<String, Object?>;
      if (m['rev'] is int) rev = m['rev'] as int;
      if (m['t'] == 'room') room = Map<String, Object?>.from(m['room'] as Map);
      if (m['t'] == 'view') { view = m['view'] == null ? null : Map<String, Object?>.from(m['view'] as Map); act(); }
    }, onError: (_) {});
  }

  void send(Map<String, Object?> m) { final s = jsonEncode(m); if (sent.add(s)) ws?.add(s); }

  void act() {
    final v = view;
    if (v == null) return;
    if (v['phase'] == 'deal' && room != null) send({'t': 'ready', 'deal': room!['deal']});
    if (v['ph'] == 'night') {
      final no = v['night'] as Map, opt = (no['opts'] as List).cast<Map>().where((o) => o['disabled'] != true).firstOrNull;
      send({'t': 'night', 'choice': no['key'] == 'none' ? null : opt?['seat'], 'day': v['day']});
    }
    if (v['ph'] == 'vote') {
      final o = (v['voteOpts'] as List).cast<Map>().where((x) => x['seat'] != v['seat']).toList();
      send({'t': 'vote', 'choice': o.isEmpty ? 'none' : o.first['seat'], 'id': v['voteId']});
    }
  }
}

Future<void> waitUntil(WidgetTester t, bool Function() ok, String what, {int seconds = 30}) async {
  for (var i = 0; i < seconds * 10; i++) { if (ok()) return; await t.pump(const Duration(milliseconds: 100)); }
  throw TestFailure('timed out waiting for $what');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a hosted Wi-Fi game, the host resumed mid-game, to the end', (t) async {
    await (await SharedPreferences.getInstance()).clear();
    final prefs = await Prefs.load(), audio = Audio(prefs), account = Account(Api(), MemoryTokens(), prefs, live: false);
    prefs.guideSeen = true;
    prefs.lanName = 'Host';
    await audio.init();
    await t.pumpWidget(App(prefs: prefs, audio: audio, account: account));
    await t.pump(const Duration(milliseconds: 500));
    await tapKey(t, 'wifi');
    await tapKey(t, 'hostRoom');
    await waitFor(t, find.byType(RoomScreen));
    RoomConn conn() => (t.state(find.byType(RoomScreen, skipOffstage: false)) as dynamic).conn as RoomConn;
    await waitUntil(t, () => conn().room != null, 'the room');
    final code = conn().code;
    final bots = [for (final u in ['b1', 'b2', 'b3']) Bot(u)];
    for (final b in bots) { await b.join(code); }
    await waitUntil(t, () => conn().members.length == 4, '4 players');

    var resumed = false;
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
      if (v['phase'] == 'night' && !resumed) {
        // the host's room goes down (as if the app were killed) and comes back from its snapshot
        resumed = true;
        final seat = v['seat'];
        expect(prefs.lanHost, isNotNull);
        await LanHost.stop(clear: false);
        await t.pump(const Duration(seconds: 1));
        expect(await LanHost.start(prefs, restore: prefs.lanHost), code);
        for (final b in bots) { await b.ws?.close(); await b.join(code); }
        await waitUntil(t, () => conn().open && conn().view?['seat'] == seat, 'the host back in its seat');
        await waitUntil(t, () => conn().members.where((m) => m['online'] == true).length == 4, 'everyone back');
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
    expect(resumed, isTrue);
    expect(conn().view?['phase'], 'end');
    await waitUntil(t, () => prefs.wifiGames.isNotEmpty, 'the game kept on the phone');
    for (final b in bots) { await b.ws?.close(); }
    await LanHost.stop();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  });
}
