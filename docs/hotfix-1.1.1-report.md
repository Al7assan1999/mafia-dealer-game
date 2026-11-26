# 1.1.1 hotfix report

His list (2026-11-26), and his second note (Sami's report wasn't a bug; a taken username needs an alert; the room's side
tab should float over the content and drag). 1.1.0 and 1.1.1 phones play together: the server still requires
build 100019.

## What a player gets
| # | His point | What changed |
|---|---|---|
| 1 | The Sniper didn't understand night 1 | His night-1 screen says **"No shot tonight"**, then that his bullet is ready from night 2 and that tonight's pick changes nothing (decoy off: "Tap Confirm"). Offline, online, Wi-Fi |
| 2 | Ghost view missing (old app) | **Ghost view** is back in the rules (Online group) with its chip: out players see every role on their phone |
| 3 | Out players (the host too) must see the votes | During any vote, open or secret, an out player's screen shows **"Votes so far"**, live. The living still see only the count in a secret vote |
| 4 | The bottom toast is annoying, the buzz above all | In a room, a buzz, ping or mention is a quiet line at the top for 2.5 s. It floats over the screen, so nothing under it moves, and a new one replaces the last (ten buzzes are one line). Toasts everywhere else last 2.5 s (was 4) and a tap hides them. On Home, a minimized room's buzzes no longer queue |
| 5 | Sami's blocks | Not a bug (his ruling): Sami reported you to test it, and the report ticks "Also block" by default. Nothing changed |
| 6 | No connection bar when someone closes the game | The amber "X's connection is lost" bar is gone. Instead: "App closed: X" in small text by the night/vote count, next to the host's Continue anyway on his own pick screens, and a small cloud mark on the day roster. Your own connection bar is unchanged |
| 7 | A second Sami account? | **No.** Production has 7 accounts and one Sami (`@sami`, Google sign-in) |
| 8 | Add without picking from the list | The button is now **Search**. A request goes only from a result's Add. An exact @username is always the first result, so nobody falls past the 20 shown |
| 9 | The role again mid-game (old app) | A role button in the game's top bar (online and Wi-Fi) opens the hold-to-see card; **Got it** closes it. It also closes by itself when the game moves on, a new deal comes, or the room closes |
| 10 | Add from a shared game | A player's page opened from History shows **Add friend** (or Accept / Invite) under their card |
| 11 | Sami twice in the stats | Found the cause (below); one tap for you fixes it |
| — | A taken username | An **alert**: "That username is taken. @x belongs to another player. Pick a different username." It shows on first sign-in and on the profile. The server already refused it, ignoring case; before, it was only a toast |
| — | The room's side tab | The lobby cards use the full width again (the 24 dp strip kept free in Sprint 16 is gone). The friends and chat tabs float over the content and drag up and down together, from the top of the room. In a game the chat tab now drags too |

## Sami (items 5, 7, 11), production, read-only
- **Item 5.** Sami sent 3 reports on 2026-11-25, 16:03–16:06 UTC (you as "spam", Farouq twice as "other"), with "Also block" ticked. That blocked you both and ended both friendships. He has unblocked you since; there are no blocks now, and both friendships were made again at 17:01. The 3 reports are still open in Profile → Reports (dismiss them there).
- **Item 7.** There is only one Sami account.
- **Item 11.** His 58 online games count under his account. His **87 old-app games** count under the name "Sami", because the Old players list has *Sami → no username*. That gives two "Sami" rows on the board. The fix is in the app: **Settings → Old players → Sami → Real, @sami** (or Sami answers "Which one were you?"). His 6 games as "Sami Aljammal" are already on his account.

## Test results
| Suite | Result |
|---|---|
| Engine, TypeScript | 72 passed (new `test/hotfix111.test.ts`) |
| Engine, Dart | passed (new `test/hotfix111_test.dart`), records byte-identical |
| Server | 83 passed (new `test/hotfix111.test.ts`: exact @username first) |
| App widget tests | 218 passed (new `test/hotfix111_test.dart`, 12 tests) |
| `flutter analyze` / `tsc` | clean |
| Emulator integration tests (local Worker, real app) | 7 passed (the online game re-run once after the local sign-up rate limit was cleared) |

Tests changed on purpose:
- `online_test`: there is no bar for another player any more.
- `account_test`:
  - the friends box searches;
  - a taken username shows the alert.
- `s16_lobby_tabs_test` and `sprint12_test`: the tabs may float over the cards and the room code (his note).

## QA ↔ Dev (Quin: 14 findings, 0 reached you)
| # | Finding | Answer |
|---|---|---|
| Q1 | Item 5's change was pulled | His ruling: not a bug; the "Also block" default stays |
| Q2 | Two tests red after his second note | Fixed: the tests follow the new behaviour (alert dismissed; tabs may float) |
| Q3 | The buzz line pushed the vote options down for 2.5 s | **Fixed**: it floats over the top edge; test |
| Q4 | The role page stayed open into the night, a new deal, a closed room | **Fixed**: it closes itself when the game moves on; test |
| Q5 | With Search only, an exact @username could fall past the 20 results | **Fixed** on the server: exact match first; test |
| Q6 | The host on his own pick screen couldn't see who was offline | **Fixed**: "App closed: X" by Continue anyway; test |
| Q7 | "App closed" also shows for a dropped network; Arabic list separator | Note: the server only knows the socket closed |
| Q8 | Out players always see a secret vote (not only with Ghost view) | As he asked ("must see the votes"). Logged in decisions |
| Q9 | Error toasts at 2.5 s may be short for long Arabic text | Note; a tap hides, they can't be paused |
| Q10 | With the chat open, a buzz is only a sound | Note |
| Q11 | Edge cases on the player page (blocked: a "blocked" toast) | Acceptable |
| Q12 | Ghost view shows in the one-phone setup too | Like the night timer, in the Online group |
| Q13 | Test header path; Sniper texts | Fixed the header; the Sniper title is checked online |
| Q14 | The build number must rise | The release run gives build 100020 |

## Challenge log
- **Quin → David:** Q3 (the strip moved the options), Q4 (the role page outlived the step), Q5 (the exact handle could become unreachable), Q6. David fixed all four with tests.
- **Quin → Ben:** Q1, item 5 pulled. Ben: his ruling, logged.
- **Quin → Ben:** Q2, the side-tab change undoes Sprint 16-1 (his own earlier note: tabs covered the ⋮ menus). Ben: his new note wins. The tabs drag off whatever they cover; logged.
- **Ben's own finding:** the chat tab alone (in a game) had no drag handle at all. Now the whole tab stack drags.

## [Danial · Release] go / no-go
- Version 1.1.1+4, release build 100020. The server gate stays at 100019, so 1.1.0 phones aren't asked to update to play.
- The server changes are the engine view (out seats get `board` during a vote) and the search order. Old phones ignore `board` on an out seat. No migration, no new traffic.
- No secrets in the diff; git email is the noreply address.
- Release notes (players): "The Sniper's first night is clearer; Ghost view is back in the rules; Players who are out see the votes as they come in; Buzzes and notices are quieter; No more bar when someone closes the app; See your role again during a game; Friends: Search, then Add; add players from a shared game; The chat and friends tabs can be moved up and down; A taken username is clearly shown".

## Only a human playtest can show
- Whether the Sniper reads "No shot tonight" right away, in Arabic too.
- Whether out players at a real table keep the secret vote to themselves.
- Whether the floating tabs cover something you need in a game, and whether people find the drag.
- Whether a host notices "App closed: X" when he needs to press Continue.
- The top bar on a small phone: narrate, role, buzz/ping and leave next to the room code.
