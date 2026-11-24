import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

// The Noir look (the old app's theme: dark paper, typewriter headings, hard black shadows) and shared pieces.

/// One look of the app (S9-3): Noir (default) or Neon (the old app's default). Colours, fonts and shapes.
class Palette {
  const Palette({required this.name, required this.bg, required this.card, required this.card2, required this.line, required this.line2,
      required this.text, required this.mute, required this.dim, required this.red, required this.red2, required this.gold, required this.green,
      required this.blue, required this.priText, required this.alt, required this.altText, required this.night, required this.day, required this.blood,
      required this.glory, required this.roles, required this.body, required this.head, required this.headFallback, required this.headLs,
      required this.headWeight, required this.radius, required this.neon});
  final String name;
  final Color bg, card, card2, line, line2, text, mute, dim, red, red2, gold, green, blue, priText, alt, altText, night, day, blood, glory;
  final Map<Role, Color> roles;
  final String body, head;
  final List<String> headFallback;
  final double headLs, radius;
  final FontWeight headWeight;
  final bool neon; // glows, gradients, glassy cards
}

const noirPalette = Palette(name: 'noir',
    bg: Color(0xFF0D0C0B), card: Color(0xFF191714), card2: Color(0xFF23201C), line: Color(0xFF36312A), line2: Color(0xFF4A433A),
    text: Color(0xFFECE4D4), mute: Color(0xFFA39A8B), dim: Color(0xFF6F675B), red: Color(0xFFB3241F), red2: Color(0xFFE0574D),
    gold: Color(0xFFD4B483), green: Color(0xFF7FB08B), blue: Color(0xFF86A6C9), priText: Color(0xFFF6EFE2), alt: Color(0xFFE9E1D1),
    altText: Color(0xFF1C1915), night: Color(0xFF08090C), day: Color(0xFF120F0B), blood: Color(0xFF0C0606), glory: Color(0xFF0E0C06),
    roles: {Role.mafia: Color(0xFFE0574D), Role.doctor: Color(0xFF7FB08B), Role.detective: Color(0xFF86A6C9), Role.citizen: Color(0xFFD4B483)},
    body: 'Plex', head: 'Elite', headFallback: ['Messiri'], headLs: .4, headWeight: FontWeight.w400, radius: 4, neon: false);

/// The old app's Neon: violet-black with pink and blue glows, glassy cards, a pink-orange gradient, Readex Pro.
const neonPalette = Palette(name: 'neon',
    bg: Color(0xFF0B0A10), card: Color(0xFF17151E), card2: Color(0xFF211E2B), line: Color(0xFF2B2735), line2: Color(0xFF3E3850),
    text: Color(0xFFF4F2F8), mute: Color(0xFFA59FB3), dim: Color(0xFF6F6880), red: Color(0xFFFF2E63), red2: Color(0xFFFF5C84),
    gold: Color(0xFFFFB547), green: Color(0xFF3CE0A0), blue: Color(0xFF5AA2FF), priText: Color(0xFFFFFFFF), alt: Color(0xFF2B2440),
    altText: Color(0xFFF4F2F8), night: Color(0xFF0F1433), day: Color(0xFF2A1A12), blood: Color(0xFF2A0B16), glory: Color(0xFF2A2010),
    roles: {Role.mafia: Color(0xFFFF4D7D), Role.doctor: Color(0xFF3CE0A0), Role.detective: Color(0xFF5AA2FF), Role.citizen: Color(0xFFFFC65A)},
    body: 'Readex', head: 'Readex', headFallback: [], headLs: 0, headWeight: FontWeight.w700, radius: 16, neon: true);

/// The current look's colours. Set from Prefs.theme by the app before it builds.
abstract final class C {
  static Palette p = noirPalette;
  static bool get neon => p.neon;
  static Color get bg => p.bg;
  static Color get card => p.card;
  static Color get card2 => p.card2;
  static Color get line => p.line;
  static Color get line2 => p.line2;
  static Color get text => p.text;
  static Color get mute => p.mute;
  static Color get dim => p.dim;
  static Color get red => p.red;
  static Color get red2 => p.red2;
  static Color get gold => p.gold;
  static Color get green => p.green;
  static Color get blue => p.blue;
  static Color get priText => p.priText;
  static Color get alt => p.alt;
  static Color get altText => p.altText;
  static Color get night => p.night;
  static Color get day => p.day;
  static Color get blood => p.blood;
  static Color get glory => p.glory;
}

/// Headings: the typewriter in Noir, Readex bold in Neon.
TextStyle get head => TextStyle(fontFamily: C.p.head, fontFamilyFallback: C.p.headFallback, letterSpacing: C.p.headLs, color: C.text,
    fontWeight: C.p.headWeight, fontVariations: C.neon ? const [FontVariation('wght', 700)] : null);

/// Neon's gradients (the old app's CSS): the primary button and each backdrop.
const neonPrimary = LinearGradient(colors: [Color(0xFFFF2E63), Color(0xFFFF6A3D)], begin: Alignment.topLeft, end: Alignment.bottomRight);
BoxDecoration neonBackdrop(Color base) {
  final glow = base == neonPalette.night ? const Color(0xAA2A3AA0) : base == neonPalette.day ? const Color(0x66FF9A3D)
      : base == neonPalette.blood ? const Color(0x66FF2E63) : base == neonPalette.glory ? const Color(0x66FFB547) : const Color(0x44FF2E63);
  return BoxDecoration(gradient: RadialGradient(center: const Alignment(-.6, -1.1), radius: 1.1, colors: [glow, base], stops: const [0, .7]));
}

/// Noir's backdrop as the old app's CSS: a dark glow from the top (red on Home, blue at night, …) over the base colour.
BoxDecoration noirBackdrop(Color base) {
  final glow = base == noirPalette.night ? const Color(0x9914213D) : base == noirPalette.day ? const Color(0xAA5A4426)
      : base == noirPalette.blood ? const Color(0xAA6B0F0F) : base == noirPalette.glory ? const Color(0xAA5A4A1E) : const Color(0x664A0F0F);
  return BoxDecoration(color: base, gradient: RadialGradient(center: const Alignment(0, -1.15), radius: .95, colors: [glow, glow.withValues(alpha: 0)], stops: const [0, .7]));
}

/// Noir's faint horizontal lines (old CSS: a 2 px light line every 4 px).
class ScanLines extends CustomPainter {
  const ScanLines();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x04FFFFFF);
    for (var y = 0.0; y < size.height; y += 4) { canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), p); }
  }
  @override
  bool shouldRepaint(ScanLines old) => false;
}

ThemeData noir() {
  final r = BorderRadius.circular(C.p.radius);
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true, fontFamily: C.p.body,
      colorScheme: ColorScheme.dark(primary: C.red, onPrimary: C.priText, surface: C.card, onSurface: C.text, error: C.red2));
  return base.copyWith(
    // [his look note] every page over the old app's backdrop; the app bar see-through, the back button in a box
    scaffoldBackgroundColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: _BackdropTransitions(), TargetPlatform.iOS: _BackdropTransitions()}),
    appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0,
        foregroundColor: C.text, titleTextStyle: head.copyWith(fontSize: 22)),
    actionIconTheme: ActionIconThemeData(backButtonIconBuilder: (context) => Container(width: 40, height: 40, alignment: Alignment.center,
        decoration: BoxDecoration(color: C.card, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(C.neon ? 12 : 2)),
        child: Icon(Directionality.of(context) == TextDirection.rtl ? Icons.chevron_right : Icons.chevron_left, color: C.text, size: 22))),
    dividerColor: C.line,
    dividerTheme: DividerThemeData(color: C.line, space: 24), // Material 3 ignores dividerColor: dividers were white
    // [look] the old app's buttons: square-cornered, red filled, outlined in the line colour
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: C.priText,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(C.neon ? 12 : 3)))),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: C.red, foregroundColor: C.priText, elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(C.neon ? 12 : 3)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: C.text, side: BorderSide(color: C.line2),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(C.neon ? 12 : 3)))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(C.neon ? 12 : 3)))),
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: C.card2, isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(C.neon ? 12 : 3), borderSide: BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(C.neon ? 12 : 3), borderSide: BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(C.neon ? 12 : 3), borderSide: BorderSide(color: C.red, width: 2)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.priText : C.mute),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.red : C.card2),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: C.red, thumbColor: C.red, inactiveTrackColor: C.line),
    // [QA] Q2: chips were Material's default teal; the accent when selected
    chipTheme: ChipThemeData(selectedColor: C.red, backgroundColor: C.card, checkmarkColor: C.priText, side: BorderSide(color: C.line2),
        labelStyle: TextStyle(fontFamily: C.p.body, color: C.text), secondaryLabelStyle: TextStyle(fontFamily: C.p.body, color: C.priText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(C.neon ? 20 : 3))),
    dialogTheme: DialogThemeData(backgroundColor: C.card, shape: RoundedRectangleBorder(borderRadius: r)),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: C.card, modalBackgroundColor: C.card),
    // [N1] the message bar kept Flutter's dark text on our dark card: unreadable. Light text, a border, floating.
    snackBarTheme: SnackBarThemeData(backgroundColor: C.card2, contentTextStyle: TextStyle(color: C.text, fontFamily: C.p.body, fontSize: 14),
        actionTextColor: C.red2, behavior: SnackBarBehavior.floating, insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(side: BorderSide(color: C.line2), borderRadius: BorderRadius.circular(C.neon ? 14 : 4))),
  );
}

/// A button: primary (Noir red with a hard black shadow / Neon pink-orange gradient with a glow), or ghost (outlined).
/// Disabled when onTap is null.
class Btn extends StatelessWidget {
  const Btn(this.label, {super.key, this.onTap, this.ghost = false, this.icon});
  final String label;
  final VoidCallback? onTap;
  final bool ghost;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null, fg = ghost ? C.text : C.priText, neon = C.neon, r = BorderRadius.circular(neon ? 14 : 4);
    return Opacity(
      opacity: on ? 1 : .45,
      child: Container(
        decoration: BoxDecoration(
          color: ghost ? Colors.transparent : neon ? null : C.red,
          gradient: !ghost && neon ? neonPrimary : null,
          border: Border.all(color: ghost ? C.line2 : neon ? Colors.transparent : C.red),
          borderRadius: r,
          boxShadow: ghost || !on ? null : neon ? const [BoxShadow(color: Color(0x45FF2E63), blurRadius: 26, offset: Offset(0, 10))]
              : const [BoxShadow(color: Colors.black, offset: Offset(3, 3))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: r,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
                Flexible(child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: neon ? 0 : .5))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card section with an optional title (the old app's: an icon box, then spaced capitals in the body font).
class Sec extends StatelessWidget {
  const Sec({super.key, this.title, required this.child, this.color, this.action, this.icon});
  final String? title;
  final IconData? icon;
  final Widget? action; // on the title's row, at its end (R7: Ping everyone)
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(  // a Material (not a colored box), so switches and chips inside show their ripples
          color: color ?? C.card,
          shape: RoundedRectangleBorder(side: BorderSide(color: C.line), borderRadius: BorderRadius.circular(C.p.radius)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (title != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
                if (icon != null) ...[IconBox(icon!), const SizedBox(width: 10)],
                Expanded(child: Text(title!.toUpperCase(), style: capStyle)),
                ?action,
              ])),
              child,
            ]),
          ),
        ),
      );
}

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
    final b = Material(color: C.card2, shape: RoundedRectangleBorder(side: BorderSide(color: C.line), borderRadius: BorderRadius.circular(C.neon ? 10 : 2)),
        child: InkWell(onTap: onTap, child: SizedBox(width: size, height: size, child: Icon(icon, size: 18, color: onTap == null ? C.dim : C.text))));
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

/// The page backdrop under every screen (Noir: the glow from the top and the faint lines; Neon: its glows).
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(decoration: C.neon ? neonBackdrop(C.bg) : noirBackdrop(C.bg),
      child: CustomPaint(painter: C.neon ? null : const ScanLines(), child: child));
}

/// Android's own page transition, with the backdrop painted under each page (pages are see-through to show it).
class _BackdropTransitions extends PageTransitionsBuilder {
  const _BackdropTransitions();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> a, Animation<double> b, Widget child) =>
      (const PageTransitionsTheme().builders[TargetPlatform.android] ?? const ZoomPageTransitionsBuilder())
          .buildTransitions(route, context, a, b, Backdrop(child: child));
}

/// A full screen with a centered column, the night / day / blood / glory backdrop, and a bottom button bar.
class Stage extends StatelessWidget {
  const Stage({super.key, required this.children, this.bottom = const [], this.color, this.center = true});
  final List<Widget> children, bottom;
  final Color? color;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? C.bg;
    return Container(
        decoration: C.neon ? neonBackdrop(bg) : noirBackdrop(bg),
        child: CustomPaint(painter: C.neon ? null : const ScanLines(), child: SafeArea(
          child: Column(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, c) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight - 24),
                      child: Column(mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                    ),
                  )),
            ),
            if (bottom.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final b in bottom) Padding(padding: const EdgeInsets.only(top: 10), child: b)]),
              ),
          ]),
        )),
      );
  }
}

/// A big centered title with an optional line under it.
class Big extends StatelessWidget {
  const Big(this.text, {super.key, this.sub, this.color, this.size = 30});
  final String text;
  final String? sub;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(text, textAlign: TextAlign.center, style: head.copyWith(fontSize: size, color: color ?? C.text, height: 1.25)),
        if (sub != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(sub!, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 15, height: 1.4))),
      ]);
}

/// "@handle" kept left-to-right inside Arabic text (it would show as "handle@" otherwise). Empty without a handle.
String atHandle(String? h) => h == null || h.isEmpty ? '' : '\u2066@$h\u2069';

/// The direction of a piece of user text from its first letter ([QA] Q3: an English chat line inside the Arabic UI
/// put its leading "@" at the end): Arabic / Hebrew → right-to-left, anything else → left-to-right.
TextDirection dirOf(String s) {
  for (final r in s.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFEFC)) return TextDirection.rtl;
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

String roleName(L l, Role r) => switch (r) { Role.mafia => l.mafia, Role.doctor => l.doctor, Role.detective => l.detective, Role.citizen => l.citizen };
Color roleColor(Role r) => C.p.roles[r]!;
IconData roleIcon(Role r) => switch (r) {
      Role.mafia => Icons.dangerous_outlined, Role.doctor => Icons.healing_outlined, Role.detective => Icons.search, Role.citizen => Icons.person_outline
    };

/// "Are you sure?" Returns true on yes.
Future<bool> ask(BuildContext context, String q, String d, String yes) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(q, style: head.copyWith(fontSize: 20)),
        content: Text(d, style: TextStyle(color: C.mute)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L.of(c).cancel, style: TextStyle(color: C.mute))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(yes, style: TextStyle(color: C.red2, fontWeight: FontWeight.w700))),
        ],
      ),
    ) ??
    false;
