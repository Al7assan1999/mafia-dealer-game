# Sprint 8 Release Report: stats, titles and profiles; your old history; new builds inside the app

2026-11-23. Built against `docs/sprint-8-prd.md`, signed off with these answers:
- my games + an Everyone leaderboard;
- the old-player list later;
- updates that feel automatic, plus a push;
- all four [BA] proposals;
- the emulator here.

Run as the three personas. Committed together with Sprint 7.

## [Developer] What changed, per AC
- **S8-1 Stats (server `stats.ts`, app `stats.dart`):**
  - the old app's rules ported 1:1: the five titles, the leaderboard by win rate with a minimum, ties by wins then games, the Mafia / Citizen split;
  - **Mine** = my online + approved Wi-Fi + my old games, 3-game minimum;
  - **Everyone** = all accounts, online + approved Wi-Fi only (old games are self-reported), 10-game minimum, top 100 + your own row, opted-in accounts, never banned;
  - valid games only, worked out on the server, so a game the host makes invalid leaves everyone's stats;
  - filters: All / Online / Wi-Fi / Old app (Mine), All time / Last 30 days (P1);
  - equal records share a rank.
- **S8-2 Profile:**
  - the old app's profile: win rate, best role, as Mafia, Citizens' side, killed most by, wins by role, moments, last 8 games;
  - plus **best partner** (P2) and **Share**, a picture of the card (P3);
  - opened from a board row, a player in a game's detail page, a friend, or Profile → My stats.
- **S8-3 Old history (`legacy.ts`):**
  - Profile → Import old history: the code from the old app's own Group history, read once from the old relay, server to server;
  - the old app and relay are untouched;
  - only games whose every name is on the real-player list (a D1 settings row, **empty until you send the names**);
  - duplicates skipped, broken entries counted, the raw game kept with its format;
  - "Which one were you?" claims a name;
  - the list can tie other names to accounts later;
  - History → **Old app** tab with the old lines on the detail page.
  - Migration `0007` (+ rollback) only adds.
- **S8-4 Updates (`update.dart`, `Updates.kt`, `release.yml`):**
  - Actions → **Release**, run when you ask, with the bullets: a release APK signed with the upload key, published as a GitHub Release, then a push in English / Arabic to every phone (topics `updates_en` / `updates_ar`);
  - the app checks on start and on return (every 10 min at most): "Update available · What's new" on Home → **Update** downloads with progress → Android's PackageInstaller;
    - the first time, Android asks to allow installs and to confirm;
    - after that, **Android 12+ updates without a prompt**;
    - "Mafia Dealer updated · tap to open" brings you back, and "Updated to vX" shows once with the bullets;
    - any failure opens the download page;
  - Settings: New version alerts, Check for updates, version and build;
  - the lobby marks players on an older build (online and Wi-Fi);
  - `SELF_UPDATE=false` switches it all off for the future Play build.
- **P4 titles:**
  - when an Everyone title changes hands, the one who lost it gets a bell note and a push on the new **Titles** channel: "Dareer took Best Detective from you";
  - recomputed after every online game, a Wi-Fi approval, a valid / invalid change and the leaderboard switch.
- **S8-5:** "1 round / 2 rounds" (Arabic: جولة واحدة / جولتان / 3–10 جولات / 11+ جولة); the MVP on a game's detail page.
- **Also:** `pubspec` version 0.2.0; CI debug builds carry their build number (so they're offered the first release).

## [QA] Results
- **Server:** 64/64 (55 earlier + 9 new):
  - every title's rule and tie;
  - the profile math;
  - Mine vs Everyone;
  - the 10-game minimum;
  - the switch handing the title to the next player;
  - banned accounts hidden;
  - invalid games leaving;
  - filters;
  - title notes, read and dismiss;
  - the import: no list = nothing kept, test names skipped, duplicates, a second importer, broken entries, unknown code, old server down, the rate limit, claims, names tied through the list, old games never on Everyone.
- **App:** analyzer clean. **96/96 widget tests** (80 earlier + 16 new):
  - Stats and its filters;
  - Everyone with your rank;
  - empty state;
  - profile;
  - Arabic;
  - import results and errors;
  - "Which one were you?";
  - the Old app tab;
  - the switch;
  - the title note;
  - the plurals;
  - the updater: card, download with progress, allow installs, failure fallback, the push topics by language.
- **Engines:** unchanged (35 TypeScript + 6 Dart groups).
- **Emulator, here** (Pixel 6, Android 14, a local Worker with 5 seeded accounts and 14 games): see the exploratory session below. The full emulator suite (account, chat, online, Wi-Fi, Wi-Fi approval) runs on CI with the push of this sprint.

## [QA] Exploratory session on the emulator (driven by hand, like a tester)
1. Install, open:
   - **the splash was white** before the black app (#9);
   - Home signed out shows History but not Stats (correct).
2. Sign in by email code: the numeric keyboard comes up for the code, and you land on Profile with My stats, Import and the Everyone switch.
3. My stats: every number checks against the seeded games. **"Best partner: No Mafia wins yet" next to "As Mafia 2/3 wins"** (#2).
4. Stats (Mine):
   - titles and board right, you highlighted;
   - **"Caught the Mafia 1 times"** (#3);
   - **the period filters off-screen** (#4);
   - **four identical records ranked 1, 2, 3, 4** (#5).
5. Everyone: the Old app filter disappears, "You: #1", the 10-game rule explained.
6. Settings:
   - the new rows are there;
   - **the Notifications line still listed 3 kinds** (#6);
   - **Check for updates gave no visible answer** (its message hid behind the sheet) (#7).
7. Arabic: everything mirrors, the split reads in Arabic, the plural bug shows in Arabic too.
8. Airplane mode → Stats: a clear "no connection" message, **but no Retry** (#8).
9. After the fixes, re-installed: dark splash, two filter rows, the Arabic plurals, the tied players all at rank 1.

## [QA] → [Developer]: what QA found, and the fixes
| # | Found by | Finding | Fix |
| --- | --- | --- | --- |
| 1 | Widget test | Title tiles in a fixed-ratio grid overflowed by 3 px (worse with large text) | Rows of two that size to their content |
| 2 | Emulator | "Best partner: No Mafia wins yet" contradicted "As Mafia 2/3 wins" (the partner needs a fellow Mafia) | "No Mafia partner yet" |
| 3 | Emulator | "1 times", "1 saves" (EN and AR) | Plural forms in both languages (Arabic 1 / 2 / 3–10 / 11+) |
| 4 | Emulator | "All time / Last 30 days" scrolled off-screen | Two rows that wrap |
| 5 | Emulator ([BA] too) | Identical records numbered 1-2-3-4 at random | Equal records share a rank (server) |
| 6 | Emulator | Settings → Notifications named 3 kinds; there are 5 | Names all five |
| 7 | Emulator | "Check for updates" answered in a toast hidden behind the sheet | The answer shows under the row |
| 8 | Emulator | Offline Stats had no way to retry | "Try again" button |
| 9 | Emulator | White launch splash before a black app | Noir background for the launch screen (and Android 12's splash) |
| 10 | Server tests | Two of my own test expectations were wrong (a hand count, a rate-limit count, a tie I misread) | Tests fixed; the code was right |

## [BA] Acceptance review
| AC | Verdict | Evidence |
| --- | --- | --- |
| S8-1 AC1 Stats from Home and History | ✅ | Emulator: Home → Stats; History's top bar |
| S8-1 AC2 the five titles, the old rules | ✅ | Server rule tests; emulator screenshots |
| S8-1 AC3 board, minimum, split, you highlighted | ✅ | Emulator EN/AR |
| S8-1 AC4 what counts, said on screen | ✅ | The line under the board, both boards |
| S8-1 AC5 server-side, invalid games leave | ✅ | Server test |
| S8-1 AC6 Everyone (fairness + privacy) | ✅ | Server tests: 10 games, opted out, banned, old games excluded; emulator |
| S8-2 AC1–AC3 profile from every place, account card, My stats | ✅ | Emulator; widget tests |
| S8-3 AC1–AC7 import | ✅ (needs your names) | Server + widget tests. **Imports keep nothing until you send the player list.** |
| S8-4 AC1 a release only when you ask | ✅ (not run yet) | `release.yml`; first run when you ask |
| S8-4 AC2–AC4 check, card, in-app download, "Updated to vX" | ✅ (logic) | Widget tests with a fake GitHub and installer. **The real install is only provable on your phone.** |
| S8-4 AC5 push for new versions | ✅ (not sent yet) | Topics by language; the release workflow sends it |
| S8-4 AC6 old-version tag in the lobby | ✅ | Online and Wi-Fi rooms carry the build; shown when lower than mine |
| S8-4 AC7 off for Play | ✅ | `SELF_UPDATE=false`; the permission must leave the Play manifest (noted for the Play sprint) |
| S8-5 plural, detail MVP | ✅ | Widget test (plurals); MVP on the detail page |
| P1–P4 | ✅ | Filters, best partner, Share card, title notes |

**[BA] notes for the next audit:**
- Stats and History are small text links at the bottom of Home. They'll matter more now; the Sprint 9 Home work (drawer, minimize) should give them a proper place.
- A tie at the top shows several "1"s, and the Best player title still goes to one of them (the old app's rule). Fine for now; a "shared title" could come later.
- The local test build has Google sign-in off (no client ID locally); CI builds have it.

## Caveats for your playtest (what only your phone proves)
1. **Run the first Release** (Actions → Release, bullets separated by ";"), install that APK once by hand, then run a second Release:
   - the phone should get the push;
   - Update should download inside the app;
   - on Android 12+, install **without a prompt** the second time;
   - "Mafia Dealer updated" brings you back, with "Updated to vX".
2. **Your old history:**
   - send me the real player names, and who is who;
   - then old app → Settings → Group history → Create group;
   - new app → Profile → Import old history → enter the code;
   - then pick your name.
3. **A title note:** when someone passes you on the Everyone board, the bell and a push.
4. **Share** a profile card to WhatsApp.
