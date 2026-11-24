part of 'intro_screen.dart';

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
