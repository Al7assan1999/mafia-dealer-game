# 1.2.1 hotfix report

His note (2026-11-26): "Sami took the best doctor from me". Then: why did the note come only now? Why does a player's page
change with where it's opened from? And: there should be no Old tab anywhere, since every old player is linked.
1.2.0 and 1.2.1 phones play together (no game rule changed).

## What happened (production, read-only)
- **Best Doctor was a tie.** You had 13 saves (8 online + 5 old app). Sami had 6 online on his account and 7 under the
  old name "Sami", which were two separate rows. Linking Sami → @sami (00:20 UTC) put them together: 13. On a tie the
  first player in the game list won, and that was Sami.
- **Why it came hours later.** Saving the Old players list did not recount the titles. The next recount was at 06:42 UTC.
  Only a game ending, a host marking a game, a Wi-Fi approval or someone switching "show me on the board" recounts, and
  no game ended then, so it was one of the last three. The database doesn't say which.
- **Most killed first** went from Farouq to Sami at the same moment. That one was a real pass (27 vs 24), not a tie.
- **A player's page** opened from Stats used the board's filter (Online, Wi-Fi, last 30 days…) without saying so. From
  History it always showed everything.

## What changed
| His point | What changed |
|---|---|
| Sami took Best Doctor | **A tie leaves a title with whoever holds it.** It moves only when someone has strictly more. Migration 0013 gives Best Doctor back to you and removes that one note (only if it still points at Sami) |
| The note came late | Saving Old players **recounts the titles at once**. It is your bookkeeping, so it sends nobody a note (Quin Q3: a misclick or a double tap would have pushed players). Titles taken in a game still send the note as before |
| The page changes with where it's opened | A player's page shows **every game, all time**, from Stats, History, Friends or Profile |
| No Old tab anywhere | **Stats:** the Old filter is gone; **Online** includes the old app's games. **History:** two tabs (Online, Wi-Fi). The old games you played are in Online by date, marked "Old app", and open their own page. If they fail to load, the list says so with **Try again** |

## Test results
| Suite | Result |
|---|---|
| Engine, TypeScript / Dart | unchanged |
| Server (`server`, vitest) | 101 passed (new: `test/hotfix121.test.ts`, 7 tests) |
| App widget tests (`app`) | 234 passed (new: `test/hotfix121_test.dart`, 3 tests; `sprint8_test` updated for the Online list) |
| `flutter analyze` / `tsc` | clean |

The emulator tests run in CI.

## QA ↔ Dev (Quin: 11 findings, 0 blocks)
| # | Finding | Dev's answer |
|---|---|---|
| Q1 | While deploying, the old code still runs for a few seconds after migration 0013. A game ending right then would give the tie back to Sami for good | **Release check:** Danial reads `titles` after the deploy (read-only). If Sami is back, ask him before fixing it by hand |
| Q2 | With "the holder keeps a tie", undoing something (a game marked invalid then valid again) can move a tied title for good | **Accepted** as part of the rule he asked for ("only passing takes it") |
| Q3 | Every Old players click could push title notes, twice on a double tap | **Fixed**: that recount is quiet; test |
| Q4 | History waited for the old games, and hid it when they failed | **Fixed**: online games show first, and a failure says so with Try again; test |
| Q5 | The admin's old list is the newest 300 of all imported games (119 now) | Note |
| Q6 | An old name without an account doesn't keep a tied title | Note: every name is linked |
| Q7 | On a tie, the Best player title can be the second of two rows ranked #1 | Note |
| Q8 | Old games marked Waiting/Test show under "Valid"; old games can't be hidden; two strings unused | Strings removed; the rest is a note |
| Q9 | The two account ids in 0013 are not checked by any test | **Checked** against production (read-only): Alhassan `a1edc5b5…`, Sami `f2250a3e…`, `titles.doc` = Sami |
| Q10 | On a 1.2.0 phone, Online and Old app both show the old games | Harmless; the notes ask everyone to update |
| Q11 | Test gaps | Added: Best Mafia / Best Detective ties, the minimum, the board shows the holder, a tie sends no note, a quiet recount, Test name, the failure line |

## [Danial · Release] go / no-go
- **Migration 0013:** data only. It changes one settings value and deletes one bell note, only if they are as the tie left
  them. Rollback: `server/rollbacks/0013_title_tie.sql`.
- **After the deploy (Q1):** read `settings.titles` (read-only) and check that `doc` is Alhassan's.
- **Cost:** a recount per Old players click (the same work as after a game).
- Version 1.2.1+6; release build 100022.
- Release notes (players):
  - "Old app games are now part of Online, in History and Stats"
  - "A tie no longer takes a title away"
  - "A player's page shows the same numbers wherever you open it"

## Only a human playtest can show
- Best Doctor is yours on the board after the deploy, and the bell has no "Sami took Best Doctor" note.
- History on a weak network: the online games show, and the old ones join them (or the Try again line shows).
- The long History line in Arabic at the largest text size ("… · Invalid game · Old app").
