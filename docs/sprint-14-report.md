# Sprint 14 Report: the old app's look, everywhere

2026-11-24. Built against `docs/sprint-14-prd.md` (his six points after 0.4.6). **Not committed, not released.**
Old-app reference shots: `docs/qa/old-look/` (Noir), `docs/qa/old-look-neon/` (Neon). New shots: `docs/qa/demo14/`.

## [Developer] What changed
- **S14-1 Chat by the drawer (his #1).** A side tab (`ChatTab`) under the friends tab, in the lobby and in the game,
  online and Wi-Fi. Gone from the top bar. In a game the friends tab stays hidden (S9-2) and the chat tab alone sits
  at the drawer's height, under the screen's header.
- **S14-2 The Home icon (his #2)** stays in the room's top bar.
- **S14-3 Home as the old app (his #3).**
  - Top row: a round avatar (or a person icon: sign in), the bell box; the flag, look and Settings boxes. Friends are
    in the side drawer, as in the old app; the drawer's + opens the full Friends screen.
  - The old hat-and-moustache mark (tilted red square in Noir, gradient tile with a glow in Neon).
  - Under Online: Game History (with the game count), Player Stats, How to Play.
  - "Best player: X · 83%" from the one board (signed in; kept between starts). [BA P2] a tap opens Player Stats.
  - The version row.
  - [BA] "Resume game · Round N" as the old gold button with a Discard link (it was a card).
- **S14-4 What's new as the old app.**
  - The Release workflow now stores the last 10 releases with the latest one on the server.
  - What's new lists them: version, date ("20 Nov 2026"), points, Available / Installed badges, Update · vX and OK.
  - After an update it opens by itself once (the toast stays for "offline, no list").
  - The update card: "What's new in vX", three points, See all, Update.
- **S14-5 Gentle transitions (his #4).** Every page fades in and slides up 4 % (280 ms; 220 ms back). With Android's
  "Remove animations" on, pages appear at once ([BA P3]).
- **S14-6 Game screens in the old central card.**
  - Every offline and online game screen: the content and its buttons in one card.
  - A boxed tag ("Card 1 of 6", "Night 1", "Morning of Day 1") and the big icon in a box.
  - "PASS THE PHONE TO" in small caps, and "Round 1 · 6/6 alive" under offline screens.
  - The role card as the old one: wide, paper, icon box, the role's colour, a "CLASSIFIED" stamp. The large-text case
    shrinks the content instead of cutting it.
- **S14-7 Neon in every detail (his #6).**
  - The old CSS backdrops: a violet gradient with a pink glow top-left and a blue glow top-right; night, day, blood
    and glory glows from the top centre.
  - 22 px corners, round − / + steppers, the gradient logo tile, the gold Resume button with dark text.
- **Settings**: the old Account section on top (sign in / create account, or your profile).
- **Structure**: the old-look widgets moved to `lib/core/look.dart` (re-exported by `ui.dart`; both under 500 lines).

## [QA] How it was tested
| Check | Result |
| --- | --- |
| App tests | **161 / 161** (`test/sprint14_test.dart` adds 8) |
| Server tests | **73 / 73** |
| Analyzer, architecture test, click map | clean, clean, 25 / 25 |
| Emulator (Noir and Neon) | Home, Resume, setup, deal, role card hidden and shown, Settings, What's new (real GitHub releases) |

Break attempts in `sprint14_test.dart`: the chat tab in the lobby *and* the game, never inside the app bar, the Home
icon still there; Home's tiles, no friends button, the best player line and its tap; a guest (no best player, flag and
look boxes switch); the release list from the check, from the server alone, from GitHub; What's new with two releases
and an available update; What's new with nothing anywhere (a toast, no empty dialog); a page half-faded mid-transition;
the round line under a game screen.

### [QA] Found and fixed during the sprint
1. **Noir's backdrop base colour was never painted** (a gradient hides a box's colour): pages were plain black, and
   the night / day / blood screens lost their colour. Now the glow fades into the base colour.
2. **Buttons lost the app font** (my S13 button themes set a text style without the font): dialog buttons were
   Android's font. Fixed for all four button types.
3. Bold buttons pushed the sign-in row off a narrow phone: it wraps now.
4. The large-text role card overflowed by 13 px: it shrinks to fit, lines still wrap.
5. How to Play marked the guide as seen while the page was being built (an exception): it does so on the tap.

### [QA] What the tests can't prove
- **His phone.** The emulator is a Pixel image; his phone has "Bold text" on (handled since 0.4.5) and may draw
  flags and fonts differently.
- **Arabic.** Widget tests run Arabic; no Arabic emulator pass this sprint.
- **The release history on the server** fills at the next release (the workflow step uses `jq`, present on GitHub's
  runners; not run locally).
- **The online game screens** were checked in renders, not with two phones.
- Not matched yet: the old dashed borders (Flutter has none built in), the end screen's paper "case file" recap,
  "Round · alive" on online screens.

## [BA] Acceptance review
| Item | Verdict |
| --- | --- |
| S14-1 chat by the drawer | ✅ test + render |
| S14-2 Home icon in the room | ✅ test |
| S14-3 Home as the old app | ✅ test + emulator (Noir and Neon) |
| S14-4 What's new | ✅ tests + emulator with real releases; the server half proves itself at the next release |
| S14-5 transitions | ✅ test (half-faded mid-way) |
| S14-6 game card | ✅ for offline and online; ⚠️ the end screen keeps its own cards, not the old paper recap |
| S14-7 Neon | ✅ Home, Settings, night pick; ⚠️ no Neon pass of every screen on the emulator |
| P1 pending approvals on the History tile | deferred (needs a server count) |

### [BA] Challenge log
- **BA against Dev:** the first Home kept the "unfinished game" card; the old app has a gold button. Sent back, fixed.
- **QA against Dev:** "Noir looks right" passed every widget test, but the backdrop's base colour was never painted;
  only a render with a light test background showed it.
- **QA against QA:** a stale render file (an older run's name) looked like a regression; renders are now checked by
  their timestamps.
- **Dev against BA:** "Player Stats" for a guest has no data (the board is online). It opens sign-in instead of an
  empty screen.

## Before release (his call)
Nothing to run on the database. Version 0.4.7, then commit → push → CI → release.
