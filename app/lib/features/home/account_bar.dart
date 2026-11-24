import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/avatar.dart';
import 'package:mafia_dealer/features/account/profile_screen.dart';
import 'package:mafia_dealer/features/account/sign_in_screen.dart';
import 'package:mafia_dealer/features/notifications/bell_sheet.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

// ---------------------------------------------------------------- home top row
/// [S14-3 / his #3] Home's top row as the old app's: a round avatar (or a person: sign in) and the bell at the start;
/// the language flag, the look and Settings in boxes at the end. Friends are in the side drawer (as the old app).
class AccountBar extends StatelessWidget {
  const AccountBar({super.key, required this.account, required this.prefs, required this.onSettings});
  final Account account;
  final Prefs prefs;
  final VoidCallback onSettings;

  Widget _box(BuildContext context, Key key, String tip, Widget child, VoidCallback onTap) => Tooltip(message: tip, child: Material(
      color: C.card, shape: RoundedRectangleBorder(side: BorderSide(color: C.line), borderRadius: BorderRadius.circular(C.neon ? 14 : 2)),
      child: InkWell(key: key, onTap: onTap, child: SizedBox(width: 42, height: 42, child: Center(child: child)))));

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: account, builder: (context, _) {
        final l = L.of(context), a = account;
        void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
        final avatar = Material(color: C.card, shape: CircleBorder(side: BorderSide(color: C.line2)), clipBehavior: Clip.antiAlias, child: InkWell(
            key: Key(a.signedIn ? 'profile' : 'signIn'),
            onTap: () => go(!a.signedIn ? SignInScreen(account: a) : a.needsHandle ? HandleScreen(account: a) : ProfileScreen(account: a)),
            child: SizedBox(width: 50, height: 50, child: Center(child: a.signedIn ? AvatarView.of(a.api, a.card!, size: 50) : Icon(Icons.person_outline, color: C.mute, size: 26)))));
        return Row(children: [
          Tooltip(message: a.signedIn ? (a.handle != null ? atHandle(a.handle) : a.display) : l.aIn, child: avatar),
          if (a.signedIn) ...[
            const SizedBox(width: 8),
            _box(context, const Key('bell'), l.notifT, Badge(isLabelVisible: a.unread > 0, label: Text('${a.unread}'), child: Icon(Icons.notifications_none, color: C.mute, size: 21)),
                () => showModalBottomSheet(context: context, backgroundColor: C.card, isScrollControlled: true, useSafeArea: true, builder: (_) => BellSheet(account: a))),
          ],
          if (a.offline) Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: Text(l.eOfflineShort, style: TextStyle(color: C.dim, fontSize: 12))),
          const Spacer(),
          _box(context, const Key('homeLang'), l.language, Text(prefs.lang == 'ar' ? '\u{1F1F8}\u{1F1E6}' : '\u{1F1EC}\u{1F1E7}', style: const TextStyle(fontSize: 20)),
              () => prefs.lang = prefs.lang == 'ar' ? 'en' : 'ar'),
          const SizedBox(width: 8),
          _box(context, const Key('homeTheme'), l.sLook, Icon(Icons.palette_outlined, color: C.mute, size: 21), () => prefs.theme = prefs.theme == 'noir' ? 'neon' : 'noir'),
          const SizedBox(width: 8),
          _box(context, const Key('settings'), l.settingsT, Icon(Icons.settings_outlined, color: C.mute, size: 21), onSettings),
        ]);
      });
}

/// The old app's mark: a hat and a moustache. Noir: red lines in a tilted red square. Neon: white lines on the
/// pink-orange tile with a glow.
class HomeLogo extends StatelessWidget {
  const HomeLogo({super.key});
  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(size: const Size(48, 48), painter: _Mark(C.neon ? Colors.white : C.red));
    if (C.neon) {
      return Container(width: 86, height: 86, alignment: Alignment.center,
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF2E63), Color(0xFFFF8A3D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x50FF2E63), blurRadius: 30, offset: Offset(0, 12))]),
          child: mark);
    }
    return Transform.rotate(angle: -.105, child: Container(width: 86, height: 86, alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: C.red, width: 2), borderRadius: BorderRadius.circular(6)), child: mark));
  }
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
