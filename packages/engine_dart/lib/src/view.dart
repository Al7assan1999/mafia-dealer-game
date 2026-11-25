// What each seat may see, and the player of the game (packages/engine/src/view.ts).
import 'game.dart';
import 'types.dart';

/// The public result on screen in the morning / after a verdict. role only when the reveal rule is on.
class ShownResult {
  final String k; // 'killed' | 'saved' | 'nobody' | 'out' | 'tie' | 'skipped'
  final int? seat;
  final Role? role;
  final List<TallyLine>? tally;
  final ({int seat, Role? role, bool sheikh})? also; // 'killed': a second death (1.0.0)
  final bool sheikh; // the revealed role is the Godfather's (his ruling: named on reveal)
  const ShownResult(this.k, {this.seat, this.role, this.tally, this.also, this.sheikh = false});
}

class Recap {
  final Winner winner;
  final List<String> names;
  final List<Role> roles;
  final List<bool> alive;
  final int day;
  final Stats stats;
  final Mode mode;
  final int? sheikh;
  const Recap(this.winner, this.names, this.roles, this.alive, this.day, this.stats, [this.mode = 'classic', this.sheikh]);
}

/// What everyone may see (the table screen); a seat's view adds its own part.
class View {
  final int deal;
  final Phase phase;
  final int day;
  final List<({String name, bool alive})> roster;
  final int? timerEnd, timerLeft; // night timer end / running discussion timer end (ms), or the paused seconds
  final ({int done, int total})? progress;
  final List<({int seat, Object? v})>? board; // open vote only
  final int? voteId;
  final ShownResult? result;
  final Winner? winner;
  List<Role>? roles; // at the end only (and for ghosts)
  final Recap? recap;

  // a seat's own part (null / defaults for the table)
  int? seat;
  Role? role;
  bool alive = true;
  List<int> mates = const [];
  int? sheikh; // the Sheikh's seat (Mafia only; may be this seat)
  ({int seat, bool mafia})? check;
  String ph = 'table'; // 'night' | 'nightDone' | 'vote' | 'voted' | 'dead' | 'table' | 'end'
  NightOptions? night;
  List<({int seat, bool disabled})>? voteOpts;

  View._(this.deal, this.phase, this.day, this.roster, this.timerEnd, this.timerLeft, this.progress, this.board,
      this.voteId, this.result, this.winner, this.roles, this.recap);
}

View _publicView(GameState s, int now) {
  final al = aliveSeats(s), R = s.rules;
  int? end, left;
  if (s.phase == Phase.night && s.night.endsAt != 0) {
    end = s.night.endsAt;
  } else if (s.phase == Phase.day) {
    if (s.timer.running) {
      end = s.timer.at + s.timer.left * 1000;
    } else {
      left = timerLeft(s, now);
    }
  }
  final progress = s.phase == Phase.night
      ? (done: al.where(s.night.done.contains).length, total: al.length)
      : s.phase == Phase.vote ? (done: al.where(s.vote!.votes.containsKey).length, total: al.length) : null;
  ShownResult? result;
  bool sh(int i) => R.reveal && i == s.sheikh; // the Godfather, named on reveal
  if (s.phase == Phase.morning && s.morning != null) {
    final d = s.morning!.dead, d2 = s.morning!.dead2;
    result = d != null
        ? ShownResult('killed', seat: d, role: R.reveal ? s.roles[d] : null, sheikh: sh(d),
            also: d2 == null ? null : (seat: d2, role: R.reveal ? s.roles[d2] : null, sheikh: sh(d2)))
        : s.morning!.saved != null ? ShownResult('saved', seat: s.morning!.saved) : const ShownResult('nobody');
  } else if (s.phase == Phase.verdict && s.verdict != null) {
    final v = s.verdict!;
    result = v.out != null
        ? ShownResult('out', seat: v.out, role: R.reveal ? s.roles[v.out!] : null, sheikh: sh(v.out!), tally: v.tally)
        : ShownResult(v.kind == 'tie' ? 'tie' : 'skipped', tally: v.tally);
  }
  final isEnd = s.phase == Phase.end;
  return View._(
    s.deal, s.phase, s.day,
    [for (var i = 0; i < s.names.length; i++) (name: s.names[i], alive: s.alive[i])],
    end, left, progress,
    s.phase == Phase.vote && s.vote!.open ? [for (final k in al) (seat: k, v: s.vote!.votes[k])] : null,
    s.phase == Phase.vote ? s.vote!.id : null,
    result, s.winner,
    isEnd ? [...s.roles] : null,
    isEnd ? Recap(s.winner!, s.names, s.roles, s.alive, s.day, s.stats, s.mode, s.sheikh) : null,
  );
}

/// What one seat's phone may show; null = only the public part (the table screen).
View viewFor(GameState s, int? who, int now) {
  final v = _publicView(s, now);
  if (who == null) return v;
  final i = who, r = s.roles[i], q = r == Role.detective ? s.night.detective[i] : null;
  v
    ..seat = i
    ..role = r
    ..alive = s.alive[i]
    ..mates = r == Role.mafia ? [for (var j = 0; j < s.roles.length; j++) if (s.roles[j] == Role.mafia && j != i) j] : []
    ..sheikh = r == Role.mafia ? s.sheikh : null
    ..check = q != null ? (seat: q, mafia: s.roles[q] == Role.mafia && q != s.sheikh) : null; // the Sheikh reads "not Mafia"
  if (s.phase == Phase.end) {
    v.ph = 'end';
  } else if (!s.alive[i]) {
    v.ph = 'dead';
    if (s.rules.ghost) v.roles = [...s.roles];
  } else if (s.phase == Phase.night) {
    if (s.night.done.contains(i)) {
      v.ph = 'nightDone';
    } else {
      v.ph = 'night';
      v.night = nightOptions(s, i);
    }
  } else if (s.phase == Phase.vote) {
    if (s.vote!.votes.containsKey(i)) {
      v.ph = 'voted';
    } else {
      v.ph = 'vote';
      v.voteOpts = [for (final j in aliveSeats(s)) (seat: j, disabled: j == i)];
    }
  }
  return v;
}

/// Player of the game, with the reason ('mafia' | 'mafia2' | 'det' | 'doc' | 'surv' | 'jester'); the app writes the text.
({int seat, String why, int? n})? mvp(Winner winner, List<Role> roles, List<bool> alive, Stats stats) {
  final idx = [for (var i = 0; i < roles.length; i++) i];
  if (winner == Winner.jester) {
    final j = roles.indexOf(Role.jester);
    return j < 0 ? null : (seat: j, why: 'jester', n: null);
  }
  (int, int)? top(List<int> a) {
    final c = <int, int>{};
    for (final x in a) { c[x] = (c[x] ?? 0) + 1; }
    final keys = c.keys.toList()..sort(); // JavaScript: integer keys ascending, then a stable sort by count
    keys.sort((x, y) => c[y]! - c[x]! != 0 ? c[y]! - c[x]! : x - y);
    return keys.isEmpty ? null : (keys.first, c[keys.first]!);
  }
  if (winner == Winner.mafia) {
    final m = idx.where((i) => roles[i] == Role.mafia).toList(), al = m.where((i) => alive[i]).toList();
    return (seat: (al.isNotEmpty ? al : m).first, why: al.isNotEmpty ? 'mafia' : 'mafia2', n: null);
  }
  final c = top(stats.caught.map((x) => x.$1).toList());
  if (c != null) return (seat: c.$1, why: 'det', n: c.$2);
  final d = top(stats.saves);
  if (d != null) return (seat: d.$1, why: 'doc', n: d.$2);
  final sv = idx.where((i) => alive[i] && roles[i] != Role.mafia && roles[i] != Role.jester).toList();
  return sv.isNotEmpty ? (seat: sv.first, why: 'surv', n: null) : null;
}
