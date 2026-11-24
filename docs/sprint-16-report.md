# Sprint 16 Report: the Sprint 15 [BA] proposals

2026-11-24. Built against `docs/sprint-16-prd.md`. **Not committed, not released.** Version in `pubspec.yaml`: 0.4.12.
Emulator shots: `docs/qa/journey16/` (k01-k05).

## Rollback
Each proposal is its own change, to be committed as its own commit, so one can be undone without the others:
`git revert <that commit>`, then a release. The table gets the commit ids when they're committed.

| # | Change | Files |
| --- | --- | --- |
| S16-1 | Side tabs clear of the lobby's controls | `room_lobby.dart` |
| S16-2 | Wi-Fi "Your name" card and tip | `wifi_screen.dart`, ARB (`wifiNameTip`) |
| S16-3 | How to Play: the game options | `guide_screen.dart`, ARB (`gOptions`) |
| S16-4 | Done after signing in | `profile_screen.dart`, `sign_in_screen.dart`, ARB (`aDone`) |
| S16-5 | Readable role colours on the paper recap | `recap_card.dart` |

Each one's test is in its own file (`test/s16_*_test.dart`; S16-4's in `account_test.dart`) and in the same commit,
so a revert takes its test out with it. Checked before committing: each of the five reverses cleanly on top of all the
others, and the app still analyzes clean with any one of them reverted.

## [Developer] What changed
- **S16-1** The player list and the role and rule cards in a lobby keep 24 dp clear on the tabs' side. The tabs are 36 dp
  and can be dragged to any height, so the whole area they can reach stays clear, not one row. The room-code card
  above (which the tabs can't reach) keeps its full width.
- **S16-2** The Wi-Fi name sits in a "Your name" card. A guest sees "Tip: sign in and your name fills in by itself."
  Signed in, the account's name is already filled in, so no tip.
- **S16-3** How to Play shows the setup's own rules card, read only, under one line ("The options you can turn on when
  you set up a game"). A tap lists every option with its explanation. It's the same card as the setup screen, so the
  guide can't fall out of date when an option changes. Nothing can be changed from the guide.
- **S16-4** Straight after signing in (or choosing a @username) the profile has **Done** at the bottom; it goes back to
  where sign-in started. Opened from Home, the profile is as before.
- **S16-5** On Noir's paper recap every role uses a darker ink: Mafia `#9E2C25`, Doctor `#28613A`, Detective
  `#315A84`, Citizen `#6F5015`. They read at 4.8:1 or more (they were 1.9-2.9:1). Neon is unchanged.

## [QA] How it was tested
| Check | Result |
| --- | --- |
| App tests | **179 / 179** (5 new + the sign-up test extended) |
| Server tests | 73 / 73 at 0.4.11; no server change since |
| Analyzer | clean |
| Emulator | each of the five on a profile build (below) |

| Item | Test | Emulator |
| --- | --- | --- |
| S16-1 | every ⋮ menu and the Mafia + end before the tab's edge (failed on the old lobby: 361 > 353) | menus end at x 933, the tab starts at 975 (k02) |
| S16-2 | guest: card and tip; signed in: name filled, no tip | guest: card and tip (k04) |
| S16-3 | Classic shown; a tap lists the options; every switch is read only | listed, switches greyed out (k01) |
| S16-4 | sign-up → Done → Home; the profile from Home has no Done | email sign-in → Done → Home; no Done from Home (k05) |
| S16-5 | computes every ink's contrast on the paper and on the player-of-the-game box (≥ 4.5:1) | dark, readable roles (k03) |

### [QA] Break attempts
- **S16-1:** the tab can be dragged anywhere, so the test checks the horizontal edge, not one position.
- **S16-3:** tapped a switch in the guide's card: nothing changes (read only).
- **S16-4:** opened the profile from Home after the sign-in: no Done there.
- **S16-5:** the player-of-the-game box is darker than the paper; checked against both.

### [QA] What only a human playtest can show
- **S16-1** The lobby's right margin is now wider than its left (24 dp more). It reads fine on the emulator; on a small
  phone it's worth a look.
- **S16-3** The read-only switches are greyed out; a player might read "off" for an option that's on. Classic's
  on/off states are still visible, but by shade only.

## [BA] Acceptance review
| Item | Verdict |
| --- | --- |
| S16-1 side tabs | ✅ test + emulator |
| S16-2 Wi-Fi name card | ✅ tests + emulator (guest) |
| S16-3 guide options | ✅ test + emulator |
| S16-4 Done | ✅ test + emulator |
| S16-5 paper colours | ✅ test (contrast) + emulator |

**Found by the BA alone:** the Doctor's green was the one named, but every Noir role colour failed on the paper (Mafia
2.9, Detective 1.9, Citizen 2.5); all four were fixed in the same change.

## Challenge log
- **BA against the proposal (its own):** P5 named only the Doctor. Measuring all four showed every role failing; the
  scope grew to all four, still one change.
- **Dev against BA:** P3 asked for the old "Options in this app" text. Dev proposed the setup's own card instead of new
  text (no copy to keep in step); BA accepted.
- **QA against Dev:** P1's first idea was to pad only the ⋮ menus; the Mafia stepper is under the same tab when it's
  dragged down. The whole tab area stays clear instead.
- **QA against QA:** S16-3's greyed switches may read as "off"; written down for the playtest instead of being
  called a pass.

## Before release (his call)
Nothing to run on the database. Commit as six commits (the five above, then the docs and version), push, CI,
release 0.4.12.
