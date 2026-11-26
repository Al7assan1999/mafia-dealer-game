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
  final r = s.roles[p], R = s.rules, rv = s.rv != null;
  // the Jester, and the Sniper once his bullet is spent (1.1.0: or on night 1), pick like a Citizen; 1.3.0: the Hunter
  // and the Mayor too
  final k0 = r == Role.jester || r == Role.hunter || r == Role.mayor || (r == Role.sniper && (s.shotUsed || (rv && s.day == 1))) ? 'citizen' : r.name,
      key = k0 == 'citizen' && !R.decoy ? 'none' : k0;
  final res = NightOptions(key);
  if (r == Role.mayor && !s.mayors.contains(p)) res.reveal = true; // pass-and-play: reveal himself in the morning
  if (key == 'none') return res;
  int mates(bool Function(Object v) pred) => s.night.mafia.entries.where((e) => e.key != p && pred(e.value)).length;
  final past = rv && r == Role.detective ? readsOf(s) : null; // 1.1.0: never the same player twice
  final sh = s.sheikh, shPick = r == Role.mafia && sh != null && sh != p && s.alive[sh] ? s.night.mafia[sh] : null;
  for (final j in aliveSeats(s)) {
    final o = NightOption(j, j == p)..sheikh = shPick == j;
    if (r == Role.mafia && s.roles[j] == Role.mafia) { o.disabled = true; o.teammate = j != p; }
    if (r == Role.mafia && R.norep && s.lastTarget == j) { o.disabled = true; o.lastTarget = true; }
    if (r == Role.doctor) {
      if (j == p && !R.self) o.disabled = true;
      if (R.rep && s.lastProt[p] == j) { o.disabled = true; o.lastNight = true; }
    }
    if (r == Role.doctor && s.mayors.contains(j)) { o.disabled = true; o.mayor = true; } // 1.3.0: a revealed Mayor
    if ((key == 'detective' || key == 'sniper' || key == 'bodyguard' || key == 'watcher') && j == p) o.disabled = true;
    if (key == 'bodyguard' && s.lastGuard[p] == j) { o.disabled = true; o.lastNight = true; }
    if (past != null && past.containsKey(j)) { o.disabled = true; o.check = past[j]; }
    if (r == Role.mafia) o.mateVotes = mates((v) => v == j);
    res.opts.add(o);
  }
  if (r == Role.mafia && R.skip && !s.skipUsed) {
    res.skipMateVotes = mates((v) => v == 'skip');
    res.skipSheikh = shPick == 'skip';
  }
  if (key == 'sniper') res.skipMateVotes = 0; // keep the bullet
  if (r == Role.mafia && p == s.framer) res.frame = [for (final j in aliveSeats(s)) if (s.roles[j] != Role.mafia) j]; // 1.3.0: never a teammate
  // everyone else is already checked: nothing to pick tonight. 1.3.0: the same for any power left with no target, so a
  // night can never wait for a pick that can't be made
  if ((past != null || rv) && res.opts.every((o) => o.disabled) && !res.canSkip) return NightOptions('none')..reveal = res.reveal;
  return res;
}

/// 1.1.0: the players the Detectives checked on earlier nights (in the order first checked).
Set<int> checkedBefore(GameState s) => {for (final e in s.log) if (e is NightLog) ...e.checked};

/// 1.3.0: what each check read (seat → Mafia?), in the order first checked. A Framer's game keeps the reads in the log;
/// older games work them out from the roles, as before.
Map<int, bool> readsOf(GameState s) {
  final m = <int, bool>{};
  for (final e in s.log) {
    if (e is! NightLog) continue;
    for (var k = 0; k < e.checked.length; k++) {
      final q = e.checked[k];
      m[q] = e.read != null ? e.read![k] : s.roles[q] == Role.mafia && q != s.sheikh;
    }
  }
  return m;
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
  bool checkWin(Lead? lead, [Winner? forced]) {
    final w = forced ?? _winnerOf(s);
    if (w == null) return false;
    if (w == Winner.mafia && forced == null && s.hunt != null) return false; // 1.3.0: the Hunter shoots first (E-H1)
    s.hunt = null;
    pauseTimer(); s.winner = w; log(WinLog(w, lead)); phase(Phase.end);
    return true;
  }
  /// 1.3.0: a Hunter who just died takes aim before the game goes on, unless the town has already won (E-H2).
  void takeAim(List<int> seats, String from) {
    final h = seats.where((x) => s.roles[x] == Role.hunter).firstOrNull;
    if (h != null && _winnerOf(s) != Winner.citizens) s.hunt = (seat: h, from: from, endsAt: s.rules.nightT != 0 ? ctx.now + s.rules.nightT * 1000 : 0);
  }
  void shoot(int? target) {
    final h = s.hunt!;
    s.hunt = null;
    if (target != null) { s.alive[target] = false; s.stats.hunts.add((h.seat, target)); }
    log(HuntLog(s.day, h.seat, target, h.from));
    checkWin(target != null ? Lead('killed', target) : Lead(h.from == 'night' ? 'killed' : 'votedOut', h.seat));
  }

  void resolveNight() {
    // the Mafia's decision: the most votes among the living Mafia. A tie (1.0.0) goes to the Sheikh's pick, even one
    // nobody else made; with no pick from him (out, or didn't vote) to the lowest seat that voted for a tied pick.
    // Older games: a tie kills nobody (tieSkip, without spending the skip) or, before Sprint 7, a random pick.
    // 1.0.0: only the living count (a Mafia or the Sniper removed mid-night after choosing has no say)
    bool live(MapEntry<int, Object> e) => s.sheikh == null || s.alive[e.key];
    final votes = s.night.mafia.entries.where(live).toList(); // seats ascending
    int? target;
    var skip = false;
    if (votes.isNotEmpty) {
      final c = <String, int>{};
      for (final e in votes) { c['${e.value}'] = (c['${e.value}'] ?? 0) + 1; }
      final max = c.values.reduce(math.max), top = _jsKeys(c).where((k) => c[k] == max).toList();
      String? w;
      final sh = s.sheikh;
      if (sh == null) {
        w = top.length > 1 && s.rules.tieSkip ? null : top[(ctx.rng() * top.length).floor()];
      } else if (top.length == 1) {
        w = top[0];
      } else {
        final sv = s.alive[sh] ? s.night.mafia[sh] : null;
        w = sv != null ? '$sv' : '${votes.firstWhere((e) => top.contains('${e.value}')).value}';
      }
      if (w == 'skip') { skip = true; s.skipUsed = true; } else if (w != null) { target = int.parse(w); }
    }
    // the Sniper's one bullet: nothing stops it, not even the Doctor
    final sn = s.night.sniper.entries.where(live).where((e) => e.value != 'skip').firstOrNull, aim = sn?.value as int?;
    // 1.1.0, the Bodyguard: a kill or a shot at the player he guards goes to him instead (then the Doctor's save is
    // looked at for him; a bullet nobody stops)
    final bg = s.rv != null && s.roles.contains(Role.bodyguard);
    final guards = bg ? s.night.bodyguard.entries.where((e) => s.sheikh == null || s.alive[e.key]).toList() : <MapEntry<int, int?>>[];
    final took = s.stats.guards.length;
    int? cover(int? t) {
      final g = t == null || !s.alive[t] ? null : guards.where((e) => e.value == t && e.key != t).firstOrNull; // [Quin Q3] not for a removed player
      if (g == null) return t;
      final gs = s.stats.guards;
      var dup = false;
      for (var i = took; i < gs.length; i++) { if (gs[i].$1 == g.key && gs[i].$2 == t) dup = true; }
      if (!dup) gs.add((g.key, t!));
      return g.key;
    }
    final victim = cover(target), shot = cover(aim);
    final doc = s.night.doctor.entries.where((e) => e.value != null).map((e) => (e.key, e.value!)).toList();
    final prot = doc.map((d) => d.$2).toSet();
    s.lastProt = s.night.copy().doctor;
    if (bg) s.lastGuard = s.night.copy().bodyguard;
    final saved = victim != null && prot.contains(victim), dead = victim != null && !saved ? victim : null;
    final kept = saved && shot != victim; // a save the Sniper didn't undo
    // 1.3.0, before anyone dies (the night is one moment): the Framer's frame (not if the host removed him), what the
    // checks read, and who visited whom for the Watcher. One Mafia goes to the victim: the Sheikh if he voted for him,
    // else the lowest seat that did (E-W1).
    final fr = s.framer, framed = fr != null && s.alive[fr] ? s.night.frame[fr] : null;
    final checks = s.night.detective.values.whereType<int>().toList();
    final reads = [for (final q in checks) (s.roles[q] == Role.mafia && q != s.sheikh) || q == framed];
    final voters = target == null ? <int>[] : [for (final e in votes) if (e.value == target) e.key];
    final visits = <(int, int)>[
      for (final d in doc) (d.$1, d.$2),
      for (final g in guards) if (g.value != null) (g.key, g.value!),
      for (final e in s.night.detective.entries) if (e.value != null) (e.key, e.value!),
      if (framed != null) (fr!, framed),
      if (aim != null) (sn!.key, aim),
      if (voters.isNotEmpty) (s.sheikh != null && voters.contains(s.sheikh) ? s.sheikh! : voters.reduce(math.min), target!),
    ];
    final watch = [
      for (final e in s.night.watch.entries)
        if ((s.sheikh == null || s.alive[e.key]) && e.value != null)
          (e.key, e.value!, ({for (final v in visits) if (v.$2 == e.value && v.$1 != e.key) v.$1}.toList()..sort())),
    ];
    if (dead != null) s.alive[dead] = false;
    if (shot != null) { s.alive[shot] = false; s.shotUsed = true; s.stats.shots.add((sn!.key, shot)); }
    log(NightLog(s.day, skip ? 'skip' : victim == null ? 'none' : saved ? 'saved' : 'kill', skip ? null : victim,
        doc.map((d) => d.$2).toList(), checks, shot,
        bg ? guards.map((e) => e.value).whereType<int>().toList() : null,
        fr != null ? reads : null, fr != null && framed != null ? (seat: framed, hit: checks.contains(framed)) : null,
        s.roles.contains(Role.watcher) ? watch : null));
    s.lastTarget = target;
    if (kept) { for (final d in doc) { if (d.$2 == victim) s.stats.saves.add(d.$1); } }
    if (dead != null) { s.stats.first ??= dead; s.stats.kills.add(dead); }
    for (final e in s.night.detective.entries) {
      final p = e.key, q = e.value;
      if (q != null && s.roles[q] == Role.mafia && q != s.sheikh && !s.stats.caught.any((x) => x.$1 == p && x.$2 == q)) s.stats.caught.add((p, q));
    }
    // the morning names the dead in seat order: nobody can tell which death was the Sniper's
    final deaths = {?dead, ?shot}.toList()..sort();
    s.morning = Morning(deaths.firstOrNull, kept && s.rules.saverev ? target : null, deaths.length > 1 ? deaths[1] : null); // [Quin Q2, B15]
    // the death that decides the game leads its announcement: a Mafia shot by the Sniper when the town wins
    final lead = deaths.where((x) => s.roles[x] == Role.mafia && !aliveSeats(s).any((i) => s.roles[i] == Role.mafia)).firstOrNull ?? dead ?? shot;
    // 1.3.0, pass-and-play: a Mayor who chose to reveal himself on his turn, if he lived
    for (final m in s.night.reveal) {
      if (s.alive[m]) { s.mayors.add(m); log(RevealLog(s.day, m)); }
    }
    takeAim(deaths, 'night');
    if (checkWin(lead != null ? Lead('killed', lead) : null)) return;
    phase(Phase.morning);
  }

  void verdict(int? out, String kind, List<TallyLine>? tally) {
    pauseTimer();
    if (out != null) { s.alive[out] = false; s.stats.outs.add(out); }
    s.verdict = Verdict(out, kind, tally);
    log(DayLog(s.day, out, kind, tally));
    if (out != null) takeAim([out], 'day');
    // the Jester wins alone when the day vote puts him out
    if (checkWin(out != null ? Lead('votedOut', out) : null, out != null && s.roles[out] == Role.jester ? Winner.jester : null)) return;
    phase(Phase.verdict);
  }

  void tally() {
    final c = <String, int>{};
    for (final e in s.vote!.votes.entries) { // 1.3.0: a revealed Mayor's vote counts twice
      final v = e.value;
      if (v != 'abstain' && (s.rules.skipVote || v != 'none')) c['$v'] = (c['$v'] ?? 0) + (s.mayors.contains(e.key) ? 2 : 1);
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
      // [Quin Q1] 1.1.0: "nothing to pick" takes no pick (older records sent anything there)
      final ok = no.key == 'none' ? s.rv == null || a.choice == null : a.choice == 'skip' ? no.canSkip : no.opts.any((o) => o.seat == a.choice && !o.disabled);
      if (!ok) return fail('choice');
      // 1.3.0: the Framer's frame (null = none) and a Mayor's "reveal me in the morning" (pass-and-play)
      if (a.hasFrame && !(no.frame != null && (a.frame == null || no.frame!.contains(a.frame)))) return fail('choice');
      if (a.reveal != null && !(a.reveal == false || no.reveal)) return fail('choice');
      final r = s.roles[seat];
      if (r == Role.watcher) s.night.watch[seat] = a.choice as int?;
      if (a.frame != null) s.night.frame[seat] = a.frame;
      if (a.reveal == true) s.night.reveal.add(seat);
      if (r == Role.mafia) s.night.mafia[seat] = a.choice!;
      if (r == Role.doctor) s.night.doctor[seat] = a.choice as int;
      if (r == Role.detective) s.night.detective[seat] = a.choice as int?; // 1.1.0: null when everyone is checked
      if (no.key == 'sniper') s.night.sniper[seat] = a.choice!;
      if (r == Role.bodyguard) s.night.bodyguard[seat] = a.choice as int?;
      s.night.done.add(seat);
      settle();

    case 'skipPending': // "Continue anyway" for offline players, or the night timer ran out (no seats = everyone pending)
      final h = s.hunt;
      if (h != null) { // 1.3.0: the Hunter holds fire
        if (a.seats != null && !a.seats!.contains(h.seat)) return fail('seat');
        shoot(null);
        return Applied(s, ev);
      }
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

    case 'hunt': // 1.3.0: the dead Hunter's shot
      final h = s.hunt;
      if (h == null) return fail('phase');
      if (a.seat != h.seat) return fail('seat');
      final ch = a.choice;
      if (!a.hasChoice || !(ch == null || (_seatOk(s, ch) && s.alive[ch as int] && ch != a.seat))) return fail('choice');
      shoot(ch as int?);

    case 'reveal': // 1.3.0: a Mayor reveals himself, before the vote
      if (s.phase != Phase.morning && s.phase != Phase.day) return fail('phase');
      if (!_seatOk(s, a.seat)) return fail('seat');
      final seat = a.seat!;
      if (!s.alive[seat]) return fail('dead');
      if (s.roles[seat] != Role.mayor || s.mayors.contains(seat)) return fail('choice');
      s.mayors.add(seat);
      log(RevealLog(s.day, seat));

    case 'startDay':
      if (s.hunt != null) return fail('hunt');
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
      if (s.hunt != null) return fail('hunt');
      if (s.phase != Phase.verdict) return fail('phase');
      s.day++;
      startNight();

    case 'remove': // the host removes a player mid-game: counts as an elimination
      if (s.phase == Phase.deal || s.phase == Phase.end) return fail('phase');
      if (!_seatOk(s, a.seat)) return fail('seat');
      final seat = a.seat!;
      if (s.hunt?.seat == seat) { shoot(null); return Applied(s, ev); } // 1.3.0: removing the Hunter while he aims = he holds fire
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
