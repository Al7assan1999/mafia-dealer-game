// [QA] The Wi-Fi room's rules (lib/lan/local_room.dart), ported from the online room's server tests: the same
// lobby, game, host hand-over, kick, silent phones, catch-up, repeats, late joiners and chat rules. Plus "Resume
// hosting" from a snapshot, and the real server on a socket (discovery answer + a phone joining).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/features/wifi/lan.dart';
import 'package:mafia_dealer/features/wifi/local_room.dart';
import 'package:mafia_engine/mafia_engine.dart';

class Phone implements LanConn {
  Phone(this.uid);
  @override
  final String uid;
  final got = <Map<String, Object?>>[];
  var pongs = 0;
  bool closed = false;
  int? closeCode;
  @override
  void send(String data) { if (data == 'pong') { pongs++; return; } got.add(jsonDecode(data) as Map<String, Object?>); }
  @override
  void close([int code = 1000]) { closed = true; closeCode = code; }
  Map<String, Object?>? last(String t) => got.lastWhere((m) => m['t'] == t, orElse: () => {})['t'] == null ? null : got.lastWhere((m) => m['t'] == t);
  Map<String, Object?>? get view => last('view')?['view'] as Map<String, Object?>?;
  Map<String, Object?> get room => last('room')!['room'] as Map<String, Object?>;
  Map<String, Object?> get me => last('room')!['me'] as Map<String, Object?>;
}

var clock = 1000000;
LocalRoom newRoom() => LocalRoom('123456', 'p0', clock: () => clock, rng: seeded(7));
Identity id(int i) => Identity('p$i', 'P${i + 1}');

/// n phones in the room, in join order (p0 hosts).
(LocalRoom, List<Phone>) table(int n) {
  final r = newRoom(), ps = [for (var i = 0; i < n; i++) Phone('p$i')];
  for (var i = 0; i < n; i++) { expect(r.join(ps[i], id(i), build: 100017), isNull); } // 1.0.0 phones (S17: older ones can't be dealt in)
  return (r, ps);
}

void send(LocalRoom r, Phone p, Map<String, Object?> m) => r.message(p, jsonEncode(m));

void deal(LocalRoom r, List<Phone> ps, {int mafia = 1}) {
  send(r, ps[0], {'t': 'setup', 'rules': defaultRules.toJson(), 'counts': {'mafia': mafia, 'detective': 0}, 'buzzMax': 3});
  send(r, ps[0], {'t': 'deal'});
  for (final p in ps) { send(r, p, {'t': 'ready', 'deal': r.deal}); }
}

void playNight(LocalRoom r, List<Phone> ps) {
  for (final p in ps) {
    final v = p.view!;
    if (v['ph'] != 'night') continue;
    final no = v['night'] as Map, opt = (no['opts'] as List).cast<Map>().where((o) => o['disabled'] != true).first;
    send(r, p, {'t': 'night', 'choice': no['key'] == 'none' ? null : opt['seat'], 'day': v['day']});
  }
}

void main() {
  test('lobby: members in join order, the host; only the host sets up and deals; ready from everyone starts the night', () {
    final (r, ps) = table(4);
    expect([for (final m in (ps[1].room['members'] as List).cast<Map>()) m['display']], ['P1', 'P2', 'P3', 'P4']);
    expect(ps[0].me['host'], true);
    send(r, ps[1], {'t': 'deal'});
    expect(ps[1].last('err')!['error'], 'forbidden');
    deal(r, ps);
    expect(ps.every((p) => p.view!['phase'] == 'night'), isTrue);
    expect(ps.map((p) => p.view!['role']).toSet().containsAll(['mafia', 'doctor']), isTrue);
    expect(ps[0].view!['roles'], isNull, reason: 'no roles before the end');
  });

  test('a whole game to the end: every phone gets the record, and it replays', () {
    final (r, ps) = table(5);
    deal(r, ps);
    for (var i = 0; i < 40 && ps[0].view!['phase'] != 'end'; i++) {
      final ph = ps[0].view!['phase'];
      if (ph == 'night') playNight(r, ps);
      if (ph == 'morning') send(r, ps[0], {'t': 'startDay'});
      if (ph == 'day') send(r, ps[0], {'t': 'startVote', 'open': false});
      if (ph == 'vote') {
        for (final p in ps) {
          final v = p.view!;
          if (v['ph'] != 'vote') continue;
          final others = (v['voteOpts'] as List).cast<Map>().where((o) => o['seat'] != v['seat']).toList();
          send(r, p, {'t': 'vote', 'choice': others.first['seat'], 'id': v['voteId']}); // everyone votes the lowest other seat out
        }
      }
      if (ph == 'verdict') send(r, ps[0], {'t': 'nextNight'});
    }
    expect(ps[0].view!['phase'], 'end');
    for (final p in ps) {
      final rec = p.last('record')!;
      expect(replay(rec['record']).error, isNull);
      expect((rec['seats'] as List).length, 5);
    }
    expect(ps[0].room['gameId'], isNotNull);
  });

  test('host hand-over in join order while the host is away; back again, the host is host', () {
    final (r, ps) = table(4);
    r.closed(ps[0]);
    expect(ps[1].me['host'], true);
    r.join(ps[0], id(0));
    expect(ps[0].me['host'], true);
    expect(ps[1].me['host'], false);
  });

  test('kicks follow the host Settings (lobby only by default); any time: elimination, no coming back; late joiners wait, seat holders return', () {
    final (r, ps) = table(5);
    deal(r, ps);
    // kick a Citizen-side seat (kicking the last Mafia would end the game)
    final k = [for (var i = 1; i < 5; i++) if (r.game!.roles[i] != Role.mafia) i].last;
    send(r, ps[0], {'t': 'kick', 'uid': 'p$k'});
    expect(ps[k].closed, isFalse, reason: 'lobby only: refused mid-game');
    expect(r.kick, 'lobby');
    r.kick = 'any'; // as if the host's Settings said "any time" (the setup message carries it in the lobby)
    send(r, ps[0], {'t': 'kick', 'uid': 'p$k'});
    expect(ps[k].closed, isTrue);
    expect((ps[0].view!['roster'] as List)[k]['alive'], false);
    expect(r.join(Phone('p$k'), id(k)), 'kicked');
    expect(r.join(Phone('p9'), id(9)), 'started');
    final s = [for (var i = 1; i < 5; i++) if (i != k) i].first;
    final back = Phone('p$s');
    expect(r.join(back, id(s)), isNull, reason: 'a seat holder comes back');
    expect(back.view!['seat'], s);
  });

  test('a silent phone is closed after 30 s; "Continue" then skips its turn', () {
    final (r, ps) = table(4);
    deal(r, ps);
    for (final p in ps.skip(1)) {
      final v = p.view!, no = v['night'] as Map, opt = (no['opts'] as List).cast<Map>().where((o) => o['disabled'] != true).first;
      send(r, p, {'t': 'night', 'choice': no['key'] == 'none' ? null : opt['seat'], 'day': 1});
    }
    clock += 31000;
    for (final p in ps.skip(1)) { r.message(p, 'ping'); }
    r.tick();
    expect(ps[0].closed, isTrue);
    expect(ps[0].closeCode, 4001);
    expect(ps[1].me['host'], true, reason: 'the host controls moved on');
    send(r, ps[1], {'t': 'continue'});
    expect(ps[1].view!['phase'], isNot('night'));
  });

  test('catch-up: the events after the rev a phone saw, once; "missed" when too far behind', () {
    final (r, ps) = table(4);
    deal(r, ps);
    final seen = ps[3].last('view')!['rev'] as int;
    r.closed(ps[3]);
    playNight(r, ps.take(3).toList());
    send(r, ps[0], {'t': 'continue'});
    final back = Phone('p3');
    r.join(back, id(3), since: seen);
    final evs = back.got.where((m) => m['t'] == 'events').toList();
    expect(evs.every((m) => (m['rev'] as int) > seen), isTrue);
    expect(evs.expand((m) => m['events'] as List).where((e) => (e as Map)['t'] == 'phase' && e['phase'] == 'morning'), hasLength(1));
    expect(evs.expand((m) => m['events'] as List).any((e) => (e as Map)['t'] == 'night'), isFalse, reason: 'the private night summary stays out');
    r.cut = r.rev;
    final far = Phone('p3');
    r.join(far, id(3), since: 1);
    expect(far.got.any((m) => m['t'] == 'missed'), isTrue);
  });

  test('a repeated night choice or vote changes nothing; an old one is stale', () {
    final (r, ps) = table(4);
    deal(r, ps);
    final p = ps[1], v = p.view!, no = v['night'] as Map, opt = (no['opts'] as List).cast<Map>().where((o) => o['disabled'] != true).first;
    final m = {'t': 'night', 'choice': no['key'] == 'none' ? null : opt['seat'], 'day': 1};
    send(r, p, m);
    send(r, p, m);
    expect(p.got.where((x) => x['t'] == 'err'), isEmpty);
    send(r, p, {...m, 'day': 0});
    expect(p.last('err')!['error'], 'stale');
  });

  test('chat: Everyone and 1:1, out players only reach out players, 8 per 10 s, edits for 15 minutes, mentions', () {
    final (r, ps) = table(4);
    send(r, ps[0], {'t': 'chat', 'to': -1, 'text': 'hi', 'cid': 'c1', 'mentions': [2]});
    expect(ps[1].last('chat')!['msg'], containsPair('text', 'hi'));
    expect(ps[0].last('chat')!['cid'], 'c1');
    expect(ps[1].last('mention'), isNotNull);
    send(r, ps[0], {'t': 'chat', 'to': 3, 'text': 'psst', 'cid': 'c2'});
    expect((ps[2].last('chat')!['msg'] as Map)['text'], 'psst');
    expect(ps[1].got.where((m) => m['t'] == 'chat' && (m['msg'] as Map)['text'] == 'psst'), isEmpty);
    for (var i = 0; i < 9; i++) { send(r, ps[1], {'t': 'chat', 'to': -1, 'text': 'x$i', 'cid': 'k$i'}); } // the 9th within 10 s is refused
    expect(ps[1].last('err')!['error'], 'slow_down');
    final id1 = (ps[0].last('chat')!['msg'] as Map)['id'];
    clock += 16 * 60 * 1000;
    send(r, ps[0], {'t': 'edit', 'id': 1, 'text': 'too late'});
    expect(ps[0].last('err')!['error'], 'too_late');
    expect(id1, isNotNull);
  });

  test('"Resume hosting": a snapshot brings back the room, the game and the chat, and play goes on', () {
    final (r, ps) = table(4);
    deal(r, ps);
    send(r, ps[1], {'t': 'chat', 'to': -1, 'text': 'before the crash', 'cid': 'c'});
    playNight(r, ps);
    final snap = jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>;
    final again = LocalRoom('123456', 'p0', restore: snap, clock: () => clock, rng: seeded(7));
    expect(again.rev, r.rev);
    expect(again.game!.phase, r.game!.phase);
    expect(again.chat.single['text'], 'before the crash');
    final fresh = [for (var i = 0; i < 4; i++) Phone('p$i')];
    for (var i = 0; i < 4; i++) { again.join(fresh[i], id(i), since: r.rev); }
    expect(fresh[2].view!['seat'], 2);
    expect(fresh[0].view!['phase'], r.game!.phase.name);
    send(again, fresh[0], {'t': 'startDay'});
    expect(fresh[0].view!['phase'], anyOf('day', 'end', 'morning'));
  });

  test('the real server: the discovery answer, a phone joining over a socket, a refused identity', () async {
    final room = newRoom(), server = LanServer(room);
    await server.start(port: 0);
    addTearDown(server.stop);
    final found = await probe('127.0.0.1', port: server.port);
    expect(found?.code, '123456');
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/v1/rooms/123456/ws', protocols: ['mafia.v1', id(0).token()]);
    final first = jsonDecode(await ws.first as String) as Map<String, Object?>;
    expect(first['t'], 'room');
    await ws.close();
    await expectLater(WebSocket.connect('ws://127.0.0.1:${server.port}/v1/rooms/123456/ws', protocols: ['mafia.v1', 'not-a-token']), throwsA(anything));
    expect(await probe('127.0.0.1', port: 1), isNull, reason: 'nothing there');
  });
}
