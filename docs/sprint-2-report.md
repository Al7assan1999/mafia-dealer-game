# Sprint 2 Release Report: the app exists, and one phone can run a whole game

2026-11-22. Built against `docs/sprint-2-prd.md` (signed off the same day with the recommended answers). **Not
committed, not pushed, so the two new CI jobs have not run yet.**

## Result: green locally
- **Dart engine:** 5/5 test groups: the 60 shared games replay; the same seeds give **byte-identical** records to the
  TypeScript engine; 1,000 random games; edited records refused; setup limits. `dart analyze --fatal-infos`: clean.
- **TypeScript engine:** 34/34 (unchanged).
- **App:** `flutter analyze`: no issues. **20/20 widget tests**: 12 whole games (3 phone sizes × English / Arabic × text
  1.0 / 1.3), a whole game with every button tapped twice, setup limits, double taps, the role card in the
  background, Back + a cold start + resume, the discussion timer, the night timer, the language switch.
- **Debug APK:** builds here. `com.mafiadealer.game`, label "Mafia Dealer", minSdk 24, targetSdk 36. It's 161 MB
  because debug builds carry every CPU type and the debug runtime; a release build is much smaller (Sprint 6).
  `app/build/app/outputs/flutter-apk/app-debug.apk`

## Bugs QA found and fixed
1. **A second quick tap on "Confirm decision" or "Cast my vote" crashed the app.** The first tap cleared the choice,
   and the second ran before the screen rebuilt. Found by the double-tap game test, fixed, and pinned by it.
2. **With 4 players, the Mafia +/- buttons vanished** instead of showing as disabled (found by the setup test).
4. **Found by the emulator job on the first CI run (330bdb0):** leaving a finished game told the home screen to
   rebuild while Flutter was closing the game screen, which Flutter forbids. Debug builds show it as an error; release
   builds would hide it. Fixed by sending the notification a moment later. The widget tests don't reproduce it (I
   checked with the fix switched off), so the emulator job is the check. The emulator test also now stops the
   narrator and lets the last sounds finish before it ends (the audio player was still running).
3. The rule switches drew on a plain colored box that hid their tap ripple (a Flutter warning in the tests). The
   section cards are now proper Material surfaces.

## Against the acceptance criteria

| AC | Status | Evidence / notes |
| --- | --- | --- |
| S2-1 AC1 `flutter doctor` | ✅ | No issues. Installed in `C:\Users\WGN\sdk\`: Flutter 3.47.9, Temurin JDK 21.0.13.1, Android SDK (platform 36, build-tools 36.1.0, platform-tools) and **NDK 28.2** (Gradle required it: about 0.7 GB more than planned). Checksums verified. The Android licenses were accepted with your OK. Your user PATH, `JAVA_HOME` and `ANDROID_HOME` were set; no system settings changed. Flutter's analytics were turned off. The zips were deleted afterwards. |
| S2-1 AC2 APK on your phone | ⏳ half | The debug APK builds here. **Installing it needs your phone plugged in with USB debugging on** (no device was connected). |
| S2-2 AC1 package, name, SDK | ✅ | Checked inside the APK (aapt2): see above. |
| S2-2 AC2 EN / AR, RTL, no hard-coded text | ✅ | All strings in `app_en.arb` / `app_ar.arb` (taken from the old app's translations). The tests check the layout direction for Arabic and that the choice is remembered. |
| S2-2 AC3 Noir look + fonts | ✅ | The old Noir colors, typewriter headings, hard shadows. The fonts are bundled as TTF from the Google Fonts repository (the old app only had web fonts); their license files sit next to them. ⚠ The fonts aren't on the app's in-app licenses page yet (Sprint 6, with the rest of Play readiness). |
| S2-2 AC4 Back asks | ✅ | Tested: Back → "Leave this game?"; Cancel stays; Leave keeps the game for Resume. |
| S2-3 AC1–AC4 Dart engine | ✅ | See above. The engine is written so JSON keys, number formatting and JavaScript's key order and stable sorts match exactly. |
| S2-3 AC5 CI fails on drift | ✅ written, ⏳ not run | The CI `app` job runs the Dart engine tests against `packages/engine/fixtures/records.json`. |
| S2-4 AC1 setup | ✅ | Limits and messages come from the engine; Deal is disabled while there's an error. |
| S2-4 AC2 deal | ✅ | Hold to see, release to hide; "Got it" stays disabled until the card has been looked at; Mafia see teammates. |
| S2-4 AC3 night | ✅ | Seat order; only the player's own options; decoys; the Detective's result after confirming; night timer tested. |
| S2-4 AC4 suspense, voice, sounds, vibration | ✅ (silent in tests) | The old recipes: the reveal fires when the narrator reaches the name, with the old fallback timers, plus "Reveal now". 84 voice clips extracted. **The 11 sound effects were rendered from the old app's own Web Audio code** (headless Edge) to WAV, so they sound the same, frozen as one take each (the old ones varied slightly every time). ⚠ The real audio has only been checked as files (levels, no clipping). Hearing it on a phone is for your playtest. |
| S2-4 AC5 day | ✅ | Timer start / pause / +1 min / reset / "time is up" tested; table decision and secret ballot both used in the game tests. |
| S2-4 AC6 end, nothing saved | ✅ | Winner, roles, MVP, history, Play again, Change players. A finished game is removed from the phone. |
| S2-4 AC7 resume after a kill | ✅ | The phone keeps the game as its engine record plus the step; a fresh start replays it to the same step and player (tested). |
| S2-4 AC8 screen stays on | ✅ written | Wake lock during the game screen. Only checkable on a phone. |
| S2-5 AC1 CI analyze + tests | ✅ written, ⏳ not run | Job `app`. |
| S2-5 AC2 APK artifact | ✅ written, ⏳ not run | Uploaded by the `app` job (kept 14 days). |
| S2-5 AC3 emulator game + resume | ✅ written, ⏳ not run | Job `emulator` (Android 14 emulator): a whole game with real audio and storage, then Back and a cold start from the saved data. ⚠ "Kill" there means rebuilding the app from what's stored on the device, not killing the Android process. |

## Decisions I made while building (tell me if you want them different)
- **Portrait only.** Rotation is locked, so "rotating mid-night" can't break anything.
- **Empty name fields become "Player N",** which the narrator can say.
- **The role card's "Got it" waits for one look,** so nobody can skip their role by accident.
- **The brand name stays "Mafia Dealer" in Arabic too.**

## Caveats for your playtest
1. **Install:** plug in your phone with USB debugging on, then I run `adb install`. Or download the APK from the
   first CI run after a push.
2. **Listen to the narrator and the sounds:** volume, timing of the reveals, and the name clips.
3. **Try the screen-on behavior and leaving / resuming,** with real taps and the phone's Back gesture.
4. The launcher icon is still Flutter's default; the real icon comes with Play readiness.
