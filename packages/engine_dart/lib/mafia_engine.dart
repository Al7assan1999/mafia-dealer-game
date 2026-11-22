/// The Mafia Dealer rules: the Dart copy of packages/engine. Both must replay
/// packages/engine/fixtures/records.json identically (test/engine_test.dart).
library;

export 'src/game.dart' show apply, nightOptions, aliveSeats, timerLeft;
export 'src/record.dart';
export 'src/setup.dart';
export 'src/types.dart';
export 'src/view.dart';

/// A repeatable random source (mulberry32, the same numbers as the TypeScript `seeded`).
double Function() seeded(int seed) {
  var a = seed & 0xFFFFFFFF;
  return () {
    a = (a + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = a;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296;
  };
}

/// Math.imul on unsigned 32-bit values, without relying on 64-bit overflow.
int _imul(int a, int b) {
  final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF, bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
  return (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)) & 0xFFFFFFFF;
}
