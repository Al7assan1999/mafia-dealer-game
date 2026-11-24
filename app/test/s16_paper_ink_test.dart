// [BA] S16-5 (docs/sprint-16-prd.md): Noir's role colours read at 1.9-2.9:1 on the paper recap.
// One file per Sprint 16 change, so each can be reverted on its own.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/ui.dart' show C;
import 'package:mafia_dealer/features/offline/recap_card.dart';
import 'package:mafia_engine/mafia_engine.dart';

void main() {
  test('the recap role inks read at 4.5:1 or more on the Noir paper and on the player-of-the-game box', () {
    double contrast(Color a, Color b) { final x = a.computeLuminance(), y = b.computeLuminance(); return (max(x, y) + .05) / (min(x, y) + .05); }
    const paper = Color(0xFFE9E1D1);
    final mvpBox = Color.alphaBlend(const Color(0x10000000), paper);
    expect(C.neon, isFalse);
    expect(C.alt, paper, reason: 'the paper colour this check is about');
    for (final r in Role.values) {
      expect(contrast(RecapCard.paperInk[r]!, paper), greaterThanOrEqualTo(4.5), reason: '$r on the paper');
      expect(contrast(RecapCard.paperInk[r]!, mvpBox), greaterThanOrEqualTo(4.5), reason: '$r on the player-of-the-game box');
    }
  });
}
