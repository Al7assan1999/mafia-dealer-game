// The intro (Sprint 10): a faithful port of the old app's welcome (../mafia-dealer v2.14–v2.16: app/src/welcome.ts, the
// #welcome rules of app/assets/style.css). Same 360×700 drawing (xMidYMax slice), scenes, timings, captions and motion;
// the CSS transitions and keyframes are replayed by hand on one ticker. The sounds were rendered once from the old
// recipes (audio/welcomeSfx.ts) into assets/intro/s1..s6.ogg; the laugh in s6 is the narrator's recorded clip.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'audio.dart';
import 'l10n/app_localizations.dart';
import 'prefs.dart';
import 'ui.dart';

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

// ---------------------------------------------------------------- the drawing (the old SVG, 360×700)
/// A tiny SVG path reader: M L H V Q Z, absolute and relative (all the old drawing needs).
Path _svg(String d) {
  final tok = RegExp(r'[MmLlHhVvQqZz]|-?(?:\d+\.?\d*|\.\d+)').allMatches(d).map((m) => m[0]!).toList();
  final p = Path();
  var i = 0, cmd = 'M';
  double x = 0, y = 0, sx = 0, sy = 0;
  double n() => double.parse(tok[i++]);
  while (i < tok.length) {
    if (RegExp('[A-Za-z]').hasMatch(tok[i])) cmd = tok[i++];
    final rel = cmd == cmd.toLowerCase(), ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M': x = ox + n(); y = oy + n(); p.moveTo(x, y); sx = x; sy = y; cmd = rel ? 'l' : 'L';
      case 'L': x = ox + n(); y = oy + n(); p.lineTo(x, y);
      case 'H': x = ox + n(); p.lineTo(x, y);
      case 'V': y = oy + n(); p.lineTo(x, y);
      case 'Q': final cx = ox + n(), cy = oy + n(); x = ox + n(); y = oy + n(); p.quadraticBezierTo(cx, cy, x, y);
      case 'Z': p.close(); x = sx; y = sy;
    }
  }
  return p;
}

final _body = _svg('M-15 -58 Q0 -66 15 -58 L18 -22 L11 -22 L9 0 L2 0 L0 -20 L-2 0 L-9 0 L-11 -22 L-18 -22 Z');
final _hat = _svg('M-20 -80 h40 v3 h-40 z M-11 -80 l2 -14 h18 l2 14 z');
final _skyline = _svg('M0 520 h30 v-60 h22 v40 h18 v-80 h26 v90 h30 v-50 h24 v70 h28 v-110 h20 v100 h34 v-40 h28 v60 h26 v-70 h30 v90 h24 V640 H0 Z');
final _chalk = _svg('M128 612 q-6 -10 6 -14 l28 -2 q6 -14 18 -10 q12 4 6 16 l34 4 q10 4 0 10 l-26 2 l10 14 q2 8 -8 6 l-18 -12 l-12 14 q-8 4 -8 -6 l6 -14 l-30 4 q-10 -2 -6 -8 z');
final _chalkLen = _chalk.computeMetrics().fold<double>(0, (a, m) => a + m.length);
double _rnd(num n) => ((sin(n * 12.9898) * 43758.5453) % 1 + 1) % 1;

/// The houses (seeded, same every time): body, roof, and the windows with their light-up delays.
final _houses = () {
  final h = <(Rect, Path)>[], win = <(RRect, double)>[];
  double x = -10;
  var i = 0;
  while (x < 370) {
    final w = 44 + _rnd(i) * 34, ht = 70 + _rnd(i + 7) * 70, y = 560 - ht;
    h.add((Rect.fromLTWH(x, y, w, ht), Path()..moveTo(x - 4, y)..lineTo(x + w / 2, y - 26 - _rnd(i + 3) * 16)..lineTo(x + w + 4, y)..close()));
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 2; c++) {
        if (_rnd(i * 4 + r * 2 + c) > .3) win.add((RRect.fromRectAndRadius(Rect.fromLTWH(x + 8 + c * (w / 2 - 4), y + 14 + r * 28, w / 2 - 14, 14), const Radius.circular(2)), _rnd(i + r + c) * 1.6));
      }
    }
    x += w + 2;
    i++;
  }
  return (h, win);
}();
final _stars = [for (var i = 0; i < 46; i++) (Offset((sin(i * 91.7) * .5 + .5) * 360, (sin(i * 37.3) * .5 + .5) * 330), i % 5 != 0 ? .9 : 1.6)];
const _crowd = [(70.0, 600.0, .9), (118.0, 612.0, 1.0), (242.0, 612.0, 1.0), (290.0, 600.0, .9), (42.0, 622.0, .8), (318.0, 622.0, .8), (180.0, 640.0, 1.05)];

/// The killing's blood (v2.15, seeded): the splash shapes, then the streams (x, top, width, length, delay, duration).
final _splash = () {
  var seed = 7;
  double r() => (seed = (seed * 16807) % 2147483647) / 2147483647;
  final s = <(Offset, double, double, double)>[(const Offset(180, 170), 30.0, 30.0, 0.0), (const Offset(160, 182), 26.0, 16.0, 0.0), (const Offset(204, 160), 22.0, 14.0, 0.0)]; // centre, rx, ry, rotation
  for (var i = 0; i < 34; i++) {
    final a = r() * pi * 2, d = 36 + r() * 150, x = 180 + cos(a) * d, y = 170 + sin(a) * d * .78, big = r();
    if (big > .7) {
      final rx = 8 + r() * 16, ry = 1.6 + r() * 2.4;
      s.add((Offset(x, y), rx, ry, (a * 180 / pi).roundToDouble() * pi / 180));
    } else {
      final rr = 1.5 + r() * (d < 90 ? 9 : 5);
      s.add((Offset(x, y), rr, rr, 0));
    }
  }
  return s;
}();
const _streams = [(122.0, 190.0, 8.0, 230.0, .05, 1.8), (150.0, 196.0, 12.0, 508.0, .15, 2.3), (180.0, 200.0, 10.0, 330.0, 0.0, 1.9), (209.0, 192.0, 13.0, 512.0, .1, 2.4),
  (237.0, 180.0, 8.0, 190.0, .25, 1.6), (262.0, 174.0, 9.0, 280.0, .2, 1.9), (95.0, 168.0, 6.0, 120.0, .35, 1.2), (284.0, 182.0, 6.0, 150.0, .3, 1.4)];

Color _a(Color c, double o) => c.withValues(alpha: c.a * o.clamp(0.0, 1.0));
Paint _fill(Color c, [double o = 1]) => Paint()..color = _a(c, o);
Paint _stroke(Color c, double w, [double o = 1]) => Paint()..color = _a(c, o)..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;

class _Scene extends CustomPainter {
  _Scene(this.s, this.w);
  final _IntroState s;
  final _W w;

  /// A group at opacity o (the old `<g>` opacity): drawn into a layer only while it fades.
  void _group(Canvas c, Rect r, double o, void Function() draw) {
    if (o <= .001) return;
    if (o >= .999) return draw();
    c.saveLayer(r, Paint()..color = Color.fromRGBO(0, 0, 0, o));
    draw();
    c.restore();
  }

  /// wPerson: a silhouette at (x, y) scaled s, in [fill], with the rim light; [extra] draws in its own coordinates.
  void _person(Canvas c, double x, double y, double sc, Paint fill, {bool rim = true, void Function()? extra}) {
    c.save();
    c.translate(x, y);
    c.scale(sc);
    c.drawCircle(const Offset(0, -74), 11, fill);
    c.drawPath(_body, fill);
    if (rim) { final p = _stroke(w.rim, 1.4 / sc); c.drawCircle(const Offset(0, -74), 11, p); c.drawPath(_body, p); }
    extra?.call();
    c.restore();
  }

  void _badge(Canvas c, Color col, void Function(Canvas c, Paint p) icon) {
    c.drawCircle(const Offset(0, -44), 10, _fill(col));
    c.save();
    c.translate(-7, -51);
    c.scale(14 / 24);
    icon(c, _stroke(const Color(0xFF06050B), 2.6));
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = canvas, t = s.t, st = s.st, k = s.k, sc = max(size.width / 360, size.height / 700);
    final view = Rect.fromLTWH(-40, -40, 440, 780);
    void viewBox() { c.translate((size.width - 360 * sc) / 2, size.height - 700 * sc); c.scale(sc); }

    // the screen shake (wlShake .5 s at 1.7 s in s2): the drawing moves, the blood and the words don't
    var sh = Offset.zero;
    final shp = k == 's2' ? s.anim(st - 1.7, .5, back: true, fwd: true) : null;
    if (shp != null) {
      const f = [0.0, .15, .3, .45, .6, .75, 1.0], xs = <double>[0, -7, 6, -5, 4, -3, 0], ys = <double>[0, 4, -5, -3, 5, 2, 0];
      sh = Offset(_IntroState.kf(shp, [for (var i = 0; i < 7; i++) (f[i], xs[i])]), _IntroState.kf(shp, [for (var i = 0; i < 7; i++) (f[i], ys[i])]));
    }
    c.save();
    c.translate(sh.dx, sh.dy);
    viewBox();
    c.drawRect(const Rect.fromLTWH(-200, 0, 760, 700), _fill(w.night[0]));
    void sky(List<Color> cs, double o) {
      if (o <= .001) return;
      c.drawRect(const Rect.fromLTWH(-200, -400, 760, 1100), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 700),
          [for (final x in cs) _a(x, o)], cs.length == 3 ? const [0, .55, 1] : const [0, 1]));
    }
    sky(w.dawn, s.v('dawn'));
    sky(w.night, s.v('night'));
    sky(w.morn, s.v('morn'));
    sky(w.red, s.v('red'));
    final so = s.v('stars');
    if (so > .001) { final p = _fill(w.star, so); for (final (o, r) in _stars) { c.drawCircle(o, r, p); } }
    c.drawCircle(Offset(180, 420 + s.v('sunY')), 58, _fill(const Color(0xFFFFD08A), s.v('sun'))); // the CSS opacity overrides the SVG attribute .9
    _group(c, view, s.v('moon'), () {
      final y = s.v('moonY');
      c.drawCircle(Offset(268, 150 + y), 30, _fill(const Color(0xFFF4EEDD)));
      c.drawCircle(Offset(280, 142 + y), 27, _fill(w.night[0], .55));
    });
    c.drawPath(_skyline, _fill(w.ink2, .6));
    final ink2 = _fill(w.ink2);
    for (final (r, roof) in _houses.$1) { c.drawRect(r, ink2); c.drawPath(roof, ink2); }
    for (final (r, d) in _houses.$2) {
      final o = s.v('win', d);
      if (o > .001) c.drawRRect(r, _fill(w.win, o));
    }
    c.drawRect(const Rect.fromLTWH(-200, 558, 760, 342), ink2);
    // the sound over a house (wlRing: three rings at 1.7 / 1.85 / 2.0 s)
    if (k == 's2') {
      for (final d in [1.7, 1.85, 2.0]) {
        final p = s.anim(st - d, 1.6, back: true, fwd: true)!, e = const Cubic(.1, .7, .2, 1).transform(p);
        if (e < 1) c.drawCircle(const Offset(250, 470), 4 + 236 * e, _stroke(w.text, 5 - 4 * e, .9 * (1 - e))..strokeCap = StrokeCap.butt);
      }
    }
    // two people walking at dawn, one waves (wlWalk 9 s from the start, wlBob, wlWave)
    _group(c, view, s.v('walkers'), () {
      final ink = _fill(w.ink), wk = s.anim(t, 9, back: true, fwd: true)!;
      final bob = -3 * Curves.easeInOut.transform(s.anim(t, .55, iters: double.infinity, alt: true) ?? 0);
      final wave = (-20 + 45 * Curves.easeInOut.transform(s.anim(t, .5, iters: double.infinity, alt: true) ?? 0)) * pi / 180;
      _person(c, -60 + 210 * wk, 610 + bob, .95, ink, extra: () {
        c.save(); c.translate(6, -50); c.rotate(wave); c.translate(-6, 50);
        c.drawLine(const Offset(8, -54), const Offset(22, -72), _stroke(w.ink, 6));
        c.restore();
      });
      _person(c, 420 - 200 * wk, 616 + bob, .85, ink);
    });
    final spot = s.v('spot');
    if (spot > .001) {
      c.save(); c.translate(180, 610); c.scale(1, 34 / 120);
      c.drawCircle(Offset.zero, 120, Paint()..shader = ui.Gradient.radial(Offset.zero, 120, [Color.fromRGBO(255, 255, 255, .42 * spot), const Color(0x00FFFFFF)]));
      c.restore();
    }
    // the chalk outline draws itself (wlDraw 2 s at .6 s)
    final ch = s.v('chalk');
    if (ch > .001) {
      final p = k == 's3' ? s.anim(st - .6, 2, fwd: true) : null;
      final len = 420 - 420 * (1 - Curves.ease.transform(p ?? 0));
      if (len > 0) {
        final out = Path();
        var left = min(len, _chalkLen);
        for (final m in _chalk.computeMetrics()) { if (left <= 0) break; out.addPath(m.extractPath(0, min(left, m.length)), Offset.zero); left -= m.length; }
        c.drawPath(out, _stroke(w.text, 2.2, ch));
      }
    }
    _group(c, view, s.v('crowd'), () { final ink = _fill(w.ink), y = s.v('crowdY'); for (final (x, py, z) in _crowd) { _person(c, x, py + y, z, ink); } });
    final vg = s.v('vign');
    if (vg > .001) {
      final m = Matrix4.identity()..translateByDouble(180, 434, 0, 1)..scaleByDouble(1, 700 / 360, 1, 1)..translateByDouble(-180, -434, 0, 1);
      c.drawRect(const Rect.fromLTWH(-200, -400, 760, 1100), Paint()..shader = ui.Gradient.radial(const Offset(180, 434), 270,
          [const Color(0x00000000), Color.fromRGBO(0, 0, 0, .85 * vg)], const [.35, 1], TileMode.clamp, m.storage));
    }
    // the three roles
    Paint glow(Color col, double o, double sc) => _fill(col, o)..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 / sc);
    _group(c, view, s.v('h_doc'), () {
      final pp = k == 's4' ? s.anim(st - .4, 1.6, iters: double.infinity) : null;
      if (pp != null) { final e = Curves.easeOut.transform(pp); c.drawCircle(const Offset(180, 540), 30 + 90 * e, _stroke(w.doc, 3, .8 * (1 - e))); }
      c.save(); c.translate(0, s.v('rise_doc'));
      _person(c, 180, 646, 2.05, glow(w.doc, .75, 2.05), rim: false);
      _person(c, 180, 646, 2, _fill(w.ink), extra: () => _badge(c, w.doc, _docIcon));
      c.restore();
    });
    _group(c, view, s.v('h_det'), () {
      if (k == 's5') {
        final p = s.anim(st - .3, 2.6, back: true, fwd: true)!;
        final x = _IntroState.kf(p, [(0, -120), (.5, 120), (1, 0)], Curves.easeInOut);
        c.drawCircle(Offset(180 + x, 600), 70, Paint()..shader = ui.Gradient.radial(Offset(180 + x, 600), 70, [_a(w.det, .55), _a(w.det, 0)]));
      }
      c.save(); c.translate(0, s.v('rise_det'));
      _person(c, 180, 646, 2.05, glow(w.det, .7, 2.05), rim: false, extra: () => c.drawPath(_hat, glow(w.det, .7, 2.05)));
      final ink = _fill(w.ink);
      _person(c, 180, 646, 2, ink, extra: () {
        c.drawPath(_hat, ink);
        _badge(c, w.det, _detIcon);
        c.drawCircle(const Offset(26, -50), 9, _stroke(w.ink, 4));
        c.drawLine(const Offset(20, -44), const Offset(10, -32), _stroke(w.ink, 5));
      });
      c.restore();
    });
    _group(c, view, s.v('h_maf'), () {
      c.save(); c.translate(0, s.v('rise_maf'));
      final lp = k == 's6' ? s.anim(st - 1.2, 3, fwd: true) : null;
      if (lp != null) { final e = Curves.easeIn.transform(lp); c.translate(180, 646); c.scale(1 + .08 * e); c.translate(-180, -646 - 6 * e); }
      _person(c, 180, 646, 2.12, glow(w.maf, .8, 2.12), rim: false, extra: () => c.drawPath(_hat, glow(w.maf, .8, 2.12)));
      final ink = _fill(w.ink);
      _person(c, 180, 646, 2.1, ink, extra: () { c.drawPath(_hat, ink); _badge(c, w.maf, _mafIcon); });
      final eo = k == 's6' ? (s.anim(st - 1, .4, fwd: true) ?? 0) : 0.0;
      if (eo > 0) {
        final e = Curves.ease.transform(eo), g = _fill(w.maf, e)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6), p = _fill(w.maf, e);
        for (final x in [171.0, 189.0]) { c.drawCircle(Offset(x, 490), 4, g); c.drawCircle(Offset(x, 490), 2.4, p); }
      }
      c.restore();
    });
    c.restore();

    // the blood (wl-blood: not shaken). The old SVG filter (blur + alpha threshold) melts the shapes into liquid.
    final bo = s.v('blood');
    if (bo > .001 && (k == 's3' || k == 's4')) {
      final e = t - s.bloodAt;
      c.save();
      viewBox();
      c.saveLayer(view, Paint()..color = Color.fromRGBO(0, 0, 0, bo));
      c.saveLayer(view, Paint()..colorFilter = const ColorFilter.matrix([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 26, -11 * 255]));
      final blur = MaskFilter.blur(BlurStyle.normal, 3.4);
      // ponytail: the old filter's wobble (feTurbulence) and wet shine (feSpecularLighting) are left out; the goo is the look
      final sp = s.anim(e - 1.6, .26, fwd: true);
      if (sp != null) {
        final z = const Cubic(.15, .9, .3, 1.15).transform(sp), p = _fill(w.blood1, z)..maskFilter = blur;
        c.save(); c.translate(180, 170); c.scale(.12 + .88 * z); c.translate(-180, -170);
        for (final (o, rx, ry, rot) in _splash) {
          c.save(); c.translate(o.dx, o.dy); c.rotate(rot); c.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), p); c.restore();
        }
        c.restore();
      }
      final p = _fill(w.blood1)..maskFilter = blur;
      for (final (x, y, sw, len, del, dur) in _streams) {
        final q = s.anim(e - 1.75 - del, dur, fwd: true);
        if (q != null) {
          final z = const Cubic(.5, 0, .75, 1).transform(q);
          if (z > 0) c.drawRRect(RRect.fromRectXY(Rect.fromLTWH(x - sw / 2, y, sw, len * z), sw / 2, sw / 2 * z), p);
          c.drawCircle(Offset(x, y + len * z), sw * .72, p);
        }
        if (len < 500) {
          final f = s.anim(e - 1.85 - del - dur, .75, iters: 3);
          if (f != null) c.drawCircle(Offset(x, y + len + (700 - y + 20 - len) * const Cubic(.55, 0, 1, .45).transform(f)), sw * .42, p);
        }
      }
      c.restore();
      c.restore();
      c.restore();
    }
    // the flash (wlFlash .5 s at 1.7 s)
    final fp = k == 's2' ? s.anim(st - 1.7, .5, back: true, fwd: true) : null;
    if (fp != null) {
      final o = _IntroState.kf(fp, [(0, 0), (.1, .35), (1, 0)], Curves.easeOut);
      if (o > 0) c.drawRect(Offset.zero & size, _fill(w.text, o));
    }
  }

  @override
  bool shouldRepaint(_Scene old) => true;
}

// the role badges' icons and the logo (the old app's IC set, 24×24, stroked)
void _docIcon(Canvas c, Paint p) {
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(3, 3, 18, 18), const Radius.circular(5)), p);
  c.drawLine(const Offset(12, 8), const Offset(12, 16), p);
  c.drawLine(const Offset(8, 12), const Offset(16, 12), p);
}
void _detIcon(Canvas c, Paint p) { c.drawCircle(const Offset(10.5, 10.5), 6, p); c.drawLine(const Offset(15, 15), const Offset(21, 21), p); }
void _mafIcon(Canvas c, Paint p) {
  c.drawLine(const Offset(2, 12), const Offset(22, 12), p);
  c.drawPath(Path()..moveTo(5, 12)..lineTo(6.6, 5.5)..lineTo(17.4, 5.5)..lineTo(19, 12), p);
  c.drawPath(Path()..moveTo(7, 16.5)..quadraticBezierTo(12, 20, 17, 16.5), p);
}

class _Logo extends CustomPainter {
  _Logo(this.color);
  final Color color;
  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / 24);
    final p = _stroke(color, 2);
    c.drawLine(const Offset(3, 11), const Offset(21, 11), p);
    c.drawPath(Path()..moveTo(5, 11)..lineTo(6.5, 5)..lineTo(17.5, 5)..lineTo(19, 11), p);
    for (final x in [10.0, 14.0]) { c.drawArc(Rect.fromCircle(center: Offset(x, 15), radius: 3), pi, -pi, false, p); }
    c.drawLine(const Offset(10, 15), const Offset(14, 15), p);
  }
  @override
  bool shouldRepaint(_Logo old) => old.color != color;
}

/// P1: Noir's old-film grain over the scenes (a new speckle 12 times a second; still with reduced motion).
class _Grain extends CustomPainter {
  _Grain(this.frame, this.color);
  final int frame;
  final Color color;
  @override
  void paint(Canvas c, Size size) {
    final r = Random(frame), n = (size.width * size.height / 500).round(), pts = Float32List(n * 2);
    for (var i = 0; i < n; i++) { pts[i * 2] = r.nextDouble() * size.width; pts[i * 2 + 1] = r.nextDouble() * size.height; }
    c.drawRawPoints(ui.PointMode.points, pts, Paint()..color = _a(color, .07)..strokeWidth = 1.3);
  }
  @override
  bool shouldRepaint(_Grain old) => old.frame != frame;
}
