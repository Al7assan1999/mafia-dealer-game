# Sprint 17 Release Report: 1.0.0, new roles as modes

2026-11-25. PRD: `docs/sprint-17-prd.md` (signed off). Rulings: `docs/decisions.md`. **Nothing committed, pushed or
released.**

> **Update after his answer to Q4 ("require 1.0.0"):** every table, Classic included, now waits until every seated
> phone is on 1.0.0 (server, Wi-Fi host, lobby). Local, test and CI builds report themselves as 1.0.0. The test
> helpers' phones and the QA bots report 1.0.0 (`BOT_BUILD` plays an older phone). Re-run: TS engine 52, Dart 9,
> server 77, app 194, click map 25, analyzers clean. The emulator's "Classic with old bots" run below was before this
> ruling: that table is now refused. `app/integration_test` (CI's emulator job) was updated but not run locally.
> After the Godfather-on-reveal ruling: TS engine 53, Dart 9, server 77, app 195, click map 25.

## What a player gets
- **Modes, one tap:** Classic (4+), Sniper (6+), Jester (6+), All roles (9+), in the offline setup and in the online and
  Wi-Fi lobby. A mode that needs more players shows "From N players"; the best one for the table is marked
  Suggested. Outside Classic the roles are set by the player count.
- **شيخ المافيا / the Godfather in every game:** one of the Mafia. His pick settles any tied Mafia vote. Once he is out
  (or if he didn't vote), the lowest seat that voted decides. A tie never means nobody dies. The Detective always reads
  him "not Mafia".
- **القنّاص / the Sniper:** one bullet a game; nothing stops it, not even the Doctor. **الجوكر / the Jester:** wins
  alone if voted out by day.
- Each role card shows the role's side and how it wins. How to Play has every role and a Modes section. 1.0.0.

## Test results (final run)
| Suite | Result |
|---|---|
| TS engine (`packages/engine`) | 52 pass (was 33) |
| Dart engine (`dart analyze --fatal-infos`, `dart test`) | clean, 9 pass: byte-identical records, 1,000 random games over every mode |
| Server (`vitest`) | 77 pass (was 73) |
| App (`flutter analyze`, `flutter test`) | clean, 194 pass (was 179) |
| Click map | 25 pass |
| Emulator (qa34, profile build 100017, local Worker) | see below |

New tests, one file per area: `packages/engine/test/roles.test.ts`, `server/test/sprint17.test.ts`,
`app/test/s17_modes_test.dart`, `s17_roles_ui_test.dart`, `s17_wifi_modes_test.dart`. New shared games:
`fixtures/records-roles.json` (scripted, both engines). The 0.4 games are kept as `fixtures/records-before-sheikh.json`
and still replay.

## Emulator pass (real app, `docs/qa/s17/`)
- **Offline Sniper game, 6 players** (`e02`–`e09`).
  - The setup shows Suggested on Sniper, and the deck is fixed by the mode.
  - The Godfather's card names him; his teammate's card says "Your Godfather: Player 1".
  - The Sniper's night shows "Take your shot?" and "Keep the bullet". The Mafia see "Godfather's pick" and "A tie goes
    to the Godfather's pick."
  - **His rule held on a real three-way tie:** each Mafia picked a different player and the Godfather's pick died.
  - The Sniper shot the Godfather, whom the Doctor had protected: he died.
  - The morning said "Last night, these players died" and named both in seat order. The recap showed "Godfather",
    "Sniper" and "the Sniper shot Player 1".
- **Online, 1 host + 5 scripted players with no app build** (stand-ins for old phones, `e10`, `e11`).
  - In Sniper mode every bot was tagged "needs 1.0.0", the warning showed, and Deal did nothing.
  - In Classic the same table dealt and played a night and a morning.
- **Arabic** (`e12`): the mode card is right to left, with مقترح and "من 9 لاعبين". The saved mode came back.
- **Tried for real:**
  - the migration on the local Worker's existing data: 18 games, 86 player rows, 2 Wi-Fi links, no orphans, no
    foreign-key errors;
  - the online room against the local Worker.
- **Only against fakes:** the Wi-Fi host (unit tests on `LocalRoom`). A real 0.4 APK at a Classic table was not tried:
  installing the 0.4.12 APK on the emulator needs your OK to download it.

## [BA] acceptance review
| AC | Verdict | Evidence |
|---|---|---|
| S17-1 Mode card, one tap, 3 setups, EN/AR | accepted | s17_modes ×4 (EN + AR), s17_wifi_modes, `e03`/`e12` |
| S17-1 "from N players" | accepted | s17_modes "All roles needs 9"; `e03` |
| S17-1 summary names the mode | accepted | s17_modes lobby; sprint5 test updated: the summary now names the mode, not the rules preset (as the AC says) |
| S17-1 mode saved; old setup opens as Classic | accepted | s17_modes ×2; `e12` (mode kept) |
| S17-2 Classic + Godfather, old games replay | accepted | record.test / engine_test "before 1.0.0" |
| S17-8 his examples, skip, no successor, lowest seat, Detective | accepted | roles.test ×9; `e06`–`e08` |
| S17-8 Mafia screen shows his pick | accepted | s17_roles_ui; `e06_night_p5` |
| S17-3 engines in step | accepted | engine_test byte-identical records |
| S17-4 old apps can't land in a mode; unknown role | accepted, with Q4 open | sprint17 server test; s17_wifi_modes; s17_modes "witch"; `e10` |
| S17-5 history/recap/profile/stats | accepted | sprint17 stats test; s17_roles_ui recap; `e09` |
| S17-6 How to Play | accepted | s17_modes guide |
| S17-7 1.0.0 | accepted | `pubspec.yaml` 1.0.0+1. Build number = 100000 + the release run, and the last was 100016 |

**Ben's own finding** (neither David nor Quin raised it): after the Godfather dies, the Mafia's night screen still said
"A tie goes to the Godfather's pick". Fixed: it now says the lowest seat that voted decides. Test: s17_roles_ui
"[Ben] once the Godfather is out".

**[BA] proposal, accepted by him:** with "Roles revealed" on, a dead or voted-out Godfather is now named "Godfather" (it
was "Mafia" in `e08`). Both engines flag it in the revealed result; tests: roles.test, s17_roles_ui, s17_wifi_modes.

## QA ↔ Dev (Quin: 12 findings, 0 blocks; 0 reached you before QA)
| # | Finding | David's answer |
|---|---|---|
| Q1 | A 0.4 phone crashes on the profile of a 1.0 player whose best role is new | **Fixed.** `best` stays one of the four old roles and 1.0 reads `best1` (`stats.ts`, test in sprint17) |
| Q2 | A Mafia (or Sniper) removed mid-night still counted | **Fixed** in both engines: only the living count in 1.0 games. roles.test "[Quin Q2]" |
| Q3 | A Sniper kill of the last Mafia wasn't the death announced | **Fixed:** the deciding Mafia death leads the win. roles.test "[Quin Q3]" |
| Q4 | 0.4 phones play Classic with a Godfather they don't know about | **His ruling: require 1.0.0 everywhere.** Server, Wi-Fi host and lobby; sprint17 + s17_modes + s17_wifi_modes tests |
| Q5 | Release order: the Worker and 0010 must go live before the APK | **Accepted:** in Danial's list |
| Q6 | Debug builds count as "old"; the host's own phone wasn't counted in the lobby | **Fixed** the lobby (counts every phone, as the server does). Debug builds stay "old": QA builds use `--dart-define=BUILD=100017` |
| Q7 | Run 0010 on a copy of production first | **Done with his OK** (Danial, below) |
| Q8 | Arabic two-dead line | **Fixed:** "الليلة الماضية مات كلٌّ من" |
| Q9 | The guide left out "or didn't vote" | **Fixed** (EN/AR) |
| Q10 | The saved player isn't named on a night the Sniper kills | **Deferred** (Ben agrees): it needs "reveal saves" and a Sniper kill on the same night |
| Q11 | Noir role card names below 3:1; locked mode tile looked enabled to TalkBack | **Fixed:** the card uses the recap's paper inks (all roles, as S16-5 did for the recap); the tile is marked disabled |
| Q12 | A role from a later version still breaks 1.0's history, game detail and bell | **Deferred** to the version that adds a role (only the room screen guards today) |

## Challenge log
| Who | Whom | About | Outcome |
|---|---|---|---|
| Alhassan | Ben | "a tie never kills nobody" | Ben's miss, logged in the PRD; the new tie rule replaced the Sprint 7 one |
| Ben | Brad | the re-vote costs a second pass of the phone offline | both recommended the lowest seat; his ruling |
| David | Ben | the D1 CHECKs refuse the new roles and the Jester's win, so Danial's "migrations only add" can't hold | 0010 rebuilds two tables and keeps every row; tested on samples and local QA data; rollback written. Danial flags it below |
| Quin | David | Q1–Q12 | 7 fixed, 2 deferred with Ben, 1 his call, 2 release items |
| Ben | David, Quin | the stale tie note after the Godfather's death | fixed with a test |
| Quin | Ben | no Arabic test of the mode card | added (s17_modes, Arabic) |

## [Danial · Release] go / no-go: **GO once committed, pushed and CI is green**

**Migration 0010 on a copy of production (his OK, 2026-11-25):** exported live D1 (at 0009) into the scratchpad, loaded
it into a separate local database, ran 0010, then the rollback; the export and the copy were deleted afterwards.
- Live has no online or Wi-Fi games yet: `games` and `game_players` are empty. The rebuild has no rows to lose there.
- After 0010: the tables take 'jester' / 'sniper'; 2 accounts, 119 imported old-app games, 3 indexes and the foreign keys
  were untouched (`foreign_key_check` empty).
- After the rollback: the 0.4 CHECKs are back, the test game is gone, and everything else is unchanged.
- Still: take a Time Travel bookmark just before CI applies it.
- CI on the exact commit: not run yet (nothing committed).
- Version 1.0.0; the build number comes from the release run (≥ 100017). `modesBuild = 100017` must not be above it.
- Git email: the GitHub noreply address. No secrets in the diff.
- **Migration 0010 is not add-only:** it rebuilds `games` and `game_players` to widen two CHECKs.
  - It keeps every row, the 0.4 Worker works on the new tables, and it is safe to run before the new Worker.
  - Rollback: `server/rollbacks/0010_new_roles.sql`. It deletes the Sniper and Jester games.
  - **Before release:** export production, run 0010 on the copy locally, compare counts (Q7), and take a Time Travel
    bookmark.
- **Order:** push to main → CI applies 0010 and deploys the Worker → then `release.yml`. A 1.0 phone on the 0.4
  Worker can't change any lobby setting (Q5).
- Cost: no new Durable Object traffic, D1 writes or pushes; one extra field per message.
- Old apps: a 0.4 phone can still open rooms, chat and see history, but isn't dealt in until it updates (his Q4 ruling); its
  profile screens keep working (Q1). Players on 0.4 must update: the in-app update offer handles it.
- Draft release notes for players: "1.0: game modes, pick one with a tap: Classic, Sniper, Jester, All roles; Every game
  has a Godfather who settles a tied Mafia vote; New roles: the Sniper (one bullet) and the Jester (wins if voted out);
  Each role card says your side and how you win; Everyone at the table needs 1.0.0 to be dealt in".

## Your decisions
1. ~~Q4~~: answered, require 1.0.0.
2. ~~Q7~~: done with his OK.
3. ~~The Godfather on reveal~~: yes, named.

## Only a human playtest can show
- Whether a Godfather as the last Mafia is too hard for the Citizens.
- Whether 6-player Sniper and Jester games are balanced.
- Whether the recorded "killed" voice lines suit Sniper deaths (the new roles have no "they were…" clip).
- Whether the Jester's laugh ending feels right.
- Two names in large Arabic text on a small phone.
- Whether passing the phone gives the Sniper away.
- A real mixed table of 0.4 and 1.0 phones in Classic.

## Commits, ready for `c` (one per change, rollback-ready)
1. Engines: the Godfather, the tie rule, Sniper, Jester, modes (TS + Dart + fixtures + engine tests).
2. Server and protocol: modes, the old-app guard, stats, migration 0010 + rollback + server tests.
3. App: modes, roles, guide, strings, and its tests.
4. 1.0.0.
5. Docs: PRD, report, decisions, handoffs, QA shots, Sprint 17 tools.

The app changes share `ui.dart` and the string files, so they can't be split further without commits that don't build.

## After `cp` (2026-11-25)
| Commit | Change |
|---|---|
| `1a26b56` | S17-3/S17-8: the Godfather, the Mafia tie rule, Sniper, Jester and modes in both engines |
| `b5ec52f` | S17-4/S17-5: modes online, 1.0.0 required to be dealt in, new-role stats, migration 0010 |
| `4893976` | S17-1/S17-5/S17-6: modes in the setup and lobby, the new roles on every screen, How to Play |
| `79d9bd5` | S17-7: 1.0.0 |
| `420b96d` | Sprint 17: PRD, report, decisions, emulator shots, QA scripts |

- **D1 Time Travel bookmark before 0010:** `000000bc-00000000-0000512e-83bf86de3b6333a5123f56a32bb8e899`
  (`wrangler d1 time-travel restore DB --bookmark=<it>` undoes the migration and everything after it).
- **CI on `420b96d`:** test, app and deploy passed; **migration 0010 is applied and the new Worker is live.** The
  emulator job failed in two Wi-Fi integration tests (`wifi_test`, `approval_test`): their scripted guest phones sent
  no build, so the 1.0.0-only deal refused them.
  - **[Quin] logged against Dev and QA:** the report said `integration_test` was "updated but not run locally"; that
    was the gap.
  - **What changes:** a sprint that changes who can be dealt in runs `flutter test integration_test` on the emulator
    before `p`.
  - **Fixed:** the test bot reports 1.0.0. All 7 integration tests pass on the emulator against the local Worker.
    Not committed yet.
