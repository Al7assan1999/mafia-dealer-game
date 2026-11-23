// The game as a state machine: apply(state, action) -> new state + events (packages/engine/src/game.ts).
// Where the TypeScript iterates object keys, this iterates the same way: seat keys ascending (JavaScript orders
// integer keys first, ascending), then other keys ('skip', 'none') in insertion order; sorts are stable.
import 'dart:math' as math;

import 'types.dart';

List<int> aliveSeats(GameState s) => [for (var i = 0; i < s.alive.length; i++) if (s.alive[i]) i];
bool _seatOk(GameState s, Object? i) => i is int && i >= 0 && i < s.names.length;

/// Keys of a count map in JavaScript's order: integer keys ascending, then the rest in insertion order.
List<String> _jsKeys(Map<String, int> c) {
  final ints = c.keys.where((k) => int.tryParse(k) != null).map(int.parse).toList()..sort();
  return [...ints.map((x) => '$x'), ...c.keys.where((k) => int.tryParse(k) == null)];
}

/// What seat p may pick tonight (the target buttons).
NightOptions nightOptions(GameState s, int p) {
  final r = s.roles[p], R = s.rules, key = r == Role.citizen && !R.decoy ? 'none' : r.name;
  final res = NightOptions(key);
  if (key == 'none') return res;
  int mates(bool Function(Object v) pred) => s.night.mafia.entries.where((e) => e.key != p && pred(e.value)).length;
  for (final j in aliveSeats(s)) {
    final o = NightOption(j, j == p);
    if (r == Role.mafia && s.roles[j] == Role.mafia) { o.disabled = true; o.teammate = j != p; }
    if (r == Role.mafia && R.norep && s.lastTarget == j) { o.disabled = true; o.lastTarget = true; }
    if (r == Role.doctor) {
      if (j == p && !R.self) o.disabled = true;
      if (R.rep && s.lastProt[p] == j) { o.disabled = true; o.lastNight = true; }
    }
    if (r == Role.detective && j == p) o.disabled = true;
    if (r == Role.mafia) o.mateVotes = mates((v) => v == j);
    res.opts.add(o);
  }
  if (r == Role.mafia && R.skip && !s.skipUsed) res.skipMateVotes = mates((v) => v == 'skip');
  return res;
}

/// Winner when the Mafia are all gone, or as many as everyone else.
Winner? _winnerOf(GameState s) {
  final a = aliveSeats(s), m = a.where((i) => s.roles[i] == Role.mafia).length;
  return m == 0 ? Winner.citizens : m >= a.length - m ? Winner.mafia : null;
}

/// Seconds left on the discussion timer at `now`.
int timerLeft(GameState s, int now) {
  final t = s.timer;
  return t.running ? math.max(0, t.left - ((now - t.at) / 1000).floor()) : t.left;
}

/// Applies an action. Never changes the given state.
Applied apply(GameState prev, Action a, Ctx ctx) {
  final s = prev.copy(), ev = <GameEvent>[];
  Applied fail(String e) => Applied.fail(e);
  void phase(Phase p) { s.phase = p; ev.add(PhaseEvent(p, s.day)); }
  void log(GameEvent e) { s.log.add(e); ev.add(e); }
  void pauseTimer() { s.timer = DayTimer(false, timerLeft(s, ctx.now), 0); }
  void startNight() {
    s.night = Night(endsAt: s.rules.nightT != 0 ? ctx.now + s.rules.nightT * 1000 : 0);
    s.morning = null; s.verdict = null; s.vote = null;
    phase(Phase.night);
  }
  bool checkWin(Lead? lead) {
    final w = _winnerOf(s);
    if (w == null) return false;
    pauseTimer(); s.winner = w; log(WinLog(w, lead)); phase(Phase.end);
    return true;
  }

  void resolveNight() {
    // the Mafia's decision: the most votes among the living Mafia; a tie kills nobody (tieSkip) or, in older games, is
    // broken at random. A tie never spends the one-time skip.
    final votes = s.night.mafia.values.toList();
    int? target;
    var skip = false;
    if (votes.isNotEmpty) {
      final c = <String, int>{};
      for (final v in votes) { c['$v'] = (c['$v'] ?? 0) + 1; }
      final max = c.values.reduce(math.max), top = _jsKeys(c).where((k) => c[k] == max).toList();
      final w = top.length > 1 && s.rules.tieSkip ? null : top[(ctx.rng() * top.length).floor()];
      if (w == 'skip') { skip = true; s.skipUsed = true; } else if (w != null) { target = int.parse(w); }
    }
    final doc = s.night.doctor.entries.where((e) => e.value != null).map((e) => (e.key, e.value!)).toList();
    final prot = doc.map((d) => d.$2).toSet();
    s.lastProt = s.night.copy().doctor;
    final saved = target != null && prot.contains(target), dead = target != null && !saved ? target : null;
    if (dead != null) s.alive[dead] = false;
    log(NightLog(s.day, skip ? 'skip' : target == null ? 'none' : saved ? 'saved' : 'kill', skip ? null : target,
        doc.map((d) => d.$2).toList(), s.night.detective.values.whereType<int>().toList()));
    s.lastTarget = target;
    if (saved) { for (final d in doc) { if (d.$2 == target) s.stats.saves.add(d.$1); } }
    if (dead != null) { s.stats.first ??= dead; s.stats.kills.add(dead); }
    for (final e in s.night.detective.entries) {
      final p = e.key, q = e.value;
      if (q != null && s.roles[q] == Role.mafia && !s.stats.caught.any((x) => x.$1 == p && x.$2 == q)) s.stats.caught.add((p, q));
    }
    s.morning = Morning(dead, saved && s.rules.saverev ? target : null);
    if (checkWin(dead != null ? Lead('killed', dead) : null)) return;
    phase(Phase.morning);
  }

  void verdict(int? out, String kind, List<TallyLine>? tally) {
    pauseTimer();
    if (out != null) { s.alive[out] = false; s.stats.outs.add(out); }
    s.verdict = Verdict(out, kind, tally);
    log(DayLog(s.day, out, kind, tally));
    if (checkWin(out != null ? Lead('votedOut', out) : null)) return;
    phase(Phase.verdict);
  }

  void tally() {
    final c = <String, int>{};
    for (final v in s.vote!.votes.values) {
      if (v != 'abstain' && (s.rules.skipVote || v != 'none')) c['$v'] = (c['$v'] ?? 0) + 1;
    }
    if (c.isEmpty) return verdict(null, 'skipped', []);
    final max = c.values.reduce(math.max), keys = _jsKeys(c), top = keys.where((k) => c[k] == max).toList();
    final order = [for (var i = 0; i < keys.length; i++) i]..sort((x, y) => c[keys[y]]! - c[keys[x]]! != 0 ? c[keys[y]]! - c[keys[x]]! : x - y);
    final lines = order.map((i) => TallyLine(keys[i] == 'none' ? 'none' : int.parse(keys[i]), c[keys[i]]!)).toList();
    if (top.length > 1) {
      verdict(null, 'tie', lines);
    } else if (top[0] == 'none') {
      verdict(null, 'skipped', lines);
    } else {
      verdict(int.parse(top[0]), 'out', lines);
    }
  }

  /// Moves on once everyone alive has acted or voted.
  void settle() {
    if (s.phase == Phase.night && aliveSeats(s).every(s.night.done.contains)) {
      resolveNight();
    } else if (s.phase == Phase.vote && aliveSeats(s).every(s.vote!.votes.containsKey)) {
      tally();
    }
  }

  switch (a.t) {
    case 'begin':
      if (s.phase != Phase.deal) return fail('phase');
      startNight();

    case 'night':
      if (s.phase != Phase.night) return fail('phase');
      if (a.day != null && a.day != s.day) return fail('stale');
      if (!_seatOk(s, a.seat)) return fail('seat');
      final seat = a.seat!;
      if (!s.alive[seat]) return fail('dead');
      if (s.night.done.contains(seat)) return fail('done');
      final no = nightOptions(s, seat);
      final ok = no.key == 'none' || (a.choice == 'skip' ? no.canSkip : no.opts.any((o) => o.seat == a.choice && !o.disabled));
      if (!ok) return fail('choice');
      final r = s.roles[seat];
      if (r == Role.mafia) s.night.mafia[seat] = a.choice!;
      if (r == Role.doctor) s.night.doctor[seat] = a.choice as int;
      if (r == Role.detective) s.night.detective[seat] = a.choice as int;
      s.night.done.add(seat);
      settle();

    case 'skipPending': // "Continue anyway" for offline players, or the night timer ran out (no seats = everyone pending)
      if (s.phase != Phase.night && s.phase != Phase.vote) return fail('phase');
      final seats = a.seats ?? aliveSeats(s);
      if (!seats.every((i) => _seatOk(s, i))) return fail('seat');
      for (final i in seats) {
        if (!s.alive[i]) continue;
        if (s.phase == Phase.night) {
          s.night.done.add(i);
        } else {
          s.vote!.votes.putIfAbsent(i, () => 'abstain');
        }
      }
      if (s.phase == Phase.night && a.seats == null) s.night.endsAt = 0;
      settle();

    case 'startDay':
      if (s.phase != Phase.morning) return fail('phase');
      s.timer = DayTimer(false, s.rules.timer, 0);
      phase(Phase.day);

    case 'timer':
      if (s.phase != Phase.day) return fail('phase');
      if (a.op == 'start') {
        if (!s.timer.running) s.timer = DayTimer(true, s.timer.left, ctx.now);
      } else if (a.op == 'pause') {
        pauseTimer();
      } else if (a.op == 'reset') {
        s.timer = DayTimer(false, s.rules.timer, 0);
      } else if (a.op == 'add') {
        final sec = a.sec;
        if (sec == null || sec <= 0 || sec > 3600) return fail('choice');
        s.timer = DayTimer(s.timer.running, timerLeft(s, ctx.now) + sec, s.timer.running ? ctx.now : 0);
      } else {
        return fail('unknown');
      }

    case 'startVote':
      if (s.phase != Phase.day) return fail('phase');
      pauseTimer();
      s.vote = Vote(ctx.now, a.open == true);
      phase(Phase.vote);

    case 'vote':
      if (s.phase != Phase.vote) return fail('phase');
      if (a.id != null && a.id != s.vote!.id) return fail('stale');
      if (!_seatOk(s, a.seat)) return fail('seat');
      final seat = a.seat!;
      if (!s.alive[seat]) return fail('dead');
      if (s.vote!.votes.containsKey(seat)) return fail('done');
      final ch = a.choice;
      if (!(ch == 'none' || (_seatOk(s, ch) && s.alive[ch as int] && ch != seat))) return fail('choice');
      s.vote!.votes[seat] = ch!;
      settle();

    case 'decide': // the table decides together (one phone)
      if (s.phase != Phase.day) return fail('phase');
      final ch = a.choice;
      if (!(ch == 'none' || (_seatOk(s, ch) && s.alive[ch as int]))) return fail('choice');
      verdict(ch == 'none' ? null : ch as int, ch == 'none' ? 'skipped' : 'out', null);

    case 'nextNight':
      if (s.phase != Phase.verdict) return fail('phase');
      s.day++;
      startNight();

    case 'remove': // the host removes a player mid-game: counts as an elimination
      if (s.phase == Phase.deal || s.phase == Phase.end) return fail('phase');
      if (!_seatOk(s, a.seat)) return fail('seat');
      final seat = a.seat!;
      if (!s.alive[seat]) return fail('dead');
      s.alive[seat] = false;
      s.vote?.votes.remove(seat);
      s.night.done.add(seat);
      log(RemovedLog(seat));
      // a removal can decide the game (the last Mafia, or the Mafia reach parity): it ends at once
      if (!checkWin(null)) settle();

    default:
      return fail('unknown');
  }
  return Applied(s, ev);
}
