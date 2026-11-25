import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/features/offline/recap_card.dart';
import 'package:mafia_dealer/features/offline/role_card.dart';
import 'package:mafia_dealer/features/offline/setup_screen.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.game, required this.prefs, required this.audio, this.account});
  final OfflineGame game;
  final Prefs prefs;
  final Audio audio;
  final Account? account;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late OfflineGame g = widget.game;
  OfflineGame get game => g; // for the tests
  Timer? _tick;
  Object? _pick; // the choice being made (night / table decision / ballot)
  bool _deciding = false; // the day: the town chose "decide together" (the pick list shows)

  @override
  void initState() {
    super.initState();
    _wake(true);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { g.tickDay(); if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _wake(false);
    g.close();
    super.dispose();
  }

  static void _wake(bool on) => (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {}); // the screen stays on during a game

  Future<void> _leave() async {
    final l = L.of(context);
    if (g.screen == Screen.end || await ask(context, l.quitQ, l.quitD, l.quit)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _do(VoidCallback f) { f(); _pick = null; _deciding = false; }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) { if (!didPop) _leave(); },
        child: Scaffold(
          body: ListenableBuilder(listenable: g, builder: (context, _) => KeyedSubtree(key: ValueKey('${g.screen.name}/${g.who}'), child: _screen(L.of(context)))),
        ),
      );

  String _name(int seat) => g.s.names[seat];

  Widget _screen(L l) => switch (g.screen) {
        Screen.dealPass => _pass(l, l.iam(_name(g.who)), () => g.dealOpen(g.who), top: l.cardOf(g.who + 1, g.s.alive.length), glyph: Icons.smartphone_outlined),
        Screen.dealCard => RoleCard(key: ValueKey('card${g.who}'), foot: _foot(l), name: _name(g.who), role: g.s.roles[g.who],
            mates: [for (final j in g.view(g.who).mates) _name(j)], done: g.who == g.n - 1 ? l.memorizedLast : l.memorized,
            isSheikh: g.view(g.who).sheikh == g.who,
            sheikh: switch (g.view(g.who).sheikh) { final sh? when sh != g.who => _name(sh), _ => null },
            onDone: () => g.dealDone(g.who)),
        Screen.nightPass => _pass(l, l.open(_name(g.who)), () => g.nightOpen(g.who), color: C.night, top: l.night(g.s.day), glyph: Icons.nightlight_outlined),
        Screen.nightPick => _nightPick(l),
        Screen.nightLocked => _nightLocked(l),
        Screen.dawn => Stage(card: true, foot: _foot(L.of(context)), color: C.night, bottom: [Btn(l.dawn, key: const Key('dawn'), icon: Icons.wb_twilight, onTap: g.dawn)],
            children: [GlyphBox(Icons.nightlight_round, color: C.blue), const SizedBox(height: 16), Big(l.allDone, sub: l.allDoneHint)]),
        Screen.morning => _morning(l),
        Screen.day => _day(l),
        Screen.ballotPass => _pass(l, l.open(_name(g.who)), () => g.ballotOpen(g.who), top: l.startBallot, glyph: Icons.how_to_vote_outlined),
        Screen.ballotPick => _ballotPick(l),
        Screen.ballotVoted => Stage(card: true, foot: _foot(L.of(context)), bottom: [Btn(l.done, key: const Key('ballotNext'), onTap: () => g.ballotNext(g.who))],
            children: [GlyphBox(Icons.how_to_vote_outlined, color: C.green), const SizedBox(height: 16), Big(l.voted, sub: l.lockedHint)]),
        Screen.verdict => _verdict(l),
        Screen.end => _end(l),
      };

  // ---------------------------------------------------------------- shared
  // [S14-6] under every game screen, as the old app
  String _foot(L l) => l.roundAlive(g.s.day < 1 ? 1 : g.s.day, g.s.alive.where((x) => x).length, g.s.alive.length);
  // [S14-6] as the old app: a boxed tag ("Card 1 of 6"), the icon in a box, "PASS THE PHONE TO" in small caps, the name
  Widget _pass(L l, String button, VoidCallback onTap, {Color? color, String? top, IconData? glyph}) => Stage(card: true, foot: _foot(L.of(context)),
        color: color,
        bottom: [Btn(button, key: const Key('open'), onTap: onTap)],
        children: [
          if (top != null) Tag(top),
          if (glyph != null) ...[const SizedBox(height: 18), GlyphBox(glyph)],
          const SizedBox(height: 20),
          Text(l.passTo.toUpperCase(), textAlign: TextAlign.center, style: capStyle.copyWith(fontSize: 14)),
          const SizedBox(height: 4),
          Big(_name(g.who), size: 40),
          const SizedBox(height: 18),
          Text(l.tiltHint, textAlign: TextAlign.center, style: TextStyle(color: C.dim)),
          if (g.s.phase == Phase.night && g.s.night.endsAt != 0) _nightClock(l),
        ],
      );

  Widget _nightClock(L l) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Text(l.nightTimeLeft(((g.s.night.endsAt - OfflineGame.now()) / 1000).ceil().clamp(0, 999)),
            key: const Key('nightClock'), textAlign: TextAlign.center, style: TextStyle(color: C.red2)),
      );

  Widget _option(String label, Object value, {List<String> tags = const [], bool disabled = false, Color? accent}) =>
      PickRow(key: Key('opt_$value'), label: label, seat: value is int ? value : null, on: _pick == value, tags: tags, accent: accent,
          onTap: disabled ? null : () => setState(() => _pick = value));

  // ---------------------------------------------------------------- night
  Widget _nightPick(L l) {
    final seat = g.who, v = g.view(seat), no = v.night!, role = g.s.roles[seat];
    final (title, desc) = nightText(l, no.key);
    final none = no.key == 'none', sniper = no.key == 'sniper';
    return Stage(card: true, foot: _foot(L.of(context)), color: C.night, center: false, bottom: [
      Btn(l.confirm, key: const Key('confirm'), onTap: none || _pick != null ? () { final c = none ? null : _pick; if (none || c != null) _do(() => g.nightPick(seat, c)); } : null),
    ], children: [
      Row(children: [
        Icon(roleIcon(role), color: roleColor(role)),
        const SizedBox(width: 8),
        Expanded(child: Text(seatRole(l, role, v.sheikh == seat), overflow: TextOverflow.ellipsis, style: head.copyWith(color: roleColor(role), fontSize: 18))),
        const SizedBox(width: 8),
        Flexible(child: Text('${_name(seat)} · ${l.night(g.s.day)}', overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: TextStyle(color: C.mute))),
      ]),
      const SizedBox(height: 14),
      Text(title, style: head.copyWith(fontSize: 26)),
      Text(desc, style: TextStyle(color: C.mute)),
      if (v.mates.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.mates(v.mates.map(_name).join(', ')), style: TextStyle(color: C.red2))),
      // [Ben, S17 review] once the Godfather is out the note says who settles a tie now
      if (no.key == 'mafia' && v.sheikh != null && v.mates.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(g.s.alive[v.sheikh!] ? l.tieSheikh : l.tieLowest, key: const Key('tieSheikh'),
            style: TextStyle(color: C.mute, fontSize: 13))),
      if (g.s.night.endsAt != 0) _nightClock(l),
      const SizedBox(height: 16),
      if (!none)
        for (final o in no.opts)
          _option(_name(o.seat), o.seat, disabled: o.disabled, accent: o.teammate ? C.red2 : null, tags: [
            if (o.self) l.you,
            if (o.teammate) l.teammate,
            if (o.mateVotes > 0) '${l.mateVote} ×${o.mateVotes}',
            if (o.sheikh) l.sheikhPick,
            if (o.lastTarget) l.lastTgt,
            if (o.lastNight) l.lastNight,
          ]),
      if (no.canSkip && sniper) _option(l.keepBullet, 'skip', tags: [l.keepBulletD])
      else if (no.canSkip) _option(l.skipKill, 'skip', tags: [l.skipLeft, if ((no.skipMateVotes ?? 0) > 0) '${l.mateVote} ×${no.skipMateVotes}', if (no.skipSheikh) l.sheikhPick]),
    ]);
  }

  Widget _nightLocked(L l) {
    final seat = g.who, check = g.view(seat).check, last = g.s.phase != Phase.night;
    return Stage(card: true, foot: _foot(L.of(context)), color: C.night, bottom: [Btn(last ? l.doneLast : l.done, key: const Key('nightNext'), onTap: () => g.nightNext(seat))], children: [
      Icon(Icons.lock_outline, color: C.mute, size: 48),
      const SizedBox(height: 14),
      Big(l.locked, sub: l.lockedHint),
      if (check != null)
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Sec(
            color: C.card2,
            child: Text(l.checkResult(_name(check.seat), check.mafia ? l.mafia : l.notMafia), key: const Key('checkResult'),
                textAlign: TextAlign.center, style: head.copyWith(fontSize: 22, color: check.mafia ? C.red2 : C.green)),
          ),
        ),
    ]);
  }

  // ---------------------------------------------------------------- morning
  Widget _suspense(L l, String text, Color color, IconData icon) => Stage(card: true, foot: _foot(L.of(context)), color: color, bottom: [
        Btn(l.skipWait, key: const Key('revealNow'), ghost: true, onTap: g.reveal),
      ], children: [
        Icon(icon, color: C.gold, size: 60),
        const SizedBox(height: 16),
        Big(text),
        const SizedBox(height: 18),
        Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: C.mute))),
      ]);

  Widget _morning(L l) {
    if (!g.revealed) return _suspense(l, l.sunrise, C.day, Icons.wb_sunny_outlined);
    final m = g.s.morning!, d = m.dead, sniper = g.s.roles.contains(Role.sniper);
    return Stage(card: true, foot: _foot(L.of(context)), color: d != null ? C.blood : C.day, bottom: [Btn(l.startDay(g.s.day), key: const Key('startDay'), onTap: g.startDay)], children: [
      Tag(l.morningOf(g.s.day)),
      const SizedBox(height: 24),
      if (d != null) ...[
        Text(m.dead2 != null ? l.diedIs : sniper ? l.diedOne : l.victimIs, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16)),
        for (final x in [d, ?m.dead2]) ...[
          Big(_name(x), size: 42, color: C.red2),
          if (g.s.rules.reveal) Text(l.wasRole(seatRole(l, g.s.roles[x], x == g.s.sheikh)), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ],
      ] else if (m.saved != null) ...[
        Text(l.savedIs, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16)),
        Big(_name(m.saved!), size: 42, color: C.green),
      ] else
        Big(l.nobody, color: C.green),
    ]);
  }

  // ---------------------------------------------------------------- day
  Widget _day(L l) {
    final left = timerLeft(g.s, OfflineGame.now()), running = g.s.timer.running;
    final clock = '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
    final timer = Sec(
      title: l.discussion,
      child: Column(children: [
        Text(left == 0 && running ? l.timeUp : clock, key: const Key('clock'), style: head.copyWith(fontSize: 52, color: left == 0 ? C.red2 : C.text)),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          OutlinedButton(key: const Key('timerGo'), onPressed: () => g.timer(running ? 'pause' : 'start'), child: Text(running ? l.pause : l.start, style: TextStyle(color: C.text))),
          OutlinedButton(key: const Key('timerAdd'), onPressed: () => g.timer('add'), child: Text(l.plusMin, style: TextStyle(color: C.text))),
          OutlinedButton(key: const Key('timerReset'), onPressed: () => g.timer('reset'), child: Text(l.reset, style: TextStyle(color: C.text))),
        ]),
      ]),
    );
    if (_deciding) {
      return Stage(card: true, foot: _foot(L.of(context)), color: C.day, center: false, bottom: [
        Btn(l.confirmDay, key: const Key('decide'), onTap: _pick == null ? null : () { final c = _pick; if (c != null) _do(() => g.decide(c)); }),
        Btn(l.back, key: const Key('decideBack'), ghost: true, onTap: () => setState(() { _deciding = false; _pick = null; })),
      ], children: [
        Text(l.whoOut, style: head.copyWith(fontSize: 20)),
        const SizedBox(height: 10),
        for (final i in aliveSeats(g.s)) _option(_name(i), i),
        _option(l.noOne, 'none'),
      ]);
    }
    return Stage(card: true, foot: _foot(L.of(context)), color: C.day, center: false, bottom: [
      Text(l.howDecide, textAlign: TextAlign.center, style: head.copyWith(fontSize: 18)),
      Btn(l.decideTogether, key: const Key('decideTogether'), onTap: () => setState(() => _deciding = true)),
      Text(l.decideTogetherD, textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 12)),
      Btn(l.startBallot, key: const Key('ballot'), ghost: true, icon: Icons.how_to_vote_outlined, onTap: () => _do(g.startBallot)),
      Text(l.secretBallotD, textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 12)),
    ], children: [
      timer,
      Sec(title: l.alivePlayers, child: Wrap(spacing: 8, runSpacing: 6, children: [
        for (var i = 0; i < g.n; i++)
          Chip(
            key: Key('roster_$i'),
            label: Text(g.s.alive[i] ? _name(i) : '${_name(i)} · ${g.s.rules.reveal ? seatRole(l, g.s.roles[i], i == g.s.sheikh) : l.outTag}',
                style: TextStyle(color: g.s.alive[i] ? C.text : C.dim, decoration: g.s.alive[i] ? null : TextDecoration.lineThrough)),
            backgroundColor: g.s.alive[i] ? C.card2 : C.bg, side: BorderSide(color: C.line),
          ),
      ])),
    ]);
  }

  Widget _ballotPick(L l) {
    final seat = g.who;
    return Stage(card: true, foot: _foot(L.of(context)), center: false, bottom: [
      Btn(l.castVote, key: const Key('castVote'), onTap: _pick == null ? null : () { final c = _pick; if (c != null) _do(() => g.ballotCast(seat, c)); }),
    ], children: [
      Text(_name(seat), style: TextStyle(color: C.mute)),
      Text(l.votePick, style: head.copyWith(fontSize: 26)),
      const SizedBox(height: 14),
      for (final i in aliveSeats(g.s)) if (i != seat) _option(_name(i), i),
      _option(l.noOne, 'none'),
    ]);
  }

  // ---------------------------------------------------------------- verdict
  Widget _verdict(L l) {
    if (!g.revealed) return _suspense(l, l.deciding, C.day, Icons.gavel);
    final v = g.s.verdict!;
    return Stage(card: true, foot: _foot(L.of(context)), color: v.out != null ? C.blood : C.day, bottom: [Btn(l.nextNight(g.s.day + 1), key: const Key('nextNight'), onTap: g.nextNight)], children: [
      if (v.out != null) ...[
        Text(l.outIs, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16)),
        Big(_name(v.out!), size: 42, color: C.red2),
        if (g.s.rules.reveal) Text(l.wasRole(seatRole(l, g.s.roles[v.out!], v.out == g.s.sheikh)), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
      ] else
        Big(v.kind == 'tie' ? l.tie : l.skipped),
      if (v.tally != null && v.tally!.isNotEmpty) ...[
        const SizedBox(height: 22),
        Sec(child: Column(children: [
          for (final t in v.tally!)
            Row(children: [Expanded(child: Text(t.k == 'none' ? l.noOne : _name(t.k as int))), Text(l.votesN(t.n), style: TextStyle(color: C.mute))]),
        ])),
      ],
    ]);
  }

  // ---------------------------------------------------------------- end
  Widget _end(L l) {
    if (!g.revealed) return _suspense(l, l.gameOver, C.glory, Icons.emoji_events_outlined);
    final s = g.s, mafia = s.winner == Winner.mafia, best = mvp(s.winner!, s.roles, s.alive, s.stats);
    return Stage(color: mafia ? C.blood : C.glory, center: false, bottom: [
      Btn('${l.playAgain} · ${l.sameNew}', key: const Key('playAgain'), icon: Icons.replay, onTap: () {
        final n = g.playAgain();
        if (n != null) setState(() => g = n);
      }),
      Row(children: [
        Expanded(child: Btn(l.changePlayers, ghost: true, onTap: () {
          g.close();
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => _NewSetup(prefs: widget.prefs, audio: widget.audio, account: widget.account)));
        })),
        const SizedBox(width: 10),
        Expanded(child: Btn(l.home, key: const Key('home'), ghost: true, onTap: () => Navigator.of(context).pop())),
      ]),
    ], children: [
      // [S15-4] the old app's recap card
      RecapCard(winner: s.winner!, days: s.day, sheikh: s.sheikh, players: [for (var i = 0; i < g.n; i++) (name: _name(i), role: s.roles[i], alive: s.alive[i])],
          best: best == null ? null : (name: _name(best.seat), role: s.roles[best.seat], why: mvpWhy(l, best.why, best.n)),
          lines: [for (final e in s.log) if (_line(l, e) case final t?) (night: e is NightLog, text: t)]),
      const SizedBox(height: 12),
      Text(l.nothingSaved, textAlign: TextAlign.center, style: TextStyle(color: C.dim, fontSize: 12)),
    ]);
  }

  String? _line(L l, GameEvent e) => switch (e) {
        NightLog(:final day, :final k, :final seat, :final shot) => l.hNight(day) +
            switch (k) { 'kill' => l.hKill(_name(seat!)), 'saved' => l.hSaved(_name(seat!)), 'skip' => l.hSkip, _ => l.hNoMafia } +
            (shot != null ? l.hShot(_name(shot)) : ''),
        DayLog(:final day, :final out) => l.hDay(day) + (out != null ? l.hOut(_name(out)) : l.hNone),
        RemovedLog(:final seat) => l.hRemoved(_name(seat)),
        _ => null,
      };
}

/// "Change players": back to the setup, then straight into the new game.
class _NewSetup extends StatelessWidget {
  const _NewSetup({required this.prefs, required this.audio, this.account});
  final Prefs prefs;
  final Audio audio;
  final Account? account;
  @override
  Widget build(BuildContext context) => SetupScreen(prefs: prefs, audio: audio, account: account, onDealt: (g) =>
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(game: g, prefs: prefs, audio: audio, account: account))));
}

/// The role card: hidden until pressed and held; hidden again on release or when the app goes to the background.
/// The button waits for one look. Used offline (pass the phone) and online (my own phone).
