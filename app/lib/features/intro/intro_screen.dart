import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

part 'intro_art.dart';

// The intro (Sprint 10): a faithful port of the old app's welcome (../mafia-dealer v2.14–v2.16: app/src/welcome.ts, the
// #welcome rules of app/assets/style.css). Same 360×700 drawing (xMidYMax slice), scenes, timings, captions and motion;
// the CSS transitions and keyframes are replayed by hand on one ticker. The sounds were rendered once from the old
// recipes (audio/welcomeSfx.ts) into assets/intro/s1..s6.ogg; the laugh in s6 is the narrator's recorded clip.

/// The intro's own colours (the old `--w*` variables), per look.
class _W {
  const _W({required this.blood1, required this.ink, required this.ink2, required this.rim, required this.text, required this.mute,
      required this.acc, required this.acc2, required this.doc, required this.det, required this.maf, required this.dawn,
      required this.night, required this.morn, required this.red, required this.star, required this.win, required this.bub});
  final Color blood1, ink, ink2, rim, text, mute, acc, acc2, doc, det, maf, star, win, bub;
  final List<Color> dawn, night, morn, red;
}

const _neonW = _W(blood1: Color(0xFF7C0812), ink: Color(0xFF06050B), ink2: Color(0xFF1B1726), rim: Color(0x30FFFFFF),
    text: Color(0xFFF4F2F8), mute: Color(0xFFA59FB3), acc: Color(0xFFFF2E63), acc2: Color(0xFFFF8A3D), doc: Color(0xFF3CE0A0),
    det: Color(0xFF5AA2FF), maf: Color(0xFFFF4D7D), dawn: [Color(0xFF2A1745), Color(0xFFC2456A), Color(0xFFFFB06A)],
    night: [Color(0xFF04030B), Color(0xFF141236)], morn: [Color(0xFF1D2638), Color(0xFF6F8399)], red: [Color(0xFF1A0207), Color(0xFF6B0A1D)],
    star: Color(0xFFFFFFFF), win: Color(0xFFFFD27A), bub: Color(0xFF0B0A10));
const _noirW = _W(blood1: Color(0xFF5E0A0A), ink: Color(0xFF080706), ink2: Color(0xFF1D1A15), rim: Color(0x2AECE4D4),
    text: Color(0xFFECE4D4), mute: Color(0xFFA39A8B), acc: Color(0xFFB3241F), acc2: Color(0xFFD4B483), doc: Color(0xFF7FB08B),
    det: Color(0xFF86A6C9), maf: Color(0xFFC0392B), dawn: [Color(0xFF1E1A16), Color(0xFF6E5A43), Color(0xFFC9B08A)],
    night: [Color(0xFF050505), Color(0xFF1A1815)], morn: [Color(0xFF1C1B19), Color(0xFF6D6658)], red: [Color(0xFF120404), Color(0xFF4A0D0B)],
    star: Color(0xFFECE4D4), win: Color(0xFFE8CF9A), bub: Color(0xFF0D0C0B));

/// Each scene and how long it stays (s); the title ('end') stays until a tap.
const _scenes = [('s1', 3.6), ('s2', 4.0), ('s3', 4.4), ('s4', 3.4), ('s5', 3.0), ('s6', 3.8), ('end', 2.8)];

/// P4: after the intro's "Tap to start", Home's "How to play" offer is highlighted.
final guideGlow = ValueNotifier<bool>(false);

/// Plays the intro over the current screen. [first]: the first launch (no Skip, Back does nothing).
Future<void> showIntro(BuildContext context, Prefs prefs, {bool first = false}) => Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false, transitionDuration: Duration.zero, reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => IntroScreen(prefs: prefs, first: first)));

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.prefs, this.first = false});
  final Prefs prefs;
  final bool first;

  /// Has it been offered at start in this run (Home can be built again; the intro plays once per start)?
  static bool ran = false;

  /// Ends a playing intro (the app is opening a room or a notification instead: S10-2 AC4).
  static void stop() => _IntroState._live?._end();

  @override
  State<IntroScreen> createState() => _IntroState();
}

/// A CSS transition: from → to over dur (s) after delay, eased.
class _Tw {
  _Tw(this.to) : from = to;
  double from, to, at = 0, dur = 0, delay = 0;
  Curve curve = Curves.ease;
  double value(double t) {
    final e = t - at - delay;
    if (e < 0) return from;
    if (dur <= 0) return to;
    return from + (to - from) * curve.transform((e / dur).clamp(0.0, 1.0));
  }
}

class _IntroState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  static _IntroState? _live;
  late final Ticker _ticker;
  double t = 0, sceneAt = 0; // s since the intro started; when the current scene started
  int idx = -1;
  bool reduce = false; // Android's "Remove animations": the old prefers-reduced-motion rules
  final _tw = <String, _Tw>{};
  final _fired = <String>{};
  String? capText, sayRole;
  double sayAt = 0, bloodAt = -99;
  double? haAt, endAt;
  AudioPlayer? _cur;

  String get k => idx < 0 ? '' : _scenes[idx].$1;
  double get st => t - sceneAt;
  Prefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    _live = this;
    _ticker = createTicker((d) => setState(() { t = d.inMicroseconds / 1e6; _step(); }))..start();
  }

  @override
  void didChangeDependencies() { super.didChangeDependencies(); reduce = MediaQuery.disableAnimationsOf(context); }

  @override
  void dispose() {
    if (_live == this) _live = null;
    _ticker.dispose();
    final c = _cur;
    _cur = null;
    if (c != null) _fade(c, .4);
    super.dispose();
  }

  // ---------------------------------------------------------------- the old CSS, replayed
  double v(String key, [double lag = 0]) => _tw[key]?.value(t - lag) ?? _initial[key] ?? 0;
  void _set(String key, double to, double dur, [Curve curve = Curves.ease, double delay = 0]) {
    final w = _tw.putIfAbsent(key, () => _Tw(_initial[key] ?? 0));
    if (w.to == to) return; // a transition runs only when the value changes
    w..from = w.value(t)..to = to..at = t..dur = reduce ? .3 : dur..delay = delay..curve = curve;
  }
  static const _initial = {'sunY': 120.0, 'moonY': 90.0, 'crowdY': 40.0, 'rise_doc': 60.0, 'rise_det': 60.0, 'rise_maf': 60.0, 'out': 1.0};

  /// A CSS animation's progress at e s after its start: null when it doesn't apply (the base style shows).
  double? anim(double e, double dur, {bool back = false, bool fwd = false, double iters = 1, bool alt = false}) {
    if (reduce) { dur = 1e-5; iters = 1; }
    if (e < 0) return back ? 0 : null;
    final n = e / dur;
    if (n >= iters) return fwd ? 1 : null;
    final p = n % 1;
    return alt && n.floor().isOdd ? 1 - p : p;
  }

  /// Keyframes: [(offset, value)], each segment eased with [c].
  static double kf(double p, List<(double, double)> f, [Curve c = Curves.linear]) {
    for (var i = 1; i < f.length; i++) {
      if (p <= f[i].$1) { final (a, va) = f[i - 1];
        final (b, vb) = f[i]; return va + (vb - va) * c.transform(((p - a) / (b - a)).clamp(0.0, 1.0)); }
    }
    return f.last.$2;
  }

  void _go(int n) {
    idx = n;
    sceneAt = t;
    _fired.clear();
    final k = this.k;
    bool on(List<String> ks) => ks.contains(k);
    void layer(String name, double to) => _set(name, to, 1.4);
    layer('dawn', k == 's1' ? 1 : 0);
    layer('night', on(['s2', 's5', 'end']) ? 1 : 0);
    layer('morn', on(['s3', 's4']) ? 1 : 0);
    layer('red', k == 's6' ? 1 : 0);
    layer('stars', on(['s2', 's5']) ? 1 : 0);
    layer('walkers', k == 's1' ? 1 : 0);
    layer('crowd', k == 's3' ? 1 : on(['s4', 's5']) ? .35 : 0);
    layer('chalk', k == 's3' ? 1 : 0);
    layer('spot', k == 's3' ? 1 : 0);
    layer('vign', on(['s4', 's5', 's6']) ? 1 : 0);
    _set('sun', k == 's1' ? 1 : 0, 1.2);
    _set('sunY', k == 's1' ? 0 : 120, 3.2, const Cubic(.2, .7, .2, 1));
    _set('moon', k == 's2' ? 1 : 0, 1.2);
    _set('moonY', k == 's2' ? 0 : 90, 3, Curves.easeOut);
    _set('win', k == 's1' ? .95 : k == 's3' ? .25 : 0, .5);
    _set('crowdY', on(['s3', 's4', 's5']) ? 0 : 40, 1.4, const Cubic(.2, .7, .2, 1));
    for (final (r, s) in [('doc', 's4'), ('det', 's5'), ('maf', 's6')]) {
      _set('h_$r', k == s ? 1 : 0, .8);
      _set('rise_$r', k == s ? 0 : 60, 1, const Cubic(.2, .8, .2, 1));
    }
    if (k == 's3') { bloodAt = t; _set('blood', 1, .1, Curves.ease, 1.55); } else { _set('blood', 0, .9); }
    _set('cap', 0, .8);
    _set('say', 0, .6);
    haAt = null;
    _set('hint', k == 's1' ? 1 : 0, .6);
    _set('title', k == 'end' ? 1 : 0, 1);
    _set('mark', k == 'end' ? 1 : 0, .9, const Cubic(.2, 1.6, .4, 1));
    _sound(k);
  }

  bool _once(String key, bool when) => when && _fired.add(key);

  void _step() {
    if (endAt != null) {
      if (t >= endAt! + .5 && _fired.add('gone')) {
        final r = ModalRoute.of(context);
        if (r != null && r.isActive) r.navigator?.removeRoute(r);
      }
      return;
    }
    if (idx < 0) { if (t >= .03) _go(0); return; }
    final k = this.k, l = L.of(context);
    final cap = {'s1': l.iCap1, 's2': l.iCap2, 's3': l.iCap3}[k];
    if (cap != null && _once('cap', st >= (k == 's1' ? .4 : .25))) { capText = cap; _set('cap', 1, .8); }
    if (_once('say', {'s4', 's5', 's6'}.contains(k) && st >= .5)) { sayRole = {'s4': 'doc', 's5': 'det', 's6': 'maf'}[k]; sayAt = t; _set('say', 1, .6); }
    if (_once('ha', k == 's6' && st >= 1.7)) haAt = t;
    // P3: a haptic beat on CRACK and on each HA
    if (_once('crack', k == 's2' && st >= 1.7)) _buzz(true);
    for (var i = 0; i < 3; i++) { if (_once('ha$i', haAt != null && t >= haAt! + i * .45)) _buzz(false); }
    if (idx < _scenes.length - 1 && st >= _scenes[idx].$2) _go(idx + 1);
  }

  void _buzz(bool big) { if (!Audio.silent) big ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact(); }

  void _tap() { if (endAt != null) return; if (idx < _scenes.length - 1) { _go(idx + 1); } else { _end(started: true); } }

  void _end({bool started = false}) {
    if (endAt != null) return;
    endAt = t;
    prefs.introSeen = true;
    if (started) guideGlow.value = true;
    final c = _cur;
    _cur = null;
    if (c != null) _fade(c, .4);
    _set('out', 0, .5);
  }

  // ---------------------------------------------------------------- sound: each scene on its own player, the previous one fades
  double get _vol => prefs.introMute ? 0 : prefs.sfx;
  void _sound(String k) {
    if (Audio.silent) return;
    final old = _cur;
    _cur = null;
    if (old != null) _fade(old, k == 'end' ? 3 : 1);
    if (k == 'end') return;
    final p = _cur = AudioPlayer()..positionUpdater = null;
    p.play(AssetSource('intro/$k.ogg'), volume: _vol).catchError((_) {});
  }
  void _fade(AudioPlayer p, double sec) {
    final v0 = p.volume, n = max(1, (sec * 20).round());
    var i = 0;
    Timer.periodic(const Duration(milliseconds: 50), (tm) {
      if (++i >= n) { tm.cancel(); p.dispose().catchError((_) {}); } else { p.setVolume(v0 * (1 - i / n)).catchError((_) {}); }
    });
  }
  void _mute() { setState(() => prefs.introMute = !prefs.introMute); _cur?.setVolume(_vol).catchError((_) {}); }

  // ---------------------------------------------------------------- the screen
  @override
  Widget build(BuildContext context) {
    final l = L.of(context), w = C.neon ? _neonW : _noirW, mq = MediaQuery.of(context), size = mq.size, pad = mq.padding;
    final rtl = Directionality.of(context) == TextDirection.rtl, vw = size.width / 100;
    TextStyle hd({double size = 16, bool bold = false, Color? color}) => rtl
        ? TextStyle(fontFamily: 'Messiri', fontSize: size, color: color ?? w.text, fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            fontVariations: [FontVariation('wght', bold ? 700 : 400)])
        : TextStyle(fontFamily: C.p.head, fontFamilyFallback: C.p.headFallback, fontSize: size, color: color ?? w.text,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontVariations: C.neon ? [FontVariation('wght', bold ? 700 : 400)] : null);
    final body = TextStyle(fontFamily: rtl ? 'Plex' : C.p.body, color: w.text, decoration: TextDecoration.none);
    // P1: Neon's glow on the big words
    List<Shadow> glow(Color c) => [const Shadow(color: Color(0xCC000000), offset: Offset(0, 2), blurRadius: 18), if (C.neon) Shadow(color: c.withValues(alpha: .55), blurRadius: 26)];
    final k = this.k, s2 = k == 's2' ? st - 1.7 : -1.0;

    // "CRACK!" (wlBang 1.4 s at 1.7 s, both)
    final bp = k == 's2' ? anim(s2, 1.4, back: true, fwd: true) : null;
    const bc = Cubic(.2, 1.6, .4, 1);
    final bangOp = bp == null ? 0.0 : kf(bp, [(0, 0), (.25, 1), (.8, 1), (1, 0)], bc);
    final bangS = bp == null ? 1.0 : kf(bp, [(0, .3), (.25, 1.15), (.4, 1), (1, 1.05)], bc);
    final bangR = bp == null ? 0.0 : kf(bp, [(0, -8), (.25, -6), (.4, -4), (1, -4)], bc);

    final role = sayRole, rc = role == 'doc' ? w.doc : role == 'det' ? w.det : w.maf;
    final sayFull = role == null ? '' : {'doc': l.iDocL, 'det': l.iDetL, 'maf': l.iMafL}[role]!;
    final typed = sayFull.substring(0, ((t - sayAt) / .032).floor().clamp(0, sayFull.length));

    Widget pill(Key key, Widget child, VoidCallback onTap, {double? size}) => GestureDetector(key: key, onTap: onTap, behavior: HitTestBehavior.opaque,
        child: Container(width: size, height: size, alignment: Alignment.center,
            padding: size == null ? const EdgeInsets.symmetric(horizontal: 16, vertical: 9) : null,
            decoration: BoxDecoration(color: const Color(0x66000000), border: Border.all(color: const Color(0x30FFFFFF)), borderRadius: BorderRadius.circular(99)),
            child: child));

    final markS = .6 + .4 * v('mark'), blink = kf(t % 1.6 / 1.6, [(0, 1), (.5, .35), (1, 1)], Curves.easeInOut);
    final title = Opacity(opacity: v('title').clamp(0.0, 1.0), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Transform.rotate(angle: C.neon ? 0 : -6 * pi / 180, child: Transform.scale(scale: markS, child: Container(width: 96, height: 96, alignment: Alignment.center,
          decoration: C.neon
              ? BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: LinearGradient(colors: [w.acc, w.acc2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: w.acc, offset: const Offset(0, 18), blurRadius: 50, spreadRadius: -12)])
              : BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: w.acc, width: 2)),
          child: CustomPaint(size: const Size(52, 52), painter: _Logo(C.neon ? Colors.white : w.acc))))),
      const SizedBox(height: 14),
      Text(l.appName, textAlign: TextAlign.center, style: hd(size: (10 * vw).clamp(34, 46), bold: true).copyWith(height: 1.1, shadows: glow(w.acc))),
      const SizedBox(height: 14),
      Text(l.iTag, textAlign: TextAlign.center, style: body.copyWith(color: w.mute, fontSize: 17)),
      const SizedBox(height: 32),
      Opacity(opacity: reduce ? 1 : blink, child: Text(rtl ? l.iGo : l.iGo.toUpperCase(), key: const Key('introGo'),
          style: body.copyWith(color: w.mute, fontSize: rtl ? 16 : 14, letterSpacing: rtl ? 0 : 1.68))),
    ])));

    final n = idx;
    final prog = Row(children: [
      for (var i = 0; i < _scenes.length - 1; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(2), child: Container(height: 3, color: const Color(0x26FFFFFF), alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(widthFactor: i < n ? 1 : i == n ? (anim(st, _scenes[i].$2, fwd: true) ?? 0) : 0, child: Container(color: w.text))))),
      ],
    ]);

    return PopScope(
      canPop: false, // the first launch: Back does nothing; later it skips
      onPopInvokedWithResult: (didPop, _) { if (!widget.first) _end(); },
      child: Opacity(
        opacity: v('out').clamp(0.0, 1.0),
        child: GestureDetector(
          key: const Key('intro'), behavior: HitTestBehavior.opaque, onTap: _tap,
          child: Material(color: w.night[0], child: DefaultTextStyle(style: body, child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _Scene(this, w))),
            if (!C.neon) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Grain(reduce ? 0 : (t * 12).floor(), w.text)))),
            // the captions
            Positioned(left: max(20, pad.left), right: max(20, pad.right), top: size.height * .18 + pad.top,
                child: Opacity(opacity: v('cap').clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, 10 * (1 - v('cap'))),
                    child: Text(capText ?? '', key: const Key('introCap'), textAlign: TextAlign.center,
                        style: hd(size: (6.4 * vw).clamp(22, 30)).copyWith(height: 1.25, shadows: glow(w.acc)))))),
            Positioned(left: 0, right: 0, top: size.height * .4, child: IgnorePointer(child: Opacity(opacity: bangOp.clamp(0.0, 1.0),
                child: Transform.rotate(angle: bangR * pi / 180, child: Transform.scale(scale: bangS,
                    child: Text(l.iBang, textAlign: TextAlign.center, style: hd(size: (18 * vw).clamp(54, 92), bold: true).copyWith(letterSpacing: rtl ? 0 : 3, shadows: glow(w.acc)))))))),
            // the role speaks (typed out)
            Positioned(left: max(18, pad.left), right: max(18, pad.right), top: size.height * .14 + pad.top,
                child: Opacity(opacity: v('say').clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, 12 * (1 - v('say'))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.fromLTRB(6, 0, 6, 8), child: Text(role == null ? '' : rtl ? {'doc': l.iDoc, 'det': l.iDet, 'maf': l.iMaf}[role]! : {'doc': l.iDoc, 'det': l.iDet, 'maf': l.iMaf}[role]!.toUpperCase(),
                          style: hd(size: rtl ? 17 : 13, bold: true, color: rc).copyWith(letterSpacing: rtl ? 0 : 2.34))),
                      Stack(clipBehavior: Clip.none, children: [
                        Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                            constraints: BoxConstraints(minHeight: (5.4 * vw).clamp(19, 24) * 1.4 * 2 + 32),
                            decoration: BoxDecoration(color: w.bub, border: Border.all(color: rc, width: 1.5), borderRadius: BorderRadius.circular(C.neon ? 20 : 4),
                                boxShadow: [BoxShadow(color: rc, blurRadius: 34, spreadRadius: -10)]),
                            child: Text(typed, key: const Key('introSay'), style: body.copyWith(fontSize: (5.4 * vw).clamp(19, 24), height: 1.4))),
                        Positioned(bottom: -11, left: 0, right: 0, child: Center(child: Transform.rotate(angle: pi / 4, child: Container(width: 20, height: 20,
                            decoration: BoxDecoration(color: w.bub, border: Border(right: BorderSide(color: rc, width: 1.5), bottom: BorderSide(color: rc, width: 1.5))))))),
                      ]),
                    ])))),
            // HA HA HA (wlHa pop, then the quake)
            if (haAt != null) Positioned(left: 0, right: 0, top: size.height * .52 + pad.top, child: Directionality(textDirection: TextDirection.ltr,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < 3; i++) Builder(builder: (_) {
                    final e = t - haAt! - i * .45, p = anim(e, .5, back: true, fwd: true) ?? 0, q = anim(e - .5, .12, iters: double.infinity);
                    final pe = const Cubic(.2, 1.8, .4, 1).transform(p);
                    final dx = q == null ? 0.0 : kf(q, [(0, 0), (.25, -2), (.5, 2), (.75, -1), (1, 0)]), dy = q == null ? 0.0 : kf(q, [(0, 0), (.25, 1), (.5, -1), (.75, -2), (1, 0)]);
                    final fs = (13 * vw).clamp(40.0, 64.0);
                    return Padding(padding: EdgeInsets.symmetric(horizontal: fs * .12), child: Opacity(opacity: pe.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(dx, dy),
                        child: Transform.scale(scale: .2 + .8 * pe, child: Text(l.iHa, style: hd(size: fs, bold: true, color: w.maf).copyWith(shadows: glow(w.maf)))))));
                  }),
                ]))),
            Positioned.fill(child: IgnorePointer(child: title)),
            Positioned(left: 0, right: 0, bottom: 64 + pad.bottom, child: IgnorePointer(child: Opacity(opacity: v('hint').clamp(0.0, 1.0),
                child: Text(l.iHint, textAlign: TextAlign.center, style: body.copyWith(fontSize: 12, color: const Color(0xAAFFFFFF)))))),
            Positioned(left: max(16, pad.left), right: max(16, pad.right), bottom: 8 + pad.bottom, child: prog),
            if (!widget.first && k != 'end') PositionedDirectional(end: 16, bottom: 18 + pad.bottom,
                child: pill(const Key('introSkip'), Text(l.iSkip, style: body.copyWith(fontSize: 14, fontWeight: FontWeight.w700)), _end)),
            PositionedDirectional(end: 14, top: 14 + pad.top, child: Semantics(label: prefs.introMute ? l.iSoundOn : l.iSoundOff, button: true,
                child: pill(const Key('introMute'), Icon(prefs.introMute ? Icons.volume_off_outlined : Icons.volume_up_outlined, size: 20, color: w.text), _mute, size: 40))),
          ]))),
        ),
      ),
    );
  }
}
