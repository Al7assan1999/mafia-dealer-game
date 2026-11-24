// The old app's building blocks (S13 look, S14): small caps, icon boxes, segmented choices, square switch and buttons,
// rows, numbered picks, the boxed tag and the icon box of the game screens. Exported by ui.dart.
import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/ui.dart';

/// The old app's small caps title (.sh h3): body font, bold, spaced capitals, muted.
TextStyle get capStyle => TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: C.neon ? 1 : 2.1, color: C.mute, height: 1.3);

/// A small square with an icon (a section's mark, the old .gi).
class IconBox extends StatelessWidget {
  const IconBox(this.icon, {super.key, this.size = 26, this.color});
  final IconData icon;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(C.neon ? 8 : 2)),
      child: Icon(icon, size: size * .58, color: color ?? C.gold));
}

/// The old app's segmented choice (.seg): a dark well, the chosen option filled red. [keys] name each option.
class Seg<T> extends StatelessWidget {
  const Seg({super.key, required this.options, required this.value, required this.onChanged, this.expand = false});
  final List<(T, String, Key?)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expand; // full width, the options sharing it
  @override
  Widget build(BuildContext context) {
    final r = C.neon ? 12.0 : 3.0;
    Widget opt((T, String, Key?) o) {
      final on = o.$1 == value;
      return Material(color: on ? C.red : Colors.transparent, borderRadius: BorderRadius.circular(r - 1),
          child: InkWell(key: o.$3, borderRadius: BorderRadius.circular(r - 1), onTap: () => onChanged(o.$1), child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Text(o.$2, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? C.priText : C.mute)))));
    }
    return Container(padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: Color.lerp(C.bg, C.card, .5), border: Border.all(color: C.line), borderRadius: BorderRadius.circular(r)),
        child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [
          for (final (i, o) in options.indexed) ...[if (i > 0) const SizedBox(width: 3), expand ? Expanded(child: opt(o)) : opt(o)],
        ]));
  }
}

/// The old app's square switch (Noir; Neon keeps Material's): red when on, a light square sliding across.
class SqSwitch extends StatelessWidget {
  const SqSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    if (C.neon) return Switch(value: value, onChanged: onChanged);
    return Semantics(toggled: value, child: GestureDetector(onTap: onChanged == null ? null : () => onChanged!(!value), child: AnimatedContainer(
      duration: const Duration(milliseconds: 160), width: 56, height: 32, padding: const EdgeInsets.all(4),
      alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      decoration: BoxDecoration(color: value ? C.red : C.card2, border: Border.all(color: value ? C.red : C.line2), borderRadius: BorderRadius.circular(2)),
      child: Container(width: 22, height: 22, decoration: BoxDecoration(color: value ? C.priText : C.mute, borderRadius: BorderRadius.circular(1))),
    )));
  }
}

/// A square − / + / × button with a border (the old app's .stp and the remove button).
class SqBtn extends StatelessWidget {
  const SqBtn(this.icon, {super.key, this.onTap, this.size = 40, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final b = Material(color: C.card2, shape: RoundedRectangleBorder(side: BorderSide(color: C.line), borderRadius: BorderRadius.circular(C.neon ? size / 2 : 2)),
        clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: SizedBox(width: size, height: size, child: Icon(icon, size: 18, color: onTap == null ? C.dim : C.text))));
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

/// A number in a small square (a player's seat, the old .num).
class NumBox extends StatelessWidget {
  const NumBox(this.n, {super.key, this.size = 30});
  final int n;
  final double size;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(C.neon ? 8 : 2)),
      child: Text('$n', style: TextStyle(color: C.mute, fontWeight: FontWeight.w700, fontSize: 14)));
}

/// A settings-style row (the old .tg): a bold label, a muted line under it, a control at the end.
class OptRow extends StatelessWidget {
  const OptRow(this.label, {super.key, this.desc, this.trailing, this.onTap, this.onLongPress, this.descKey});
  final String label;
  final String? desc;
  final Widget? trailing;
  final VoidCallback? onTap, onLongPress;
  final Key? descKey;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, onLongPress: onLongPress, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.text)),
          if (desc != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(desc!, key: descKey, style: TextStyle(fontSize: 13, color: C.mute, height: 1.35))),
        ])),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ])));
}

/// A player to pick (night, vote), as the old app's .opt: a number box, the name, its tags, a square checkbox.
/// [seat] shows as the number (null for "skip").
class PickRow extends StatelessWidget {
  const PickRow({super.key, required this.label, this.seat, required this.on, this.onTap, this.tags = const [], this.accent});
  final String label;
  final int? seat;
  final bool on;
  final VoidCallback? onTap; // null = can't be picked
  final List<String> tags;
  final Color? accent;
  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(C.p.radius), sq = BorderRadius.circular(C.neon ? 8 : 2);
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Opacity(opacity: onTap == null ? .4 : 1, child: Material(
      color: on ? (C.neon ? C.red.withValues(alpha: .18) : const Color(0xFF3A1512)) : C.card,
      shape: RoundedRectangleBorder(side: BorderSide(color: on ? C.red : C.line, width: on ? 2 : 1), borderRadius: r),
      child: InkWell(borderRadius: r, onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(children: [
        Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(color: C.card2, borderRadius: sq),
            child: seat == null ? Icon(Icons.block, size: 16, color: C.mute) : NumBox(seat! + 1)),
        const SizedBox(width: 12),
        // the tags follow the name and wrap under it on a narrow phone
        Expanded(child: Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: accent ?? C.text)),
          for (final t in tags) Text(t, style: TextStyle(color: C.mute, fontSize: 12, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(width: 10),
        Container(width: 24, height: 24, decoration: BoxDecoration(color: on ? C.red : null, border: Border.all(color: on ? C.red : C.line2, width: 2), borderRadius: sq),
            child: on ? Icon(Icons.check, size: 16, color: C.priText) : null),
      ]))),
    )));
  }
}

/// [S14-6] The old game screens' boxed tag ("Morning of Day 1", "Night 1"): the heading font, gold, in a thin box.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(color: (color ?? C.gold).withValues(alpha: .1), border: Border.all(color: (color ?? C.gold).withValues(alpha: .45)),
          borderRadius: BorderRadius.circular(C.neon ? 20 : 2)),
      child: Text(text, textAlign: TextAlign.center, style: head.copyWith(fontSize: 15, color: color ?? C.gold))));
}

/// [S14-6] The big icon of a game screen, in a box (the old .glyph).
class GlyphBox extends StatelessWidget {
  const GlyphBox(this.icon, {super.key, this.color});
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) => Center(child: Container(width: 92, height: 92, alignment: Alignment.center,
      decoration: BoxDecoration(color: C.card2, border: Border.all(color: C.line2), borderRadius: BorderRadius.circular(C.neon ? 26 : 4)),
      child: Icon(icon, size: 46, color: color ?? C.text)));
}

/// The old app's mark (a hat and a moustache), in one colour.
class HatMark extends StatelessWidget {
  const HatMark({super.key, required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: _Mark(color));
}

/// The old SVG (24 × 24): M3 11h18 · M5 11l1.5-6h11L19 11 · two half circles under the brim · M10 15h4.
class _Mark extends CustomPainter {
  const _Mark(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    canvas.drawPath(Path()..moveTo(3, 11)..lineTo(21, 11)..moveTo(5, 11)..lineTo(6.5, 5)..lineTo(17.5, 5)..lineTo(19, 11)
      ..moveTo(7, 15)..arcToPoint(const Offset(13, 15), radius: const Radius.circular(3), largeArc: true, clockwise: false)
      ..moveTo(11, 15)..arcToPoint(const Offset(17, 15), radius: const Radius.circular(3), largeArc: true, clockwise: false)
      ..moveTo(10, 15)..lineTo(14, 15), p);
  }
  @override
  bool shouldRepaint(_Mark old) => old.color != color;
}

/// [S15] A switch row as the old app's (.tg): the label, a muted line, the square switch; the whole row toggles.
class SqSwitchTile extends StatelessWidget {
  const SqSwitchTile({super.key, required this.title, this.subtitle, required this.value, required this.onChanged, this.small = false});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool small; // the rules card's rows
  @override
  Widget build(BuildContext context) => InkWell(onTap: onChanged == null ? null : () => onChanged!(!value), child: Padding(
      padding: EdgeInsets.symmetric(vertical: small ? 8 : 12), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: small ? 14 : 15, fontWeight: small ? FontWeight.w400 : FontWeight.w700, color: C.text)),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(subtitle!, style: TextStyle(fontSize: small ? 12 : 13, color: C.mute, height: 1.35))),
        ])),
        const SizedBox(width: 12),
        Opacity(opacity: onChanged == null ? .45 : 1, child: SqSwitch(value: value, onChanged: onChanged)),
      ])));
}
