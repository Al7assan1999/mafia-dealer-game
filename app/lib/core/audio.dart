import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:mafia_dealer/core/prefs.dart';

// Sound effects (rendered from the old app's procedural sounds) and the recorded English narrator. The narration
// recipes are the old app's (narrator.ts): which clips, which delays, and when the suspense reveal fires.

class Audio {
  Audio(this.prefs);
  final Prefs prefs;

  /// Tests (and phones where audio fails) run silent: no players, but every callback still fires.
  static bool silent = false;

  /// Online with "This phone narrates" off: no voice or sounds; the suspense still opens on the fallback timers.
  bool muted = false;

  final _rand = Random();
  Map<String, String> _alias = {};
  AudioPlayer? _voice;
  int _tok = 0;

  Future<void> init() async {
    try {
      _alias = (jsonDecode(await rootBundle.loadString('assets/voice/names.json')) as Map).cast<String, String>();
    } catch (_) {}
  }

  String _pick(List<String> a) => a[_rand.nextInt(a.length)];

  /// A player without position tracking (the app never shows playback position; the default asks for every frame).
  static AudioPlayer _player() => AudioPlayer()..positionUpdater = null;

  // ---------------------------------------------------------------- sound effects
  /// `always`: also when this phone's narration is off (a buzz or a ping, R7).
  void sfx(String name, [double delay = 0, bool always = false]) {
    if (silent || (muted && !always) || prefs.sfx <= 0) return;
    Future.delayed(Duration(milliseconds: (delay * 1000).round()), () async {
      try {
        final p = _player();
        p.onPlayerComplete.first.then((_) => p.dispose());
        await p.play(AssetSource('sfx/$name.wav'), volume: prefs.sfx);
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------- narrator
  void stop() { _tok++; _voice?.stop(); }

  /// Plays the clips one after another after [delay] s; at(i) fires when clip i starts (a null clip takes no time),
  /// at(keys.length) at the end. With the voice off nothing plays and nothing fires (the caller's fallback timer runs).
  Future<void> say(List<String?> keys, {double delay = 0, void Function(int i)? at}) async {
    final my = ++_tok;
    if (muted) return; // the suspense opens on the caller's fallback timer
    if (silent) { for (var i = 0; i <= keys.length; i++) { at?.call(i); } return; }
    if (prefs.voice <= 0) return;
    await _voice?.stop();
    await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
    for (var i = 0; i <= keys.length; i++) {
      if (my != _tok) return;
      at?.call(i);
      if (i == keys.length || keys[i] == null || silent) continue;
      try {
        final v = _voice ??= _player();
        final done = v.onPlayerComplete.first;
        await v.play(AssetSource('voice/${keys[i]}.ogg'), volume: prefs.voice);
        await done.timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
  }

  /// The name clip for a player's name, if the narrator knows it (monster voice for the dead).
  String? name(String n, {bool monster = false}) {
    final k = norm(n), c = _alias[k] ?? _alias[k.split(' ').first];
    return c == null || !monster ? c : 'm_${c.substring(2)}';  // every n_ clip has an m_ twin
  }

  static String norm(String n) => n.toLowerCase().trim()
      .replaceAll(RegExp('[ً-ْـ]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه')
      .replaceAll(RegExp("[-'’.]"), '').replaceAll(RegExp(r'\s+'), ' ');

  // ---------------------------------------------------------------- the game's narration
  // `arm(s)` asks for the suspense reveal in s seconds (the last call wins).
  void welcome() { sfx('shuffle'); say(['v_welcome'], delay: .8); }
  void night() { sfx('night'); say([_pick(['v_night_1', 'v_night_2', 'v_night_3', 'v_night_4', 'v_night_5'])], delay: 2.4); }
  void day() { sfx('day_start'); say([_pick(['v_day', 'v_day_2'])], delay: .4); }
  void timeUp() { sfx('time_up'); say(['v_timeup'], delay: 1.1); }

  /// "They were: …" (recorded for the four first roles only; the newer ones are shown, not said)
  static String? _was(String? role) => const {'mafia', 'doctor', 'detective', 'citizen'}.contains(role) ? 'v_was_$role' : null;

  void morning(String? dead, String? role, String? saved, void Function(double) arm, [String? dead2, String? role2]) {
    sfx(dead != null ? 'morning_dead' : 'morning_safe');
    arm(dead != null ? 3.6 : 4.4);
    if (dead != null) {
      say([_pick(['v_killed_1', 'v_killed_2', 'v_killed_3']), name(dead, monster: true), _was(role),
          if (dead2 != null) ...[name(dead2, monster: true), _was(role2)]], delay: 2.8, at: (i) { if (i == 1) arm(0); });
    } else if (saved != null) {
      say([_pick(['v_saved_1', 'v_saved_2']), name(saved)], delay: 3.4, at: (i) { if (i == 1) arm(0); });
    } else {
      say([_pick(['v_safe_1', 'v_safe_2', 'v_safe_3'])], delay: 3.4, at: (i) { if (i == 0) arm(1.2); });
    }
  }

  void verdict(String? out, String? role, String kind, void Function(double) arm) {
    sfx('verdict');
    arm(1.4);
    if (out != null) {
      say([_pick(['v_vote_out', 'v_vote_out_2']), name(out), _was(role)], delay: 1.3, at: (i) { if (i == 1) arm(0); });
    } else {
      say([kind == 'tie' ? 'v_vote_tie' : 'v_vote_none'], delay: 1.2, at: (i) { if (i == 0) arm(.6); });
    }
  }

  /// The clips that announce what ended the game (a kill or a vote), said before the win.
  List<String?> lead(String k, String who, String? role) => [
        k == 'killed' ? _pick(['v_killed_1', 'v_killed_2', 'v_killed_3']) : _pick(['v_vote_out', 'v_vote_out_2']),
        name(who, monster: k == 'killed'), _was(role),
      ];

  /// [S17] the Jester was voted out: the vote, then his laugh
  void jesterWin(List<String?> lead, void Function(double) arm) {
    sfx('verdict');
    arm(4);
    say([...lead, 'v_laugh'], delay: 1.3, at: (i) { if (i == lead.length) arm(.3); });
  }

  /// [S21] the Serial Killer, the Lovers or a draw: no voice for them yet: the death that ended it, then the result on screen
  void otherWin(List<String?> lead, void Function(double) arm) {
    sfx('verdict');
    arm(lead.isEmpty ? 1 : 4);
    if (lead.isNotEmpty) say(lead, delay: 1.3, at: (i) { if (i == lead.length - 1) arm(.6); });
  }

  void mafiaWin(List<String> mafia, List<String?> lead, void Function(double) arm) {
    lead.isNotEmpty ? sfx('verdict') : sfx('mafia_win');
    arm(2);
    say([...lead, 'v_laugh', 'v_mafia_win', ...mafia.map((n) => name(n, monster: true))], delay: 1.5, at: (i) {
      if (i == lead.length) { if (lead.isNotEmpty) sfx('mafia_win'); arm(.3); }
    });
    if (prefs.voice <= 0 && lead.isNotEmpty) sfx('mafia_win', 1.5);
  }

  void citizensWin(List<String> mafia, List<String?> lead, void Function(double) arm) {
    if (lead.isNotEmpty) sfx('verdict');
    arm(lead.isNotEmpty ? 6 : 2.4);
    if (lead.isEmpty) {
      sfx('citizens_win');
    } else if (prefs.voice <= 0) {
      sfx('citizens_win', 2);
    }
    say([...lead, 'v_citizens_win', ...mafia.map((n) => name(n))], delay: lead.isNotEmpty ? 1.4 : 2.2, at: (i) {
      if (i == lead.length) { if (lead.isNotEmpty) sfx('citizens_win'); arm(.2); }
    });
  }

  /// The reveal itself: a sound and a buzz (long for bad news).
  void hit(bool bad) {
    sfx(bad ? 'hit_bad' : 'hit_good');
    if (!silent) bad ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact();
  }
}
