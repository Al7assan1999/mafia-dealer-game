import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/prefs.dart';

// The offline game on one phone: the Dart engine judges, this follows the phone round the table (who holds it,
// which screen), narrates, and keeps the game on the phone so it survives the app being killed. Nothing is logged.

/// Which screen the phone shows. The engine's phase can be ahead (the night resolves on the last pick, but the phone
/// still shows that player "locked" and then "the night is over").
/// [S20] huntPass / huntPick: the phone goes to the dead Hunter; shot: his shot (or held fire) for the table.
enum Screen { dealPass, dealCard, nightPass, nightPick, nightLocked, dawn, morning, day, ballotPass, ballotPick, ballotVoted, verdict, end,
  huntPass, huntPick, shot }

class OfflineGame extends ChangeNotifier {
  OfflineGame._(this.prefs, this.audio, this.rec, this.s, this.screen, this.who, this.revealed);

  final Prefs prefs;
  final Audio audio;
  GameRecord rec;
  GameState s;
  Screen screen;
  int who;        // the seat holding the phone (deal, night, ballot)
  bool revealed;  // the suspense reveal of the morning / verdict / end
  Timer? _arm, _nightT;
  bool _timeUpSaid = false;
  static final _rng = Random.secure();

  static double rng() => _rng.nextDouble();
  /// The clock (ms); tests replace it.
  static int Function() clock = () => DateTime.now().millisecondsSinceEpoch;
  static int now() => clock();

  /// Deals a new game (or the setup error).
  static ({OfflineGame? game, String? error}) start(Prefs prefs, Audio audio, Setup setup, [int deal = 1]) {
    final c = createGame(setup, rng, deal);
    if (c.error != null) return (game: null, error: c.error);
    final g = OfflineGame._(prefs, audio, startRecord(c.state!), c.state!, Screen.dealPass, 0, true);
    g._save();
    audio.welcome();
    return (game: g, error: null);
  }

  /// The game saved on this phone, if any (replayed from its record).
  static OfflineGame? resume(Prefs prefs, Audio audio) {
    final j = prefs.game;
    if (j == null) return null;
    try {
      final r = replay(j['rec']);
      if (r.error != null) { prefs.game = null; return null; }
      final rec = recordFromJson(j['rec'] as Map<String, Object?>);
      final g = OfflineGame._(prefs, audio, rec, r.state!, Screen.values.byName(j['screen'] as String), j['who'] as int, true);
      g._watchNight();
      return g;
    } catch (_) {
      prefs.game = null;
      return null;
    }
  }

  void _save() {
    prefs.game = s.phase == Phase.end && screen == Screen.end && revealed
        ? null // a finished game is not kept (and never logged)
        : {'rec': rec.toJson(), 'screen': screen.name, 'who': who, 'day': s.day < 1 ? 1 : s.day}; // day: Home's "Resume game · Round N"
  }

  void _go(Screen to, {int? seat}) {
    screen = to;
    if (seat != null) who = seat;
    _save();
    notifyListeners();
  }

  bool _act(Action a) {
    final res = step(rec, s, a, Ctx(rng, now()));
    if (!res.ok) return false;
    s = res.state!;
    return true;
  }

  // ---------------------------------------------------------------- what the screens need
  int get n => s.names.length;
  List<int> get pendingNight => aliveSeats(s).where((i) => !s.night.done.contains(i)).toList();
  List<int> get pendingVote => s.vote == null ? [] : aliveSeats(s).where((i) => !s.vote!.votes.containsKey(i)).toList();
  View view([int? seat]) => viewFor(s, seat, now());

  // ---------------------------------------------------------------- deal
  void dealOpen(int seat) { if (screen == Screen.dealPass && who == seat) _go(Screen.dealCard); }
  void dealDone(int seat) {
    if (screen != Screen.dealCard || who != seat) return; // a second tap on the same button
    if (seat < n - 1) return _go(Screen.dealPass, seat: seat + 1);
    _act(const Action.begin());
    _startNight();
  }

  // ---------------------------------------------------------------- night
  void _startNight() {
    audio.night();
    _go(Screen.nightPass, seat: pendingNight.first);
    _watchNight();
  }

  /// The night timer: when it runs out, the turns not taken are skipped.
  void _watchNight() {
    _nightT?.cancel();
    if (s.phase != Phase.night || s.night.endsAt == 0) return;
    _nightT = Timer(Duration(milliseconds: max(0, s.night.endsAt - now())), () {
      if (s.phase != Phase.night) return;
      _act(const Action.skipPending());
      if (screen == Screen.nightPass || screen == Screen.nightPick) _go(Screen.dawn);
    });
  }

  void nightOpen(int seat) { if (screen == Screen.nightPass && who == seat) _go(Screen.nightPick); }
  /// [S20] frame: the Framer's frame (hasFrame with null = none); reveal: a Mayor reveals himself in the morning.
  /// [S21] silence: the Silencer's pick (hasSilence with null = nobody); pair: Cupid's second lover.
  void nightPick(int seat, Object? choice, {int? frame, bool hasFrame = false, bool? reveal, int? silence, bool hasSilence = false, int? pair}) {
    if (screen != Screen.nightPick || who != seat) return;
    if (_act(Action.nightWith(seat, choice, day: s.day, frame: frame, hasFrame: hasFrame, reveal: reveal, silence: silence, hasSilence: hasSilence,
        pair: pair, hasPair: pair != null))) {
      _go(Screen.nightLocked);
    }
  }
  void nightNext(int seat) {
    if (screen != Screen.nightLocked || who != seat) return;
    if (s.phase == Phase.night) return _go(Screen.nightPass, seat: pendingNight.first);
    _nightT?.cancel();
    _go(Screen.dawn);
  }

  /// "Reveal the morning": the phone is in the middle of the table now.
  void dawn() {
    if (screen != Screen.dawn) return;
    if (s.phase == Phase.end) return _end();
    revealed = false;
    _go(Screen.morning);
    final m = s.morning!, reveal = s.rules.reveal;
    audio.morning(m.dead == null ? null : s.names[m.dead!], m.dead != null && reveal ? s.roles[m.dead!].name : null,
        m.saved == null ? null : s.names[m.saved!], _armReveal, m.dead2 == null ? null : s.names[m.dead2!], m.dead2 != null && reveal ? s.roles[m.dead2!].name : null);
  }

  // ---------------------------------------------------------------- suspense
  void _armReveal(double sec) {
    _arm?.cancel();
    _arm = Timer(Duration(milliseconds: (max(sec, 0) * 1000).round()), reveal);
  }

  /// The result appears (the narrator reached the name, the fallback timer ran out, or "Reveal now").
  void reveal() {
    _arm?.cancel();
    if (revealed || !(screen == Screen.morning || screen == Screen.verdict || screen == Screen.end)) return;
    revealed = true;
    final bad = (screen == Screen.morning && s.morning?.dead != null) || (screen == Screen.verdict && s.verdict?.out != null) ||
        (screen == Screen.end && s.winner == Winner.mafia);
    if (screen != Screen.end) audio.hit(bad);
    _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- day
  void startDay() {
    if (!(screen == Screen.morning || screen == Screen.shot) || !_act(const Action.startDay())) return;
    _timeUpSaid = false;
    audio.day();
    _go(Screen.day);
  }

  void timer(String op) {
    if (screen != Screen.day) return;
    if (_act(op == 'add' ? const Action.timer('add', sec: 60) : Action.timer(op))) {
      if (op != 'pause') _timeUpSaid = false;
      _save();
      notifyListeners();
    }
  }

  /// Called every second by the day screen: the narrator says "time is up" once when the running timer hits 0.
  void tickDay() {
    if (screen == Screen.day && s.timer.running && timerLeft(s, now()) == 0 && !_timeUpSaid) {
      _timeUpSaid = true;
      audio.timeUp();
    }
  }

  /// The table decides together on this phone (a seat or 'none').
  void decide(Object choice) {
    if (screen != Screen.day || !_act(Action.decide(choice))) return;
    _afterVerdict();
  }

  void startBallot() {
    if (screen != Screen.day || !_act(const Action.startVote(false))) return;
    _go(Screen.ballotPass, seat: pendingVote.first);
  }
  void ballotOpen(int seat) { if (screen == Screen.ballotPass && who == seat) _go(Screen.ballotPick); }
  void ballotCast(int seat, Object choice) {
    if (screen != Screen.ballotPick || who != seat) return;
    if (_act(Action.vote(seat, choice, id: s.vote!.id))) _go(Screen.ballotVoted);
  }
  void ballotNext(int seat) {
    if (screen != Screen.ballotVoted || who != seat) return;
    if (s.phase == Phase.vote) return _go(Screen.ballotPass, seat: pendingVote.first);
    _afterVerdict();
  }

  void _afterVerdict() {
    if (s.phase == Phase.end) return _end();
    revealed = false;
    _go(Screen.verdict);
    final v = s.verdict!;
    audio.verdict(v.out == null ? null : s.names[v.out!], v.out != null && s.rules.reveal ? s.roles[v.out!].name : null, v.kind, _armReveal);
  }

  void nextNight() {
    if (!(screen == Screen.verdict || screen == Screen.shot) || !_act(const Action.nextNight())) return;
    _startNight();
  }

  // ---------------------------------------------------------------- [S20] the Hunter
  /// "The Hunter takes aim": from the morning or the verdict, the phone goes to him.
  void huntStart() {
    final h = s.hunt;
    if (h == null || !(screen == Screen.morning || screen == Screen.verdict) || !revealed) return;
    _go(Screen.huntPass, seat: h.seat);
  }
  void huntOpen(int seat) { if (screen == Screen.huntPass && who == seat) _go(Screen.huntPick); }
  /// His shot (a seat) or null: hold fire.
  void huntShoot(int seat, int? target) {
    if (screen != Screen.huntPick || who != seat || !_act(Action.hunt(seat, target))) return;
    _afterShot();
  }
  // [Quin Q2] no timer on one phone: the night timer started when he died, and the dawn, the morning and passing the
  // phone would use it all up (E-H6: pass-and-play waits for him)
  void _afterShot() {
    if (s.phase == Phase.end) return _end();
    _go(Screen.shot);
  }

  // ---------------------------------------------------------------- end
  void _end() {
    revealed = false;
    _go(Screen.end);
    final win = s.log.whereType<WinLog>().last, lead = win.lead;
    final clips = lead == null ? <String?>[] : audio.lead(lead.k, s.names[lead.seat], s.rules.reveal ? s.roles[lead.seat].name : null);
    final mafia = [for (var i = 0; i < n; i++) if (s.roles[i] == Role.mafia) s.names[i]];
    if (s.winner == Winner.mafia) {
      audio.mafiaWin(mafia, clips, _armReveal);
    } else if (s.winner == Winner.jester) {
      audio.jesterWin(clips, _armReveal);
    } else if (s.winner != Winner.citizens) {
      audio.otherWin(clips, _armReveal); // [S21] the Serial Killer, the Lovers, a draw
    } else {
      audio.citizensWin(mafia, clips, _armReveal);
    }
  }

  /// The same players, new roles.
  OfflineGame? playAgain() {
    if (screen != Screen.end) return null;
    close();
    return start(prefs, audio, Setup(s.names, Counts(_count(Role.mafia), 1, _count(Role.detective)), s.rules, s.mode, _count(Role.bodyguard) > 0), s.deal + 1).game;
  }
  int _count(Role r) => s.roles.where((x) => x == r).length;

  /// Leaving to the start screen: the game stays saved unless it's over.
  void close() {
    _arm?.cancel();
    _nightT?.cancel();
    audio.stop();
    if (screen == Screen.end) prefs.game = null;
  }

  void discard() { close(); prefs.game = null; }
}
