// The Noir look (the old app's theme: dark paper, typewriter headings, hard black shadows) and shared pieces.
import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart';

import 'l10n/app_localizations.dart';

abstract final class C {
  static const bg = Color(0xFF0D0C0B), card = Color(0xFF191714), card2 = Color(0xFF23201C), line = Color(0xFF36312A),
      line2 = Color(0xFF4A433A), text = Color(0xFFECE4D4), mute = Color(0xFFA39A8B), dim = Color(0xFF6F675B),
      red = Color(0xFFB3241F), red2 = Color(0xFFE0574D), gold = Color(0xFFD4B483), green = Color(0xFF7FB08B),
      blue = Color(0xFF86A6C9), priText = Color(0xFFF6EFE2), alt = Color(0xFFE9E1D1), altText = Color(0xFF1C1915),
      night = Color(0xFF08090C), day = Color(0xFF120F0B), blood = Color(0xFF0C0606), glory = Color(0xFF0E0C06);
}

const head = TextStyle(fontFamily: 'Elite', fontFamilyFallback: ['Messiri'], letterSpacing: .4, color: C.text);

ThemeData noir() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true, fontFamily: 'Plex',
      colorScheme: const ColorScheme.dark(primary: C.red, onPrimary: C.priText, surface: C.card, onSurface: C.text, error: C.red2));
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    dividerColor: C.line,
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true, fillColor: C.card2, isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(3)), borderSide: BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(3)), borderSide: BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(3)), borderSide: BorderSide(color: C.red, width: 2)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.priText : C.mute),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.red : C.card2),
    ),
    sliderTheme: const SliderThemeData(activeTrackColor: C.red, thumbColor: C.red, inactiveTrackColor: C.line),
    dialogTheme: const DialogThemeData(backgroundColor: C.card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4)))),
  );
}

/// A Noir button: primary (red with a hard black shadow), or ghost (outlined). Disabled when onTap is null.
class Btn extends StatelessWidget {
  const Btn(this.label, {super.key, this.onTap, this.ghost = false, this.icon});
  final String label;
  final VoidCallback? onTap;
  final bool ghost;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null, fg = ghost ? C.text : C.priText;
    return Opacity(
      opacity: on ? 1 : .45,
      child: Container(
        decoration: BoxDecoration(
          color: ghost ? Colors.transparent : C.red,
          border: Border.all(color: ghost ? C.line2 : C.red),
          borderRadius: BorderRadius.circular(4),
          boxShadow: ghost || !on ? null : const [BoxShadow(color: Colors.black, offset: Offset(3, 3))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
                Flexible(child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: .5))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card section with an optional title.
class Sec extends StatelessWidget {
  const Sec({super.key, this.title, required this.child, this.color = C.card});
  final String? title;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(  // a Material (not a colored box), so switches and chips inside show their ripples
          color: color,
          shape: RoundedRectangleBorder(side: const BorderSide(color: C.line), borderRadius: BorderRadius.circular(4)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (title != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(title!.toUpperCase(), style: head.copyWith(fontSize: 14, color: C.mute, letterSpacing: 2))),
              child,
            ]),
          ),
        ),
      );
}

/// A full screen with a centered column, the night / day / blood / glory backdrop, and a bottom button bar.
class Stage extends StatelessWidget {
  const Stage({super.key, required this.children, this.bottom = const [], this.color = C.bg, this.center = true});
  final List<Widget> children, bottom;
  final Color color;
  final bool center;

  @override
  Widget build(BuildContext context) => Container(
        color: color,
        child: SafeArea(
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
        ),
      );
}

/// A big centered title with an optional line under it.
class Big extends StatelessWidget {
  const Big(this.text, {super.key, this.sub, this.color = C.text, this.size = 30});
  final String text;
  final String? sub;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(text, textAlign: TextAlign.center, style: head.copyWith(fontSize: size, color: color, height: 1.25)),
        if (sub != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(sub!, textAlign: TextAlign.center, style: const TextStyle(color: C.mute, fontSize: 15, height: 1.4))),
      ]);
}

String roleName(L l, Role r) => switch (r) { Role.mafia => l.mafia, Role.doctor => l.doctor, Role.detective => l.detective, Role.citizen => l.citizen };
Color roleColor(Role r) => switch (r) { Role.mafia => C.red2, Role.doctor => C.green, Role.detective => C.blue, Role.citizen => C.gold };
IconData roleIcon(Role r) => switch (r) {
      Role.mafia => Icons.dangerous_outlined, Role.doctor => Icons.healing_outlined, Role.detective => Icons.search, Role.citizen => Icons.person_outline
    };

/// "Are you sure?" Returns true on yes.
Future<bool> ask(BuildContext context, String q, String d, String yes) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(q, style: head.copyWith(fontSize: 20)),
        content: Text(d, style: const TextStyle(color: C.mute)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L.of(c).cancel, style: const TextStyle(color: C.mute))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(yes, style: const TextStyle(color: C.red2, fontWeight: FontWeight.w700))),
        ],
      ),
    ) ??
    false;
