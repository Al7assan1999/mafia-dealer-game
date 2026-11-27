# Sprint 21 report: 1.4.0, wave 2 (the Serial Killer, Cupid and the Lovers, the Silencer)

Documents:
- PRD and rulings R1–R12: `docs/sprint-21-prd.md`.
- Brad's research: `docs/sprint-21-brad.md`.
- Sign-off: `docs/decisions.md` (Sprint 21).

## What a player gets
**Two new modes** (setup, online lobby and Wi-Fi; every phone needs 1.4.0):
- **Lovers** (8+): Cupid links two players on night 1. The Hunter joins from 9 (the Sniper instead from 17), the Jester from 9, the Mayor and the Bodyguard from 11, the Watcher from 13.
- **Lone Wolves** (9+): one Serial Killer against the Mafia and the town. The Silencer joins the Mafia from 11, the Framer from 13; the Watcher and the Jester from 11, the Mayor from 13, the Hunter from 17.

**The Serial Killer (القاتل المتسلسل)**
- He kills one player every night, on his own. The Doctor can save his victim and the Bodyguard can cover them. The Detective reads him "not Mafia".
- He wins alone, or as one of the last two with a non-Mafia. He and one Mafia as the last two is a **draw**. Nobody else wins while he lives.

**Cupid (كيوبيد) and the Lovers (العاشقان)**
- On night 1 Cupid picks two players (himself allowed). Each lover learns the other's name and side from the morning of day 1.
- If one dies, by night, by vote or by the Hunter's shot, the other "dies of a broken heart", announced.
- A mixed couple (one Mafia, one town) wins as the last two.

**The Silencer (المُسكِت)**
- One of the Mafia. Besides the kill vote, he picks one player who can't vote the next day (not himself, not the same player two nights running).
- The morning names who can't vote. That phone shows "You can't vote today".

**The old modes get Mafia ranges:** Sniper, Jester and Bodyguard now offer a choice of Mafia count, as Avenger and Shadows do. The default is the count they always dealt.

**Also**
- New endings in the guide, the history, the end screen (its own backdrop and colour) and the stats.
- MVP for the Serial Killer and for the Lovers.
- Arabic throughout; version 1.4.0+9.

## Test results
| Suite | Result |
|---|---|
| Engine, TypeScript | 111 passed. `test/s21.test.ts` has 19 tests (9 added after Quin's review, plus the regression test for the bug below) |
| Engine, Dart | 19 passed: byte-identical with TS on the shared games, the 1.3 records and the 29 scripted 1.4.0 games |
| Every combination, 1 game each (CI) | 15,422 combinations, passed |
| Every combination, 50 games each (§8 E) | **Passed after the fix below:** 771,100 games, 0 failures (134 minutes) |
| Server (vitest) | 121 passed. New: `test/sprint21.test.ts` (7 tests) and `test/migration15.test.ts` (1) |
| App widget tests | 267 passed. New: `test/s21_roles_ui_test.dart` (13 tests) |
| `flutter analyze`, `dart analyze`, `tsc` | clean |
| Click map | 25 passed before Quin's review; not rerun after the QA fixes |

**The 50-games run found one real bug before release:**
- The case: Lone Wolves, 14 players, "not twice" on. The Mafia's only possible target was the Serial Killer they had attacked the night before, so they had no one to pick.
- In TypeScript, the empty pick was counted as a vote for a seat that doesn't exist. In Dart (the phone hosting Wi-Fi or pass-and-play), it would have **crashed the game**.
- The fix: an empty pick is not a vote, in both engines. A scripted test fails without the fix and passes with it.
- It could only happen once a Serial Killer can keep a game going, so it is new in 1.4.0.

**Tried for real:** the Worker runtime (miniflare) for the room, the gate, a host hand-off, and migration 0015 and its rollback on a database with games already in it.
**Only against fakes:** the screens.

## [Ben · BA] acceptance review
| AC | Verdict | Evidence |
|---|---|---|
| S21-1 AC1: migration 0015 | Accepted after Q4 | `migration15.test`: a 1.3 game with its players and an approved Wi-Fi link survives the migration. The rollback removes only the Serial Killer and Cupid games, and forward works again |
| S21-1 AC2: old phones | Accepted after Q1 | Server: `winner`/`role` a 1.3 phone knows on the games list, the game page and Wi-Fi notes. 1.4.0 deals rv 2 whenever 1.3.x would have dealt the same, so 1.3.x guests keep their Wi-Fi History |
| S21-1 AC3: every game ends | Accepted: the 50-games run passed after the fix | 15,422 combinations; 1,000 random games in each engine with each ending checked on its own terms (Q4) |
| S21-1 AC4: old records replay | Accepted | `records-1.3.json` (1.3's `records.json`) replays in both engines. The 1.0–1.3 scripted fixtures are byte-identical to the committed ones |
| S21-2 Serial Killer | Accepted after Q4 | E-K1 (he kills the Hunter, who aims), E-K4 (voted out), E-K5 (removed), D9 (the Hunter's shot before his win, both ways), the same target as the Mafia (one death, counted once), a draw in play |
| S21-3 Cupid and the Lovers | Accepted after Q3, Q4 | E-C1–C6, C7 (both lovers killed the same night, no second heart), C9 (the Watcher sees Cupid); online: the partner on the morning and day screens |
| S21-4 Silencer | Accepted after Q4 | E-S1 (the silenced revealed Mayor), S2 (killed: his pick counts; removed: it doesn't), S3 (the silenced player dies: nothing announced), S5 (timeout: no silence) |
| S21-5 Modes and gate | Accepted after Q2, Q6 | Server gate and Wi-Fi gate; a signed-in player keeps the chosen count; the count is dealt by the build that chose it |
| S21-6 Screens, stats, text | Accepted after Q8–Q10 | Arabic at a small phone with large text; stats per seat; MVP; the Silencer named on reveal everywhere |

**Ben's own find:** Q1's fix keeps 1.3.x guests' History for any deal 1.3.x could have made. If a 1.4.0 host **chooses a non-default Mafia count** in the Sniper, Jester or Bodyguard mode, the game is rv 3, and a 1.3.x guest still can't replay it, so it is missing from their Wi-Fi History. There is no crash, and updating to 1.4.0 brings it back. Ben accepts it, because a gate would stop old phones from playing those modes at all.

## QA ↔ Dev (Quin: 12 findings, 0 blocks, 0 reached you)
| # | Finding | Dev's answer |
|---|---|---|
| Q1 | Every 1.4.0 deal was rv 3, so 1.3.x guests of a 1.4.0 Wi-Fi host lost the game from History | **Fixed.** rv 3 only for Lovers, Lone Wolves, or a Mafia count 1.3.x wouldn't deal. Both engines; the random games check the rule |
| Q2 | A signed-in player's chosen Mafia count went back to the default on the next game (the account copy drops the flag) | **Fixed.** The flag is read from the phone's own copy. Test fails without the fix |
| Q3 | Online and Wi-Fi, a lover saw the partner only on night 2 (R4 says the morning of day 1) | **Fixed.** The morning and day screens show it, on the lover's own phone. Test |
| Q4 | Test gaps | **Added:** Dart checks each ending as TS does; E-K1, K4, K5, D9, same target, E-C7, C9, E-S1, S2 (killed), S3, S5, a draw in play; the migration test with real rows and the rollback. Not added: S21-5 screens for the old-mode ranges in the lobby (the server deal is tested) |
| Q5 | The rollback leaves approved Wi-Fi requests pointing at nothing | Note, and in Danial's checklist. The migration test shows it |
| Q6 | The count was dealt by whoever held the controls, not the phone that chose it | **Fixed.** The room keeps the build that sent the setup. Test with a 1.4.0 host who drops and a 1.3.1 phone that deals; it fails without the fix |
| Q7 | The gate assumes release run 25 is 1.4.0 | Danial checked: the last release run is 24 |
| Q8 | The end screen used the town's backdrop for a Serial Killer win, a Lovers win and a draw | **Fixed.** Blood for the Serial Killer, night for the Lovers, day for a draw. Test |
| Q9 | The History game page didn't name the Silencer | **Fixed** (server and app) |
| Q10 | With reveal on, a dead Silencer was "Silencer" or "Mafia" depending on how he died | **Fixed.** He is named on reveal everywhere, like the Godfather and the Framer (both engines, Wi-Fi, online, pass-and-play) |
| Q11 | The server wrote `pair` before `silence`; Dart writes `silence` first | **Fixed** (Dart's order). No seat sends both today |
| Q12 | Latent for Sprint 22's All mode: a Serial Killer lover's side, his win with a town lover, a Hunter with nobody to aim at | Note: Sprint 22 must rule these before All has both roles |

## Challenge log
- **Brad → Ben:** "the Hunter can't be a lover". Ben's edge cases showed a Hunter lover works (E-C2, E-C3), and you kept him in.
- **Ben → Brad:** where the Silencer goes. Brad hadn't placed him; Ben put him in Lone Wolves, because a thinking table suits the vote ban.
- **Ben vs Brad:** one or two Serial Killers at 17–20 (R9). You ruled one, to judge in a playtest.
- **The tests → David:** a 1.3.x host's Sniper game would have dealt the Classic stepper's count. Fixed with a legacy deal before Quin saw it; Q6 then tightened it.
- **The 50-games run → David:** the empty Mafia pick (above). Fixed in both engines with a test.
- **Quin → David:** Q1, Q2, Q3, Q6, Q8–Q11 fixed with tests; Q4's gaps filled.
- **Quin → Danial:** Q5 and Q7 are on the release checklist.

## [Danial · Release] go / no-go
- **Migration 0015** rebuilds `games` and `game_players` with the wider CHECKs, the way 0010 did.
  - It copies the players and the Wi-Fi links first, so dropping `games` loses nothing. A test proves it on real rows.
  - It is safe before the new Worker is live: the 1.3.x Worker never writes the new values.
  - Rollback: `server/rollbacks/0015_wave2.sql`. It deletes the Serial Killer, Cupid, Lovers-win and draw games. Their approved Wi-Fi requests stay "approved" with no game (Q5).
- **Old phones:**
  - 1.3.x keeps playing every old mode. Lovers and Lone Wolves deal only when every phone is on 1.4.0 (server and Wi-Fi).
  - History, game pages and Wi-Fi notes give old phones a result and a role they know (`winner`, `role`); 1.4.0 reads `winner2`, `role2`.
  - A 1.3.x host's Sniper, Jester or Bodyguard game deals the old count (it is decided by the build that sent the setup).
- **Gate:** the build must be **100025**. The last release run is 24, so release run 25 must be 1.4.0, with no other release before it.
- **Cost:** no new D1 writes per game. One more small field in the room state. No new alarms.
- **Checks:** git email is the noreply address. No secrets in the diff. Version 1.4.0+9.
- **Before go:** the 50-games-per-combination run passed after the fix (771,100 games, 0 failures). CI must be green on the exact commit.
- **Release notes (players):**
  - "Two new modes: Lovers (Cupid links two players) and Lone Wolves (a Serial Killer against everyone)"
  - "A new Mafia role: the Silencer, who stops one player voting"
  - "Choose the Mafia count in the Sniper, Jester and Bodyguard modes too"
  - "New endings: the Serial Killer, the Lovers, and a draw"

## Only a human playtest can show
- Balance: Lone Wolves at 17–20 with one Serial Killer (R9), and the new default counts in the old modes.
- How long a game runs when the Serial Killer and two Mafia stalemate.
- Whether "X died of a broken heart" and "X can't vote today" read clearly in Arabic on a small phone at the table.
- Whether Cupid's two-tap pick is understood without help.
- Whether a mixed couple notices they can win together as the last two.
- How the end screen and the sound feel for a Serial Killer win, a Lovers win and a draw (no voice clips for them yet).
- Whether the Arabic reads naturally: القاتل المتسلسل، كيوبيد، العاشقان (the couple and the mode)، المُسكِت، الذئاب المنفردة.
