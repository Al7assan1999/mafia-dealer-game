// [QA] Sprint 10: the intro (scenes, captions, first launch without Skip, Back, Settings, How to play, rooms and
// notifications going straight through, updates counting as seen, reduced motion) and the How to play hand-off (P4).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/features/intro/intro_screen.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver.dart';
import 'harness.dart';

const _scenes = [3.6, 4.0, 4.4, 3.4, 3.0, 3.8];

Future<void> secs(WidgetTester t, double s) async {
  for (var i = 0; i < (s * 10).round(); i++) { await t.pump(const Duration(milliseconds: 100)); }
}
Finder _key(String k) => find.byKey(Key(k));
String _cap(WidgetTester t) => (t.widget(_key('introCap')) as Text).data!;
String _say(WidgetTester t) => (t.widget(_key('introSay')) as Text).data!;

void main() {
  setUpAll(setUpHarness);
  setUp(() { IntroScreen.ran = false; guideGlow.value = false; });

  test('a new install has not seen the intro; any earlier data (an update from 0.2.0) counts as seen', () async {
    SharedPreferences.setMockInitialValues({});
    var p = await Prefs.load();
    p.firstLaunch();
    expect(p.introSeen, false);
    SharedPreferences.setMockInitialValues({'lastBuild': 100001, 'lang': 'ar'});
    p = await Prefs.load();
    p.firstLaunch();
    expect(p.introSeen, true);
    expect(p.introAtStart, false); // off by default
  });

  testWidgets('first launch: six scenes on their own, captions typed, no Skip, Back does nothing, then the title until a tap', (t) async {
    final a = await launch(t, stored: {'introSeen': false});
    await t.pump();
    expect(_key('intro'), findsOneWidget);
    expect(_key('introSkip'), findsNothing);
    await secs(t, .6);
    expect(_cap(t), 'A quiet town. Everyone knows everyone.');
    // [QA] it is on screen, not just in the tree (a fade value defaulting to 0 once hid the whole intro)
    expect(t.widget<Opacity>(find.ancestor(of: _key('intro'), matching: find.byType(Opacity)).first).opacity, 1);
    await t.binding.handlePopRoute(); // Back
    await t.pump();
    expect(_key('intro'), findsOneWidget);
    await secs(t, _scenes[0] + .1);
    expect(_cap(t), 'Then one night… something sounded wrong.');
    await secs(t, 1.8); // CRACK! at 1.7 s
    expect(find.text('CRACK!'), findsOneWidget);
    await secs(t, _scenes[1] - 1.8 + _scenes[2] + .6); // into the Doctor's scene
    expect(_say(t), isNot(isEmpty));
    expect('It could happen to anyone. I’ll keep you safe tonight.'.startsWith(_say(t)), true); // typing out
    await secs(t, 2.5);
    expect(_say(t), 'It could happen to anyone. I’ll keep you safe tonight.');
    await secs(t, _scenes[3] - 3.1 + _scenes[4] + 2.0); // the Mafia: HA HA HA
    expect(find.text('HA'), findsNWidgets(3));
    await secs(t, 10); // the title stays
    expect(_key('introGo'), findsOneWidget);
    expect(_key('intro'), findsOneWidget);
    expect(a.prefs.introSeen, false); // seen only once it's over
    await t.tap(_key('intro'));
    await secs(t, .8);
    expect(_key('intro'), findsNothing);
    expect(a.prefs.introSeen, true);
    expect(_key('guideGlow'), findsOneWidget); // P4: the How to play offer, highlighted
  });

  testWidgets('a tap moves on; Settings switches it on at start; Watch the intro has Skip; Back skips it', (t) async {
    final a = await launch(t);
    expect(_key('intro'), findsNothing); // seen already (and the test default): Home straight away
    await tapKey(t, 'settings');
    await t.pumpAndSettle();
    expect((t.widget(_key('introAtStart')) as SwitchListTile).value, false);
    await t.tap(_key('introAtStart'));
    expect(a.prefs.introAtStart, true);
    await t.ensureVisible(_key('watchIntro'));
    await t.tap(_key('watchIntro'));
    await secs(t, 1);
    expect(_key('intro'), findsOneWidget);
    expect(_key('introSkip'), findsOneWidget);
    await t.tap(_key('intro')); // to scene 2
    await secs(t, .5);
    expect(_cap(t), 'Then one night… something sounded wrong.');
    await t.tap(_key('introSkip'));
    await secs(t, .8);
    expect(_key('intro'), findsNothing);
    expect(_key('guideGlow'), findsNothing); // only "Tap to start" leads on to How to play
    // the mute button is remembered
    await t.tap(_key('settings'));
    await t.pumpAndSettle();
    await t.ensureVisible(_key('watchIntro'));
    await t.tap(_key('watchIntro'));
    await secs(t, .5);
    await t.tap(_key('introMute'));
    await t.pump();
    expect(a.prefs.introMute, true);
    await t.binding.handlePopRoute(); // Back skips it (not the first launch)
    await secs(t, .8);
    expect(_key('intro'), findsNothing);
  });

  testWidgets('with "Show the intro at start" on it plays at start, with Skip; How to play has Watch the intro', (t) async {
    await launch(t, stored: {'introAtStart': true, 'guideSeen': true});
    await t.pump();
    expect(_key('intro'), findsOneWidget);
    expect(_key('introSkip'), findsOneWidget);
    IntroScreen.stop(); // what opening a room or a notification does (S10-2 AC4)
    await secs(t, .8);
    expect(_key('intro'), findsNothing);
    await tapKey(t, 'howToPlay');
    await t.pumpAndSettle();
    await t.tap(_key('guideIntro'));
    await secs(t, .5);
    expect(_key('intro'), findsOneWidget);
  });

  testWidgets('Arabic captions and the Arabic HA; reduced motion still tells the story', (t) async {
    await launch(t, lang: 'ar', stored: {'introAtStart': true});
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await secs(t, .8);
    expect(_cap(t), 'بلدة هادئة. الجميع يعرف الجميع.');
    for (var i = 0; i < 5; i++) { await t.tap(_key('intro')); await t.pump(); }
    await secs(t, 2.0);
    expect(find.text('ها'), findsNWidgets(3));
    expect(t.takeException(), isNull);
  });
}
