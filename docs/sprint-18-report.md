# Sprint 18 report: 1.1.0, the Bodyguard and two rule fixes

PRD: `docs/sprint-18-prd.md` (his answers at the end). Rulings: `docs/decisions.md` (2026-11-25, Sprint 18).

## What a player gets
- **The Detective never checks the same player twice.** Players he already checked stay marked on his night screen,
  "Mafia" or "not Mafia" (the Godfather reads "not Mafia" for the whole game), and can't be picked again. Once
  everyone else is checked, his turn says "You've checked everyone" and lists his results.
- **No Sniper shot on night 1.** That night he picks like a Citizen, told "Your bullet is ready from night 2".
- **The Bodyguard (الحارس الشخصي).** Each night he guards a player (not himself, not the same player two nights
  running). A Mafia kill or a Sniper shot at that player goes to him instead; the Doctor can save him from the
  Mafia, never from a bullet.
- **Where he's dealt:** a new Bodyguard mode (6+), All roles, and an "Add a Bodyguard" switch in the Sniper and Jester
  modes.
- **His results show:** the recap puts a shield on a Bodyguard who took the hit; the history says whom he guarded
  each night; he can be the Player of the game ("Took the hit"); profiles count "Took the hit".
- **Every table needs 1.1.0** (build 100019), Classic too.

## Test results (final run)
| Suite | Result |
|---|---|
| Engine, TypeScript (`packages/engine`) | 71 passed |
| Engine, Dart (`packages/engine_dart`) | 12 passed: byte-identical records for the 60 shared seeds, 1,000 random games, every fixture set |
| Server (`server`, vitest) | 82 passed (new: `test/sprint18.test.ts`) |
| App widget tests (`app`) | 206 passed (new: `test/s18_ui_test.dart`, 8 tests) |
| `flutter analyze` / `tsc` | clean |
| Emulator integration tests (local Worker, `integration_test/`) | 7 passed |

Fixtures: `records-1.0.json` (the 1.0.0 shared games, kept), `records-s18.json` (the scripted 1.1.0 games, replayed by
both engines), `records.json` regenerated (every new game is a 1.1.0 game), `records-roles.json` unchanged (1.0.0).

## Emulator pass (real app, profile build, `docs/qa/s18/`)
- `s01`/`s02` setup: five modes; Sniper picked; "Add a Bodyguard" turned on adds the Bodyguard row to the deck.
- `s04` the Sniper on night 1: "Who do you suspect?" with "Your bullet is ready from night 2"; no "Keep the bullet".
- `s05` the Bodyguard's night: "Who do you guard tonight?", his own seat greyed.
- Tried for real: the offline pass-the-phone flow in Sniper + Bodyguard mode (6 players).
- Only against fakes: the online Detective screens and the Wi-Fi host JSON (widget tests); the online deal of a
  Bodyguard mode (server tests against a real Worker runtime).

## [BA] acceptance review (Ben)
| AC | Verdict | Evidence |
|---|---|---|
| S18-1 AC1–2 marked, can't re-check | Accepted | s18.test "S18-1…", UI "S18-1 on screen" |
| S18-1 AC3 offline / online / Wi-Fi, EN/AR | Accepted (Arabic tags covered by the shared strings only) | UI tests offline + online + Wi-Fi JSON |
| S18-1 AC4 everyone checked | Accepted | s18 "AC4", UI "You've checked everyone" |
| S18-1 AC5, S18-2 AC4 old records | Accepted | 60 records-1.0 games replay in both engines |
| S18-2 AC1–3 night 1 | Accepted after Q4 | s04, s18 "S18-2", UI "[Quin Q4]" |
| S18-3 B1–B15 | Accepted (B13/B15 after Q2, see below) | s18 B-tests, fixture games |
| S18-4 AC1–4 modes, switch | Accepted after Ben's own finding (below) | s01/s02, UI "S18-4 setup" |
| S18-5 AC1–4 screens, stats | Accepted after Q5 | UI recap shield, server moments.guards |
| S18-6 engines in step | Accepted | Dart replays records-s18 byte-identical |
| S18-7 AC1, AC3 | Accepted; AC3 with Q6 (old app's History) as a known limit | server "every table needs 1.1.0" |
| S18-7 AC2 migration 0011 | Accepted: local QA database and a copy of production (his OK), see Danial | Danial's check below |
| S18-8 1.1.0 | Accepted | pubspec 1.1.0+3 |

**Ben's own finding (not raised by Dev or QA):** on the emulator the "Add a Bodyguard" switch sat under "All roles",
which reads as if it belonged to All roles. It now sits right under the Sniper or Jester tile it changes.
**Ben owns:** B13 and B15 in his own PRD contradicted each other ("Reveal saves" names whom the Doctor saved, but the
Mafia mustn't learn a Bodyguard was involved). Quin found it (Q2).

## QA ↔ Dev (Quin: 10 findings, 0 blocks; 0 reached you before QA)
| # | Finding | Dev's answer |
|---|---|---|
| Q1 | Once the Detective has checked everyone, any choice was accepted (a dead seat's role, a crash on Wi-Fi, Dart parity) | **Fixed** in both engines: in a 1.1.0 game "nothing to pick" takes no pick; test |
| Q2 | B3 with "Reveal saves": the morning named the Bodyguard, telling the Mafia | **Fixed** by B15: the morning names the Mafia's own target; test. *Your call if you prefer otherwise* |
| Q3 | Guarded player removed mid-night: the Bodyguard still died | **Fixed**: a guard covers only a player still in; test |
| Q4 | Decoy off: the Sniper's night-1 note missing | **Fixed** offline and online; test |
| Q5 | No "Took the hit" on the recap; the server ignored it | **Fixed**: shield on the recap, `moments.guards` on the profile; tests |
| Q6 | A 1.0.x phone's History crashes on a game with a Bodyguard (it reads every role by name) | **Not fixable in the old app**; the API doesn't know the caller's version. Release note: update every phone you play on. Ben agrees |
| Q7 | Deploy order | Answered by Danial below |
| Q8 | The Sniper's and the Bodyguard's night lines were out of date | **Fixed** EN/AR |
| Q9 | The night log names the Bodyguard as the Mafia's kill | **Not a bug**: the log records who died; the guard line says whom he covered |
| Q10 | Test gaps | Added: Q1, Q2, Q3, Q4, Q5 tests. Left: Arabic tag rendering (strings only), 0011 rollback run |

## Challenge log
- **Brad → Ben (PRD):** B6/B7 defaults: Ben took Brad's "not the same player twice running" (the Doctor + Bodyguard
  lock), kept "not himself". One round.
- **Quin → Ben:** B13 vs B15 contradiction (Q2). Ben: B15 wins, the Mafia's target is named.
- **Quin → David:** Q1 (a crash path on Wi-Fi and a role leak). David fixed it, limited to 1.1.0 games so old
  records still replay. Quin's attempt now refused (test).
- **Quin → David:** Q9. David: not a bug, with the reason above; Quin's note stands.
- **Ben → David:** the switch placement, from the emulator. Fixed.
- **Ben → his own PRD:** P1 "on his role card": the role card is never shown during a game. Ben moved it to the
  Detective's night screen (and his own day screen online). Logged in decisions.

## [Danial · Release] go / no-go: **GO**, on `cpr` in one go
- **0011 on a copy of production** (his OK, 2026-11-25): 44 games, 218 seats, 119 old-app games, 7 accounts, at 0010.
  Applied as CI does (`migrations apply`): every seat row identical before and after, both indexes back, no foreign-key
  errors, a Bodyguard seat accepted. Rollback: only the game holding the test Bodyguard seat went (44→43 games), the
  old CHECK refuses a Bodyguard again, `d1_migrations` back to 0010. The export and the copy were deleted.
- Version 1.1.0+3; release build will be **100019** (release run 19; run 18 was 1.0.1). The server requires 100019.
- `git config user.email` is the GitHub noreply address. No secrets in the diff.
- **Migration 0011** only widens `game_players.role` (adds 'bodyguard'); `games` untouched; nothing references
  `game_players`; rollback written (`server/rollbacks/0011_bodyguard.sql`, deletes Bodyguard games first). CI applies
  migrations before deploying the Worker, so a save never meets the old CHECK (Quin Q7).
- **Deploy order (Q7):** the push deploys the Worker first; from then until the 1.1.0 APKs are out, 1.0.x tables are
  refused ("update"). So: `cp` and `r` back to back. 1.0.1 phones show their old text ("update to 1.0.0") during
  that window; the update offer in the app names 1.1.0.
- **Cost:** no new Durable Object traffic, one D1 table rebuild (a few hundred rows), no new pushes.
- **Old apps (Q6):** a 1.0.x phone can't open History entries that have a Bodyguard. Release notes say so.
- Release notes (players): "The Bodyguard (الحارس الشخصي): guards someone each night and takes the hit; Bodyguard
  mode, and an optional Bodyguard in the Sniper and Jester modes; The Detective never checks the same player twice
  and sees his earlier results; The Sniper's bullet is ready from night 2; Everyone at the table needs 1.1.0;
  Update every phone you play on".

## Your decisions
1. Test 0011 on a copy of production: **yes** (done, clean).
2. Q2: the morning's "Reveal saves" names the Mafia's target, not the Bodyguard (B15). Keep? (BA default until you say)

## Only a human playtest can show
- Whether a Doctor + Bodyguard pair feels unbeatable at 7–8 players.
- Whether the Mafia read the Bodyguard from who dies.
- Whether a bystander can read the Detective's tags on a passed phone.
- Whether the long Arabic tag row wraps cleanly on a small phone with large text.
- Whether the Sniper understands his night-1 screen.

## Commits, ready for `c`
1. Engine: the 1.1.0 rules and the Bodyguard (both engines, fixtures, tests).
2. Server: the Bodyguard online, the 1.1.0 gate, migration 0011, stats.
3. App: the Bodyguard and the new rules on every screen; strings; tests.
4. QA scripts and test phones on 1.1.0.
5. Sprint 18: PRD, report, decisions, emulator shots; 1.1.0.
