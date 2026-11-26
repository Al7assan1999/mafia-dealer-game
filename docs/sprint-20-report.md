# Sprint 20 report: 1.3.0, new roles and modes

Documents:
- PRD: `docs/sprint-20-prd.md`.
- Roles, modes and edge cases: `docs/sprint-20-roles.md`.
- Brad's research: `docs/sprint-20-brad.md`.
- Rulings: `docs/decisions.md` (Sprint 20).

## What a player gets
**Two new modes** (setup, online lobby and Wi-Fi):
- **Avenger** (6+, for beginners) has the Hunter and never the Sniper. The Mayor joins from 7 players, the Jester from 9, the Bodyguard from 13.
- **Shadows** (8+) has the Sniper and never the Hunter.
  - 2 Mafia: the Godfather and the **Framer**.
  - The Detective, the **Watcher**, the Sniper and the Doctor.
  - The Jester joins from 10 (from 9 with 2 Mafia), the Mayor from 11, the Bodyguard from 13.

**The Mafia count**
- Where §8 allows it, the table chooses between two Mafia counts (for example Shadows at 9: 2 or 3).
- The table rules "lean" the game: if they favour one side by 2 points or more, the count that makes it worse is not offered. The setup says why.

**The Hunter (الصياد)**
- When he dies, by night or by vote, his phone asks him to shoot one player or hold fire.
- Everyone else sees "X, the Hunter, is taking aim…", then his shot.
- His shot comes before the win check, so he can save the game.

**The Mayor (العمدة)**
- By day he can tap "Reveal: I'm the Mayor". It asks to confirm first, and it is proof, because only the real Mayor has the button.
- After that his vote counts twice, every phone names him, and the Doctor can't protect him.
- In pass-and-play he reveals from his own night turn.

**The Framer (الملفّق)**
- He is one of the Mafia. Besides the kill, he frames one player (or chooses "No frame").
- That night the Detective reads the framed player as Mafia.
- The Framer learns whether it worked, on his own screen.

**The Watcher (المراقب)**
- He learns who visited the player he watched: names only, no decoys, and one Mafia for the kill.

**Also**
- The guide lists the Framer and the night order.
- History and the recap name the shot and the reveal.
- The verdict says "The Mayor's vote counts twice" whenever there are more votes than players.
- **A player's photo opens full size** on their profile, with pinch to zoom.

## Test results
| Suite | Result |
|---|---|
| Engine, TypeScript | 90 passed. New: `test/s20.test.ts` (17 tests), and `test/combos.test.ts` (11,608 combinations, 1 game each in CI) |
| Engine, Dart | 16 passed: byte-identical with TS on the 60 shared games, the 19 scripted 1.3.0 games, and the 1.2 records |
| Every combination, 50 games each (§8 E) | Running before release (`GAMES=50`, about two hours). Danial reads the result before go |
| Server (vitest) | 113 passed. New: `test/sprint20.test.ts` (12 tests) |
| App widget tests | 252 passed. New: `test/s20_roles_ui_test.dart` (17 tests) and `test/profile_photo_test.dart` (1) |
| Click map | 25 passed |
| `flutter analyze`, `dart analyze --fatal-infos`, `tsc` | clean |

**The combination test found one real hang before release:**
- The case: a Doctor with "self" off and "not twice" on, next to a revealed Mayor, had nobody to protect, so the night waited forever.
- The fix: any power left with no possible target now skips its turn (both engines).

**Tried for real:** the Worker runtime (miniflare) for the room, the gate, the timer alarm, leave and kick.
**Only against fakes:** the screens, plus the emulator run in CI.

## [Ben · BA] acceptance review
| AC | Verdict | Evidence |
|---|---|---|
| S20-0 photo opens | Accepted | `profile_photo_test` |
| S20-1 AC1: 1.2.1 phones don't break | Accepted | Server tests: `role`/`role2` on History, the game page and Wi-Fi notes. The live room is gated; old phones show "Update to play". Quin traced every 1.2.1 path in HEAD |
| S20-1 AC2: migration 0014 | Accepted for apply. The rollback follows the 0011 pattern and is not run in a test | sprint20 "history takes the new roles" |
| S20-1 AC3: every game ends | Accepted, with a change to the number | TS: 11,608 combinations + 1,000 random games; Dart: 1,000 random games + byte-identical records. The 50-per-combination run gates the release |
| S20-1 AC4: old records replay | Accepted | `records-1.2.json` = HEAD's `records.json`; it replays in both engines |
| S20-2 Hunter | Accepted after Q1, Q2, Q4 | E-H1–H8 engine tests; server: aim, timer, kick, leave, Go on; UI: pass-and-play, online, Wi-Fi leave |
| S20-3 Mayor | Accepted | E-M tests; UI: reveal (online and pass-and-play), ×2 chips, the tally line |
| S20-4 Framer | Accepted after Q3, Q5, Q12 | E-F tests; UI: frame online and pass-and-play, stale frame cleared |
| S20-5 Watcher | Accepted | E-W tests; UI: his list on his next turn |
| S20-6 modes | Accepted | §8 tests in both engines; setup and lobby UI tests; the gate on the server and Wi-Fi |
| S20-7 AC1: screens EN/AR, small phone | Accepted after Q6 | Arabic at 320×568 with text ×1.3: the Hunter's shot, the Framer's night, the Mayor's turn, the morning |
| S20-7 AC2: stats, titles, MVP | Accepted | Server: the profile counts the new roles for the town (it threw before); MVP "Shot a Mafia" |
| S20-7 AC3: 1.3.0+7 | Accepted | pubspec |

**Ben's own find:** with a revealed Mayor, the tally can show 7 votes with 6 people alive, and nothing said why. The verdict now says "The Mayor's vote counts twice" (online and pass-and-play; test).

**Ben owns his mistakes, in writing:**
- **Q5 in the PRD** ("every Mafia who voted visits") would have named every Mafia to the Watcher in one night. Ben caught it himself (E-W1), and you ruled R5.
- **E-F5** ruled something the screen can't do: the kill vote and the frame are one turn. Quin Q12 caught it; the doc is corrected.

## QA ↔ Dev (Quin: 15 findings, 2 blocks, 0 reached you)
| # | Finding | Dev's answer |
|---|---|---|
| Q1 **block** | A dead Hunter who leaves the room while aiming hung the game: nobody could go on | **Fixed.** Leaving while aiming = he holds fire (server and Wi-Fi). The host's button now counts a seat nobody is online for, including someone who left (this also fixes the same old gap for a player who leaves mid-night). Tests on the server, the Wi-Fi host and the UI |
| Q2 **block** | Pass-and-play with the night timer: the timer started when he died, so by the time the phone reached him it had run out, and he "held fire" without choosing | **Fixed.** No clock on his shot on one phone; the phone waits for him (E-H6). Test |
| Q3 | The Framer's "it worked", the Detective's "Mafia" and the Watcher's list showed on the morning and day screens, which the table can see | **Fixed.** The Framer's news and the Watcher's list are on their own next night screen. The Detective's result is in his day list, as in every mode |
| Q4 | An online Hunter who never answers (no timer) had no way past him | **Fixed.** The host has "Go on without his shot", which asks first if the Hunter is still in the room; he holds fire. Tests |
| Q5 | The frame list sat under the kill list with "No frame" preselected, so it was easy to miss; a frame tapped on an earlier turn could block the next night's vote | **Fixed.** He must choose a frame or "No frame" before Confirm. Picks are cleared at every new step online; a stale frame is dropped in pass-and-play. Tests |
| Q6 | The guide had no Framer, no night order, and the Mayor's text said "once a day" | **Fixed.** Framer entry, the fixed night order, and "once per game, and it is proof" |
| Q7 | Test gaps | **Added:** Q1/Q2/Q4/Q5 tests, Wi-Fi note roles, Arabic at a small phone with large text. Not added: a rollback test, and a 1.2.1-shaped app test (the 1.2.1 code can't be built into this test run; Quin traced it by hand) |
| Q8 | `ROLES13_BUILD = 100023` is tied to the next release run | Danial's check: the last release run was 22, so 1.3.0 must be run 23, with no other release before it |
| Q9 | The default rules (reveal on) lean town, so a new host never gets the Mafia choice (Shadows at 9 is always 3) | **His ruling: reveal off by default** (Beginner keeps it on). Choosing a mode now starts at its default count. Older tests keep reveal on explicitly, so their saved games stay byte-identical |
| Q10 | A 1.2.1 phone in a lobby set to Avenger or Shadows shows "Classic" | Note. An old phone can't be taught new modes; the host sees who needs updating, and the deal is refused |
| Q11 | The Hunter's shot isn't spoken by the narrator; the end voice names the person shot, not the Hunter | Note. There are no voice clips for it yet; the screen says it |
| Q12 | E-F5 ruled something that can't happen | Doc corrected (Ben owns it) |
| Q13 | A dead Framer was "Framer" in pass-and-play but "Mafia" online | **Fixed.** He is named on reveal online and on Wi-Fi too (both engines, as the Godfather is) |
| Q14 | A 1.2.1 phone that rejoins its own seat mid-game plays on, degraded, without crashing | Note (the deal itself is gated) |
| Q15 | The "full size" photo is the stored 256 px avatar | Note: yours to judge on a phone |

## Challenge log
- **Ben → his own PRD:** Q5 "every Mafia visits" was too strong (E-W1). You ruled R5: one Mafia.
- **Brad → Ben:** the 25/65/10 ratio. You ruled it a guide; Brad proposed Shadows at 9 with 3 Mafia.
- **The combination test → David:** found the Doctor hang. Fixed in both engines.
- **Quin → David:** Q1 and Q2 blocks, Q3 privacy, Q4, Q5. All fixed with tests; Quin's attempts were re-run by the new tests.
- **Quin → Ben:** Q12, the ruling that couldn't happen. Ben corrected the doc.
- **Quin → Danial:** Q8, the gate tied to run 23. It's on the release checklist.

## [Danial · Release] go / no-go
- **Migration 0014** only widens a CHECK. It rebuilds `game_players` the way 0011 did, keeping every row; nothing references the table.
  - It is safe before the new Worker is live (the old Worker never writes the new roles).
  - Rollback: `server/rollbacks/0014_new_roles_13.sql`. It deletes games that have the new roles.
- **Old phones:**
  - 1.1.x and 1.2.x keep playing Classic and the old modes.
  - Avenger and Shadows deal only when every phone is on 1.3.0 (server and Wi-Fi).
  - History, game pages and Wi-Fi notes give old phones a role they know.
- **Gate:** the build must be **100023**. Release run 23 must be 1.3.0, with no other release before it (Q8).
- **Cost:** no new D1 writes per game, no new Durable Object traffic beyond one message per shot or reveal, and one alarm while a Hunter aims with a timer.
- **Checks:** git email is the noreply address. No secrets in the diff. Version 1.3.0+7.
- **Before go:** the 50-games-per-combination run must finish clean, and CI must be green on the exact commit.
- **Release notes (players):**
  - "Two new modes: Avenger (with the Hunter and the Mayor) and Shadows (the Framer against the Watcher and the Sniper)"
  - "Choose 2 or 3 Mafia in the new modes, and see how your rules favour a side"
  - "New games start with Reveal roles off"
  - "Tap a player's photo to see it full size"

## Only a human playtest can show
- Whether the table understands "X, the Hunter, is taking aim…", and whether a dead Hunter leaves the room.
- The Framer's screen with 12+ players on a small Arabic phone at large text.
- Whether the doubled vote reads clearly on the board and the tally.
- Balance: Shadows at 8 (both Mafia with powers, R6) and Avenger at 6. This needs the §8 E win-rate recheck after real games.
- Whether the Arabic reads naturally: الصياد، الملفّق، المراقب، العمدة، المنتقم، الظلال، «لا أطلق».
- The 256 px photo full screen (Q15).
