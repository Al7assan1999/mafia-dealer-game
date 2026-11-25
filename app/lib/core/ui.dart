import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';
import 'package:mafia_dealer/core/look.dart';
export 'package:mafia_dealer/core/look.dart';

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
    roles: {Role.mafia: Color(0xFFE0574D), Role.doctor: Color(0xFF7FB08B), Role.detective: Color(0xFF86A6C9), Role.citizen: Color(0xFFD4B483),
      Role.sniper: Color(0xFFB79AD6), Role.jester: Color(0xFFE39A5B)},
    body: 'Plex', head: 'Elite', headFallback: ['Messiri'], headLs: .4, headWeight: FontWeight.w400, radius: 4, neon: false);

/// The old app's Neon: violet-black with pink and blue glows, glassy cards, a pink-orange gradient, Readex Pro.
const neonPalette = Palette(name: 'neon',
    bg: Color(0xFF0B0A10), card: Color(0xFF17151E), card2: Color(0xFF211E2B), line: Color(0xFF2B2735), line2: Color(0xFF3E3850),
    text: Color(0xFFF4F2F8), mute: Color(0xFFA59FB3), dim: Color(0xFF6F6880), red: Color(0xFFFF2E63), red2: Color(0xFFFF5C84),
    gold: Color(0xFFFFB547), green: Color(0xFF3CE0A0), blue: Color(0xFF5AA2FF), priText: Color(0xFFFFFFFF), alt: Color(0xFF2B2440),
    altText: Color(0xFFF4F2F8), night: Color(0xFF0F1433), day: Color(0xFF2A1A12), blood: Color(0xFF2A0B16), glory: Color(0xFF2A2010),
    roles: {Role.mafia: Color(0xFFFF4D7D), Role.doctor: Color(0xFF3CE0A0), Role.detective: Color(0xFF5AA2FF), Role.citizen: Color(0xFFFFC65A),
      Role.sniper: Color(0xFFB98CFF), Role.jester: Color(0xFFFF8A3D)},
    body: 'Readex', head: 'Readex', headFallback: [], headLs: 0, headWeight: FontWeight.w700, radius: 22, neon: true);

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
/// [S14-7 / his #6] Neon's backdrops, as the old CSS (--bgfx, --bg-night …): a dark violet gradient with a pink glow at
/// the top start and a blue one at the top end (Home and pages); the game screens: one coloured glow from the top centre.
Widget neonBackdrop(Color base, Widget child) {
  RadialGradient glow(Alignment at, double r, Color c) => RadialGradient(center: at, radius: r, colors: [c, c.withValues(alpha: 0)], stops: const [0, .7]);
  LinearGradient lin(Color a, Color b, double stop) =>
      LinearGradient(begin: const Alignment(-.15, -1), end: const Alignment(.15, 1), colors: [a, b], stops: [0, stop]);
  final (LinearGradient bg, List<RadialGradient> glows) = base == neonPalette.night ? (lin(const Color(0xFF0F1433), const Color(0xFF06070F), .65), [glow(const Alignment(0, -1.16), .8, const Color(0xAA2A3AA0))])
      : base == neonPalette.day ? (lin(const Color(0xFF2A1A12), const Color(0xFF0D0A08), .65), [glow(const Alignment(0, -1.16), .8, const Color(0x66FF9A3D))])
      : base == neonPalette.blood ? (lin(const Color(0xFF2A0B16), const Color(0xFF0B0508), .65), [glow(const Alignment(0, -1.16), .85, const Color(0x66FF2E63))])
      : base == neonPalette.glory ? (lin(const Color(0xFF2A2010), const Color(0xFF0D0A05), .65), [glow(const Alignment(0, -1.16), .85, const Color(0x66FFB547))])
      : (lin(const Color(0xFF17131F), const Color(0xFF0B0A10), .6),
          [glow(const Alignment(-.84, -1.12), .62, const Color(0x44FF2E63)), glow(const Alignment(1.08, -.76), .58, const Color(0x303D6BFF))]);
  Widget w = child;
  for (final g in glows.reversed) { w = DecoratedBox(decoration: BoxDecoration(gradient: g), child: w); }
  return DecoratedBox(decoration: BoxDecoration(gradient: bg), child: w);
}

/// Noir's backdrop as the old app's CSS: a dark glow from the top (red on Home, blue at night, …) over the base colour.
BoxDecoration noirBackdrop(Color base) {
  final glow = base == noirPalette.night ? const Color(0x9914213D) : base == noirPalette.day ? const Color(0xAA5A4426)
      : base == noirPalette.blood ? const Color(0xAA6B0F0F) : base == noirPalette.glory ? const Color(0xAA5A4A1E) : const Color(0x664A0F0F);
  // a gradient hides the box's colour: the glow fades into the base colour itself (it faded into nothing: black)
  return BoxDecoration(gradient: RadialGradient(center: const Alignment(0, -1.15), radius: .95, colors: [Color.alphaBlend(glow, base), base], stops: const [0, .7]));
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
        child: Icon(Icons.chevron_left, color: C.text, size: 22))), // mirrors itself in Arabic (matchTextDirection)
    dividerColor: C.line,
    dividerTheme: DividerThemeData(color: C.line, space: 24),
    tabBarTheme: TabBarThemeData(dividerColor: C.line, indicatorColor: C.red, labelColor: C.text, unselectedLabelColor: C.mute,
        labelStyle: TextStyle(fontFamily: C.p.body, fontWeight: FontWeight.w700), unselectedLabelStyle: TextStyle(fontFamily: C.p.body)), // Material 3 ignores dividerColor: dividers were white
    // [look] the old app's buttons: square-cornered, red filled, outlined in the line colour
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: C.priText,
        textStyle: TextStyle(fontFamily: C.p.body, fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(C.neon ? 12 : 3)))),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: C.red, foregroundColor: C.priText, elevation: 0,
        textStyle: TextStyle(fontFamily: C.p.body, fontWeight: FontWeight.w700, fontSize: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(C.neon ? 12 : 3)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: C.text, side: BorderSide(color: C.line2),
        textStyle: TextStyle(fontFamily: C.p.body, fontWeight: FontWeight.w700, fontSize: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(C.neon ? 12 : 3)))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: TextStyle(fontFamily: C.p.body, fontWeight: FontWeight.w700),
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
    // [S15-5] the old app's chips: the chosen one dark red with a red border, no checkmark
    chipTheme: ChipThemeData(selectedColor: C.neon ? C.red.withValues(alpha: .18) : const Color(0xFF3A1512), backgroundColor: C.card, showCheckmark: false,
        side: WidgetStateBorderSide.resolveWith((s) => BorderSide(color: s.contains(WidgetState.selected) ? C.red : C.line2)),
        labelStyle: TextStyle(fontFamily: C.p.body, color: C.text, fontWeight: FontWeight.w700), secondaryLabelStyle: TextStyle(fontFamily: C.p.body, color: C.text, fontWeight: FontWeight.w700),
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
  const Btn(this.label, {super.key, this.onTap, this.ghost = false, this.icon, this.gold = false});
  final String label;
  final VoidCallback? onTap;
  final bool ghost;
  final bool gold; // [S14] the old .btn.gold (Resume game): gold paper, dark text
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null, fg = ghost ? C.text : gold ? (C.neon ? const Color(0xFF1D1206) : C.altText) : C.priText, neon = C.neon, r = BorderRadius.circular(neon ? 14 : 4);
    return Opacity(
      opacity: on ? 1 : .45,
      child: Container(
        decoration: BoxDecoration(
          color: ghost ? Colors.transparent : gold ? (neon ? null : C.alt) : neon ? null : C.red,
          gradient: ghost ? null : gold && neon ? const LinearGradient(colors: [Color(0xFFFFB547), Color(0xFFFF7A3D)]) : neon ? neonPrimary : null,
          border: Border.all(color: ghost ? C.line2 : neon ? Colors.transparent : gold ? C.alt : C.red),
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

/// The page backdrop under every screen (Noir: the glow from the top and the faint lines; Neon: its glows).
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => C.neon ? neonBackdrop(C.bg, child)
      : DecoratedBox(decoration: noirBackdrop(C.bg), child: CustomPaint(painter: const ScanLines(), child: child));
}

/// [S14-5 / his #4] A gentle page change: the new page fades in and slides up a little (and back out). The
/// backdrop is painted under each page (pages are see-through to show it). No motion when Android's animations are off.
class _BackdropTransitions extends PageTransitionsBuilder {
  const _BackdropTransitions();
  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> a, Animation<double> b, Widget child) {
    final page = Backdrop(child: child);
    if (MediaQuery.of(context).disableAnimations) return page;
    final inC = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(opacity: inC, child: SlideTransition(position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(inC), child: page));
  }
}

/// A full screen with a centered column, the night / day / blood / glory backdrop, and a bottom button bar.
class Stage extends StatelessWidget {
  const Stage({super.key, required this.children, this.bottom = const [], this.color, this.center = true, this.card = false, this.foot});
  final List<Widget> children, bottom;
  final Color? color;
  final bool center;
  /// [S14-6] the old app's game screens: everything, buttons included, in one central card; [foot] under the screen
  /// ("Round 1 · 6/6 alive")
  final bool card;
  final String? foot;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? C.bg;
    final page = Container(
        decoration: C.neon ? null : noirBackdrop(bg),
        child: CustomPaint(painter: C.neon ? null : const ScanLines(), child: SafeArea(
          child: Column(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, c) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight - 24),
                      child: Column(mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.stretch, children: !card ? children : [
                            Container(padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                                decoration: BoxDecoration(color: C.neon ? C.card.withValues(alpha: .86) : C.card, border: Border.all(color: C.line),
                                    borderRadius: BorderRadius.circular(C.neon ? 22 : 6)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  ...children,
                                  for (final b in bottom) Padding(padding: const EdgeInsets.only(top: 12), child: b),
                                ])),
                          ]),
                    ),
                  )),
            ),
            if (foot != null) Padding(padding: const EdgeInsets.only(bottom: 14, top: 4), child: Text(foot!, key: const Key('stageFoot'), style: TextStyle(color: C.mute, fontSize: 14))),
            if (bottom.isNotEmpty && !card)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final b in bottom) Padding(padding: const EdgeInsets.only(top: 10), child: b)]),
              ),
          ]),
        )),
      );
    return C.neon ? neonBackdrop(bg, page) : page;
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

String roleName(L l, Role r) => switch (r) {
      Role.mafia => l.mafia, Role.doctor => l.doctor, Role.detective => l.detective, Role.citizen => l.citizen,
      Role.sniper => l.sniper, Role.jester => l.jester,
    };
/// A seat's role as the table sees it: the Sheikh (1.0.0) is a Mafia with his own name.
String seatRole(L l, Role r, bool sheikh) => sheikh && r == Role.mafia ? l.sheikh : roleName(l, r);
String roleDesc(L l, Role r) => switch (r) {
      Role.mafia => l.dMafia, Role.doctor => l.dDoctor, Role.detective => l.dDetective, Role.citizen => l.dCitizen,
      Role.sniper => l.dSniper, Role.jester => l.dJester,
    };
/// [S17 P2] the role's side and how it wins, in one line
String sideLine(L l, Role r) => switch (r) { Role.mafia => l.sideMafia, Role.jester => l.sideJester, _ => l.sideTown };
Color roleColor(Role r) => C.p.roles[r]!;
IconData roleIcon(Role r) => switch (r) {
      Role.mafia => Icons.dangerous_outlined, Role.doctor => Icons.healing_outlined, Role.detective => Icons.search, Role.citizen => Icons.person_outline,
      Role.sniper => Icons.gps_fixed, Role.jester => Icons.theater_comedy_outlined,
    };
/// A role the engine names that this app doesn't know (a later version): null (the screens say "Update the app").
Role? roleOf(Object? r) => r is String ? Role.values.asNameMap()[r] : null;

/// The night screen's title and line for a night key (engine nightOptions().key).
(String, String) nightText(L l, String key) => switch (key) {
      'mafia' => (l.aMafia, l.aMafiaD), 'doctor' => (l.aDoctor, l.aDoctorD), 'detective' => (l.aDetective, l.aDetectiveD),
      'citizen' => (l.aCitizen, l.aCitizenD), 'sniper' => (l.aSniper, l.aSniperD), _ => (l.aNone, l.aNoneD),
    };

/// Who won, from a Winner or its name ('mafia' | 'citizens' | 'jester').
String winText(L l, Object? w) => switch (w is Winner ? w.name : w) { 'mafia' => l.winMafia, 'jester' => l.jesterWins, _ => l.winCitizens };
IconData winIcon(Object? w) => switch (w is Winner ? w.name : w) {
      'mafia' => Icons.dangerous_outlined, 'jester' => Icons.theater_comedy_outlined, _ => Icons.emoji_events_outlined };
Color winColor(Object? w) => switch (w is Winner ? w.name : w) { 'mafia' => C.red2, 'jester' => roleColor(Role.jester), _ => C.gold };

/// Why the player of the game (engine mvp()) earned it.
String mvpWhy(L l, String why, int? n) => switch (why) {
      'mafia' => l.mvpMafia, 'mafia2' => l.mvpMafia2, 'det' => l.mvpDet(n ?? 1), 'doc' => l.mvpDoc(n ?? 1), 'jester' => l.mvpJester, _ => l.mvpSurv };

String modeName(L l, Mode m) => switch (m) { 'sniper' => l.modeSniper, 'jester' => l.modeJester, 'all' => l.modeAll, _ => l.modeClassic };
String modeLine(L l, Mode m) => switch (m) { 'sniper' => l.mSniper, 'jester' => l.mJester, 'all' => l.mAll, _ => l.mClassic };
/// [S17 P1] the mode the setup marks as Suggested for this many players
Mode suggestedMode(int n) => n >= modeMin['all']! ? 'all' : n >= modeMin['sniper']! ? 'sniper' : 'classic';

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
