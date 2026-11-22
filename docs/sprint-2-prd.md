# Sprint 2 PRD: the app exists, and one phone can run a whole game

Status: **signed off and built 2026-11-22** (results: `docs/sprint-2-report.md`). Not committed.

## Audit
- **New repo:** no app code. The rules exist only in TypeScript; the 60 shared test games
  (`packages/engine/fixtures/records.json`) are ready for a Dart copy to prove itself against.
- **Laptop:** no Java, Flutter or Android SDK. Reachable from here today: Flutter's downloads (current stable
  3.50.1, released 2026-11-20), pub.dev, Google's Android repository and Maven, Gradle. Disk: **29 GB free** (88% used);
  the tools need about 6–8 GB.
- **The old app's single-phone game** (the player reference), in `../mafia-dealer/app/src`:
  - **setup:** 4–20 names with recent-name chips; role counts within the limits; rules with Classic / Beginner presets;
    night timer;
  - **deal:** pass the phone; each player press-and-holds to see their role; Mafia see their teammates;
  - **night:** the phone goes round; each player picks secretly; Citizens tap a decoy;
  - **morning, verdict, winner:** shown with a suspense reveal (a waiting screen until the narrator says the name),
    vibration and sounds;
  - **day:** discussion timer;
  - **vote:** two ways: the table decides together, or a secret ballot passed round;
  - **after the game:** a recap, the MVP, Play again (same names, new roles), resuming a game after the app closed,
    "are you sure?" before leaving.
  - **voice and sound:** an 84-clip pre-recorded English narrator (about 850 KB), including spoken names for known
    friends' names. The sound effects are synthesized in code (Web Audio oscillators), not files.
  - **fonts:** OFL-licensed (Readex Pro, IBM Plex Sans Arabic, El Messiri, Special Elite), with about 630 UI strings in
    English and Arabic.
- **Gaps for Play:** no Android build, no Android signing yet (Sprint 6), and the target API level Google Play requires
  for new apps (API 36 from August 2026; to be checked at upload time). The screen also sleeps during long
  discussions: the old app doesn't keep it on.

## Scope

### S2-1 The tools on this laptop
Downloads (your sign-off is the permission for them):
- **Flutter SDK:** a pinned stable release that's at least two weeks old. Today that's **3.47.9** (2026-10-29,
  Dart 3.13.7), not 3.50.1 (2 days old). Source: storage.googleapis.com, about 1.2 GB.
- **JDK 21:** Eclipse Temurin from github.com/adoptium, about 200 MB.
- **Android command-line tools, platform and build-tools:** from dl.google.com, about 0.5 GB.

They go in `C:\Users\WGN\sdk\` (outside the repo, next to nothing else) and are added to your user PATH only (no
system settings). There's no emulator on the laptop: it needs Windows' hypervisor setting, which is yours to change.
Emulator tests run in CI instead.
- AC1: `flutter doctor` shows the Android toolchain without errors.
- AC2: `flutter build apk --debug` works here, and the APK installs on your phone with `adb install` (you plug it in and
  allow USB debugging).

### S2-2 The app shell (`app/`)
- AC1: package `com.mafiadealer.game`; launcher name **"Mafia Dealer"** (the full "Mafia Dealer: Party Game" is for
  the Play listing, since launchers cut long names); minimum Android 7.0 (API 24); targets the API level Play requires.
- AC2: English and Arabic from ARB files, switched in Settings and remembered on the phone. In Arabic the whole layout
  mirrors (right to left), including back arrows and number formats. No UI string is hard-coded.
- AC3: the old app's look ("Noir") and fonts carried over (fonts bundled, licenses included in the app's licenses
  page).
- AC4: phone Back never leaves a running game without asking.

### S2-3 The Dart engine (`packages/engine_dart`, pure Dart, used by the app)
- AC1: the same rules, actions, views, `startRecord` / `step` / `replay` and the same `seeded` random source as the
  TypeScript engine.
- AC2: it replays all 60 shared test games to the **identical** final state and history.
- AC3: its random-game player, run with seeds 1–60, produces records **byte-identical** to the shared file. That proves
  both engines play the same moves the same way, not just that the Dart one accepts the TypeScript results.
- AC4: 1,000 random games with the same checks as the TypeScript test: they always end, the right winner, no role leaks
  before the end, refused actions change nothing. The edited-record tests are ported too.
- AC5: CI runs the Dart and TypeScript engine tests on every push. A rule changed in one copy only fails the build.

### S2-4 Offline play on one phone (no account, nothing logged)
Same flow as the old app's single-phone game, judged by the Dart engine:
- AC1: **Setup:** 4–20 names with the engine's limits and messages (too few, too many, duplicate names, Mafia gap);
  role counts that can't go out of bounds; the rules with presets; the night timer.
- AC2: **Deal:** pass the phone; each player holds to see their role (released = hidden); Mafia see their teammates;
  "Pass to <next name>" between players.
- AC3: **Night:** the phone goes round in seat order; each player sees only their own options (the engine's
  `nightOptions`); Citizens tap a decoy when that rule is on; the night timer skips unfinished turns.
- AC4: **Morning, verdict and winner:** the suspense reveal (a waiting screen until the narrator says the name), the
  old app's voice clips (English only), sounds and vibration. Volume settings for voice and effects.
- AC5: **Day:** the discussion timer (start, pause, +1 minute, reset); the vote either by the table together or by
  secret ballot round the phone; the verdict.
- AC6: **End:** the winner, every role, the recap and the MVP; Play again (same names, new roles); Change players.
  **Nothing is saved to any history.**
- AC7: **Resume:** if the app is killed mid-game, it offers to resume at the same step (the game in progress is kept on
  the phone) or to discard it.
- AC8: the screen stays on during a game.

### S2-5 CI builds the app
- AC1: every push runs `flutter analyze` (no warnings), the widget tests and the engine tests.
- AC2: every push builds a debug APK, downloadable from the run (for your playtests).
- AC3: an Android emulator in CI plays a full offline game end to end through the real UI, and runs the
  kill-and-resume test.

## How QA will test
- Widget tests at three phone sizes (360×640, 393×851, 412×915) in English and Arabic and at 1.3× text size: no
  overflow, nothing cut off, the right layout direction.
- The emulator test in CI (S2-5 AC3): a whole game, plus Back during the game, plus killing the app and resuming.
- Adversarial: fast double taps on every game button (nothing happens twice), rotating mid-night, holding the role
  card while the app goes to the background (it must hide), the timer through pause and resume.
- A release report with a debug APK for your manual playtest on your phone.

## Not in Sprint 2
Accounts and sign-in, friends, online rooms, Wi-Fi, any history or stats, Play signing and listing, push. Saved names
in D1 come with accounts.

## Decisions needed
1. **Names chips offline:** with no account, should the phone remember recent names on the device (convenient, but
   decision 2 says such data belongs in D1), or should there be no chips until sign-in? Recommended: remember recent
   names on the phone for players who aren't signed in, and use D1 once signed in.
2. **Look:** carry over the old "Noir" look (recommended), or a new design first?
3. **Narrator name clips:** keep the spoken friends' names (Alhassan, Sami, Dareer, …) in the public Play app? Those
   names ship inside the app for anyone to find. Recommended: keep them, unless your friends mind.
4. **Tools location:** `C:\Users\WGN\sdk\` (recommended), or somewhere else?
5. **G7** (still open from Sprint 1): the dead Detective's last result, and a Mafia "skip" tie broken at random. The
   Dart port copies the rules either way; deciding now saves porting twice.
