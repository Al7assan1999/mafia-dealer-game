// What the Wi-Fi host sends each phone: an engine view as JSON, in the server's shape (split out of local_room.dart).
import 'package:mafia_engine/mafia_engine.dart';

/// A view as JSON, exactly as the TypeScript engine's viewFor() serializes (the phones read the same shape online).
Map<String, Object?> viewJson(View v) {
  Map<String, Object?>? result() {
    final r = v.result;
    if (r == null) return null;
    return {'k': r.k, if (r.seat != null) 'seat': r.seat, if (r.k == 'killed' || r.k == 'out') 'role': r.role?.name, if (r.sheikh) 'sheikh': true, if (r.framer) 'framer': true,
      if (r.also != null) 'also': {'seat': r.also!.seat, 'role': r.also!.role?.name, if (r.also!.sheikh) 'sheikh': true, if (r.also!.framer) 'framer': true},
      if (r.k == 'out' || r.k == 'tie' || r.k == 'skipped') 'tally': r.tally?.map((x) => x.toJson()).toList()};
  }
  final rc = v.recap;
  return {
    'deal': v.deal, 'phase': v.phase.name, 'day': v.day,
    'roster': [for (final r in v.roster) {'name': r.name, 'alive': r.alive}],
    'timer': v.timerEnd != null ? {'end': v.timerEnd} : v.timerLeft != null ? {'left': v.timerLeft} : null,
    'progress': v.progress == null ? null : {'done': v.progress!.done, 'total': v.progress!.total},
    'board': v.board?.map((b) => {'seat': b.seat, 'v': b.v}).toList(),
    'voteId': v.voteId, 'result': result(), 'winner': v.winner?.name, 'roles': v.roles?.map((r) => r.name).toList(),
    'recap': rc == null ? null : {
      'winner': rc.winner.name, 'names': rc.names, 'roles': rc.roles.map((r) => r.name).toList(), 'alive': rc.alive, 'day': rc.day,
      'stats': {'first': rc.stats.first, 'kills': rc.stats.kills, 'outs': rc.stats.outs, 'saves': rc.stats.saves, 'caught': [for (final c in rc.stats.caught) [c.$1, c.$2]],
        'shots': [for (final c in rc.stats.shots) [c.$1, c.$2]], 'guards': [for (final c in rc.stats.guards) [c.$1, c.$2]],
        if (rc.stats.hunts.isNotEmpty) 'hunts': [for (final c in rc.stats.hunts) [c.$1, c.$2]]},
      if (rc.sheikh != null) 'mode': rc.mode,
      if (rc.sheikh != null) 'sheikh': rc.sheikh,
      if (rc.framer != null) 'framer': rc.framer,
    },
    // [S20] only in games with the role, as the TypeScript view
    if (v.mayors != null) 'mayors': v.mayors,
    if (v.hasHunt) 'hunt': v.hunt == null ? null : {'seat': v.hunt!.seat},
    if (v.hasHunt) 'hunted': v.hunted == null ? null : {'by': v.hunted!.by, 'seat': v.hunted!.seat, 'role': v.hunted!.role?.name},
    if (v.seat != null) ...{
      'seat': v.seat, 'role': v.role?.name, 'alive': v.alive, 'mates': v.mates, 'sheikh': v.sheikh,
      'check': v.check == null ? null : {'seat': v.check!.seat, 'mafia': v.check!.mafia},
      'checks': v.checks?.map((c) => {'seat': c.seat, 'mafia': c.mafia}).toList(),
      'ph': v.ph,
      'night': v.night == null ? null : {
        'key': v.night!.key,
        'opts': [for (final o in v.night!.opts) {'seat': o.seat, 'disabled': o.disabled, 'self': o.self, 'teammate': o.teammate, 'lastTarget': o.lastTarget, 'lastNight': o.lastNight, 'mateVotes': o.mateVotes, 'sheikh': o.sheikh, if (o.check != null) 'check': o.check, if (o.mayor) 'mayor': true}],
        'skip': v.night!.canSkip ? {'mateVotes': v.night!.skipMateVotes, 'sheikh': v.night!.skipSheikh} : null,
        if (v.night!.frame != null) 'frame': v.night!.frame,
        if (v.night!.reveal) 'reveal': true,
      },
      // [S20]
      if (v.framer != null) 'framer': v.framer,
      if (v.role == Role.mafia && v.seat == v.framer) 'framed': v.framed == null ? null : {'seat': v.framed!.seat, 'hit': v.framed!.hit},
      if (v.watch != null) 'watch': [for (final w in v.watch!) {'seat': w.seat, 'visitors': w.visitors}],
      if (v.huntOpts != null) 'huntOpts': v.huntOpts,
      'voteOpts': v.voteOpts?.map((o) => {'seat': o.seat, 'disabled': o.disabled}).toList(),
    },
  };
}
