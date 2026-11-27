// What each seat may see, and the player of the game (packages/engine/src/view.ts).
import 'game.dart';
import 'types.dart';

/// The public result on screen in the morning / after a verdict. role only when the reveal rule is on.
class ShownResult {
  final String k; // 'killed' | 'saved' | 'nobody' | 'out' | 'tie' | 'skipped'
  final int? seat;
  final Role? role;
  final List<TallyLine>? tally;
  final Shown? also; // 'killed': a second death (1.0.0)
  final bool sheikh; // the revealed role is the Godfather's (his ruling: named on reveal)
  final bool framer; // 1.3.0 (Quin Q13): the revealed Mafia was the Framer
  final bool silencer; // 1.4.0 (Quin Q10): the revealed Mafia was the Silencer
  // 1.4.0, games with the Serial Killer or Cupid: a third death and on (more); who died of a broken heart (hearts)
  final List<Shown>? more, hearts;
  const ShownResult(this.k, {this.seat, this.role, this.tally, this.also, this.sheikh = false, this.framer = false, this.silencer = false, this.more, this.hearts});
}

/// One death on screen: the seat, and its role with the reveal rule (1.4.0).
typedef Shown = ({int seat, Role? role, bool sheikh, bool framer, bool silencer});

/// The Hunter's shot on screen: who shot whom (role and flags with the reveal rule), and the broken hearts it caused.
typedef Hunted = ({int by, int? seat, Role? role, bool sheikh, bool framer, bool silencer, List<Shown>? hearts});

class Recap {
  final Winner winner;
  final List<String> names;
  final List<Role> roles;
  final List<bool> alive;
  final int day;
  final Stats stats;
  final Mode mode;
  final int? sheikh;
  final int? framer; // 1.3.0
  final int? silencer; // 1.4.0
  const Recap(this.winner, this.names, this.roles, this.alive, this.day, this.stats, [this.mode = 'classic', this.sheikh, this.framer, this.silencer]);
}

/// What everyone may see (the table screen); a seat's view adds its own part.
class View {
  final int deal;
  final Phase phase;
  final int day;
  final List<({String name, bool alive})> roster;
  final int? timerEnd, timerLeft; // night timer end / running discussion timer end (ms), or the paused seconds
  final ({int done, int total})? progress;
  List<({int seat, Object? v})>? board; // open vote only (and for out players: every vote, 1.1.1)
  final int? voteId;
  final ShownResult? result;
  final Winner? winner;
  List<Role>? roles; // at the end only (and for ghosts)
  final Recap? recap;
  // 1.3.0, only in games with the role (null otherwise): the revealed Mayors; the Hunter taking aim; his shot, while
  // its morning or verdict is on screen (role only with the reveal rule)
  List<int>? mayors;
  ({int seat})? hunt;
  bool hasHunt = false; // the game has a Hunter (hunt / hunted are meaningful)
  Hunted? hunted;
  bool hasSilencer = false; // 1.4.0: the game has a Silencer (silenced is meaningful)
  int? silenced; // 1.4.0: who can't vote today (public, R8)

  // a seat's own part (null / defaults for the table)
  int? seat;
  Role? role;
  bool alive = true;
  List<int> mates = const [];
  int? sheikh; // the Sheikh's seat (Mafia only; may be this seat)
  ({int seat, bool mafia})? check;
  List<({int seat, bool mafia})>? checks; // 1.1.0, Detective: every result so far (his role card)
  String ph = 'table'; // 'night' | 'nightDone' | 'vote' | 'voted' | 'dead' | 'table' | 'end' | 'hunt' (1.3.0: this dead Hunter aims)
  NightOptions? night;
  List<({int seat, bool disabled})>? voteOpts;
  int? framer; // 1.3.0: the Framer's seat (Mafia only; may be this seat)
  ({int seat, bool hit})? framed; // 1.3.0, the Framer: last night's frame, and whether a Detective checked it
  List<({int seat, List<int> visitors})>? watch; // 1.3.0, the Watcher: every result so far, the last one last
  List<int>? huntOpts; // ph 'hunt': who he may shoot
  int? silencer; // 1.4.0: the Silencer's seat (Mafia only; may be this seat)
  ({int seat, String side})? lover; // 1.4.0, a lover: the partner and their side ('mafia' | 'town', R4)

  View._(this.deal, this.phase, this.day, this.roster, this.timerEnd, this.timerLeft, this.progress, this.board,
      this.voteId, this.result, this.winner, this.roles, this.recap);
}

View _publicView(GameState s, int now) {
  final al = aliveSeats(s), R = s.rules;
  int? end, left;
  if (s.hunt != null && s.hunt!.endsAt != 0) {
    end = s.hunt!.endsAt;
  } else if (s.phase == Phase.night && s.night.endsAt != 0) {
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
  bool fr(int i) => R.reveal && i == s.framer && !sh(i); // 1.3.0: the Framer, named on reveal
  bool sl(int i) => R.reveal && i == s.silencer && !sh(i) && !fr(i); // 1.4.0 [Quin Q10]: the Silencer, named on reveal
  Shown shown(int i) => (seat: i, role: R.reveal ? s.roles[i] : null, sheikh: sh(i), framer: fr(i), silencer: sl(i));
  if (s.phase == Phase.morning && s.morning != null) {
    final d = s.morning!.dead, d2 = s.morning!.dead2, more = (s.morning!.deaths ?? const <int>[]).skip(2).toList(), hearts = s.morning!.hearts ?? const <int>[];
    result = d != null
        ? ShownResult('killed', seat: d, role: R.reveal ? s.roles[d] : null, sheikh: sh(d), framer: fr(d), silencer: sl(d),
            also: d2 == null ? null : shown(d2),
            more: more.isEmpty ? null : more.map(shown).toList(), hearts: hearts.isEmpty ? null : hearts.map(shown).toList())
        : s.morning!.saved != null ? ShownResult('saved', seat: s.morning!.saved) : const ShownResult('nobody');
  } else if (s.phase == Phase.verdict && s.verdict != null) {
    final v = s.verdict!, hearts = s.log.whereType<DayLog>().lastOrNull?.hearts ?? const <int>[];
    result = v.out != null
        ? ShownResult('out', seat: v.out, role: R.reveal ? s.roles[v.out!] : null, sheikh: sh(v.out!), framer: fr(v.out!), silencer: sl(v.out!), tally: v.tally,
            hearts: hearts.isEmpty ? null : hearts.map(shown).toList())
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
    isEnd ? Recap(s.winner!, s.names, s.roles, s.alive, s.day, s.stats, s.mode, s.sheikh, s.framer, s.silencer) : null,
  )
    ..hasSilencer = s.silencer != null
    ..silenced = s.silencer != null ? s.silenced : null
    ..mayors = s.roles.contains(Role.mayor) ? [...s.mayors] : null
    ..hasHunt = s.roles.contains(Role.hunter)
    ..hunt = s.hunt == null ? null : (seat: s.hunt!.seat)
    ..hunted = _hunted(s, shown);
}

Hunted? _hunted(GameState s, Shown Function(int) shown) {
  final h = s.log.whereType<HuntLog>().firstOrNull;
  if (h == null || h.day != s.day || !((s.phase == Phase.morning && h.from == 'night') || (s.phase == Phase.verdict && h.from == 'day'))) return null;
  final t = h.target == null ? null : shown(h.target!);
  return (by: h.seat, seat: h.target, role: t?.role, sheikh: t?.sheikh ?? false, framer: t?.framer ?? false, silencer: t?.silencer ?? false,
      hearts: h.hearts == null || h.hearts!.isEmpty ? null : h.hearts!.map(shown).toList());
}

/// What one seat's phone may show; null = only the public part (the table screen).
View viewFor(GameState s, int? who, int now) {
  final v = _publicView(s, now);
  if (who == null) return v;
  final i = who, r = s.roles[i], reads = readsOf(s);
  // 1.3.0: with a Framer, tonight's result waits for the morning (the frame may not be in yet), then reads from the log
  final q = r == Role.detective && !(s.framer != null && s.phase == Phase.night) ? s.night.detective[i] : null;
  final lastNight = s.log.whereType<NightLog>().lastOrNull;
  v
    ..seat = i
    ..role = r
    ..alive = s.alive[i]
    ..mates = r == Role.mafia ? [for (var j = 0; j < s.roles.length; j++) if (s.roles[j] == Role.mafia && j != i) j] : []
    ..sheikh = r == Role.mafia ? s.sheikh : null
    ..check = q != null ? (seat: q, mafia: s.framer != null ? reads[q] ?? false : s.roles[q] == Role.mafia && q != s.sheikh) : null // the Sheikh reads "not Mafia"
    ..checks = s.rv != null && r == Role.detective ? [for (final e in reads.entries) (seat: e.key, mafia: e.value)] : null;
  if (s.framer != null && r == Role.mafia) {
    v.framer = s.framer;
    // last night's frame: from the morning until his next night turn is over (pass-and-play shows it on that turn)
    final fresh = lastNight != null && (s.phase == Phase.night ? lastNight.day == s.day - 1 : lastNight.day == s.day);
    if (i == s.framer) v.framed = fresh ? lastNight.frame : null;
  }
  if (s.silencer != null && r == Role.mafia) v.silencer = s.silencer;
  final l = s.lovers; // 1.4.0: each lover learns the other and their side, once Cupid's night is over (R4)
  if (l != null && (l.$1 == i || l.$2 == i)) {
    final o = l.$1 == i ? l.$2 : l.$1;
    v.lover = (seat: o, side: s.roles[o] == Role.mafia ? 'mafia' : 'town');
  }
  if (r == Role.watcher) {
    v.watch = [for (final e in s.log) if (e is NightLog) for (final (w, t, vs) in e.watch ?? const <(int, int, List<int>)>[]) if (w == i) (seat: t, visitors: vs)];
  }
  if (s.phase == Phase.end) {
    v.ph = 'end';
  } else if (s.hunt?.seat == i) { // 1.3.0: no ghost view before his shot (E-H8)
    v.ph = 'hunt';
    v.huntOpts = [for (final j in aliveSeats(s)) if (j != i) j];
  } else if (!s.alive[i]) {
    v.ph = 'dead';
    if (s.rules.ghost) v.roles = [...s.roles];
    // [1.1.1 hotfix] an out player (the host too) follows the vote live, open or secret: they can't vote any more
    if (s.phase == Phase.vote) v.board = [for (final k in aliveSeats(s)) (seat: k, v: s.vote!.votes[k])];
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

/// Player of the game, with the reason ('mafia' | 'mafia2' | 'det' | 'doc' | 'guard' | 'hunter' | 'surv' | 'jester' | 'killer' | 'lovers'); the app writes the text.
({int seat, String why, int? n})? mvp(Winner winner, List<Role> roles, List<bool> alive, Stats stats) {
  final idx = [for (var i = 0; i < roles.length; i++) i];
  if (winner == Winner.jester) {
    final j = roles.indexOf(Role.jester);
    return j < 0 ? null : (seat: j, why: 'jester', n: null);
  }
  // 1.4.0: the Serial Killer's win is his; the Lovers' win goes to the first of the couple; a draw has no player of the game
  if (winner == Winner.killer) {
    final k = roles.indexOf(Role.killer);
    return k < 0 ? null : (seat: k, why: 'killer', n: null);
  }
  if (winner == Winner.lovers) return stats.lovers == null ? null : (seat: stats.lovers!.$1, why: 'lovers', n: null);
  if (winner == Winner.draw) return null;
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
  final b = top(stats.guards.map((x) => x.$1).toList());
  if (b != null) return (seat: b.$1, why: 'guard', n: b.$2);
  final h = stats.hunts.where((x) => roles[x.$2] == Role.mafia).firstOrNull; // 1.3.0: shot a Mafia
  if (h != null) return (seat: h.$1, why: 'hunter', n: null);
  final sv = idx.where((i) => alive[i] && roles[i] != Role.mafia && roles[i] != Role.jester).toList();
  return sv.isNotEmpty ? (seat: sv.first, why: 'surv', n: null) : null;
}
