import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/ui.dart';

// ---------------------------------------------------------------- buzz and ping (R7)
/// Bumped by every buzz / ping that arrives: [BuzzFlash] flashes the screen red.
final buzzFlash = ValueNotifier<int>(0);
/// A buzz or a ping arriving, as the old app's buzzFx: a double vibration, the hit sound (even with narration off on this
/// phone) and a red flash.
void buzzFx(Audio? audio) {
  const MethodChannel('mafia/keep').invokeMethod('vibrate').catchError((_) { HapticFeedback.heavyImpact(); return null; });
  audio?.sfx('hit_good', 0, true);
  buzzFlash.value++;
}

/// The red flash over every screen (MaterialApp.builder).
class BuzzFlash extends StatelessWidget {
  const BuzzFlash({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(child: ValueListenableBuilder(valueListenable: buzzFlash, builder: (context, n, _) => n == 0
      ? const SizedBox.shrink()
      : TweenAnimationBuilder<double>(key: ValueKey(n), tween: Tween(begin: .35, end: 0), duration: const Duration(milliseconds: 450),
          builder: (context, o, _) => ColoredBox(color: C.red.withValues(alpha: o), child: const SizedBox.expand()))));
}
