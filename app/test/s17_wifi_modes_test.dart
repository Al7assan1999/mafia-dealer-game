// [S17-4] The Wi-Fi room (the host phone) keeps phones older than 1.0.0 out of the new modes, like the server; the
// mode survives "Resume hosting".
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/features/wifi/local_room.dart';
import 'package:mafia_engine/mafia_engine.dart';

import 'lan_room_test.dart' show Phone, id, newRoom, send;

void main() {
  test('a guest below 1.0.0 (or with no build) keeps any deal from happening, Classic too (his ruling); once they leave, it deals', () {
    final r = newRoom(), ps = [for (var i = 0; i < 6; i++) Phone('p$i')];
    for (var i = 0; i < 6; i++) { expect(r.join(ps[i], id(i), build: i == 3 ? modesBuild - 1 : i == 4 ? null : modesBuild), isNull); }
    void setup(String? mode) => send(r, ps[0], {'t': 'setup', 'rules': defaultRules.toJson(), 'counts': {'mafia': 1, 'detective': 0}, 'buzzMax': 3,
        'mode': ?mode});
    setup('sniper');
    expect(ps[0].room['mode'], 'sniper');
    send(r, ps[0], {'t': 'deal'});
    expect(ps[0].last('err')?['error'], 'old_app');
    expect(r.game, isNull);
    setup(null);                                     // an older host sends no mode: Classic
    expect(ps[0].room['mode'], 'classic');
    ps[0].got.clear();
    send(r, ps[0], {'t': 'deal'});
    expect(ps[0].last('err')?['error'], 'old_app');
    expect(r.game, isNull);
    for (final p in [ps[3], ps[4]]) { send(r, p, {'t': 'leave'}); }
    send(r, ps[0], {'t': 'deal'});
    expect(r.game, isNotNull);
    expect(r.game!.roles[r.game!.sheikh!], Role.mafia);
  });

  test('every phone on 1.0.0: the mode deals its deck; the guest sees the Godfather; Resume hosting keeps the mode and the Godfather', () {
    final r = newRoom(), ps = [for (var i = 0; i < 9; i++) Phone('p$i')];
    for (var i = 0; i < 9; i++) { expect(r.join(ps[i], id(i), build: modesBuild), isNull); }
    send(r, ps[0], {'t': 'setup', 'rules': defaultRules.toJson(), 'counts': {'mafia': 1, 'detective': 0}, 'buzzMax': 3, 'mode': 'all'});
    send(r, ps[0], {'t': 'deal'});
    final g = r.game!;
    expect([Role.sniper, Role.jester].every(g.roles.contains), isTrue);
    final m = [for (var i = 0; i < 9; i++) if (g.roles[i] == Role.mafia) i];
    expect(ps[m.first].view!['sheikh'], g.sheikh);
    // his ruling: on reveal the Godfather is named (the result says so to every phone)
    final s = g..alive[g.sheikh!] = false;
    final shown = viewJson(viewFor(GameState(deal: s.deal, names: s.names, roles: s.roles, alive: s.alive, rules: s.rules, mode: s.mode, sheikh: s.sheikh,
        phase: Phase.morning, day: 1, night: Night(), skipUsed: false, lastTarget: null, lastProt: SplayTreeMap(), morning: Morning(s.sheikh, null),
        timer: s.timer, vote: null, verdict: null, winner: null, log: [], stats: Stats()), null, 0));
    expect(shown['result'], {'k': 'killed', 'seat': s.sheikh, 'role': 'mafia', 'sheikh': true});
    s.alive[s.sheikh!] = true;
    final back = LocalRoom('123456', 'p0', restore: jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>, clock: () => 1, rng: seeded(1));
    expect(back.mode, 'all');
    expect(back.game!.sheikh, g.sheikh);
    expect(jsonEncode(back.rec!.toJson()), jsonEncode(r.rec!.toJson()));
  });
}
