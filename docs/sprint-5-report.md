# Sprint 5 Release Report: room chat, safety, and the walkthrough fixes

2026-11-22. Built against `docs/sprint-5-prd.md` (revised by [BA] after the player walkthrough; signed off with the
recommended answers). Run as the three personas (`docs/team-workflow.md`). **Not committed yet.** On the next push CI
deploys migration `0005` and runs the new emulator chat test.

## [QA] Results: green
- **Server:** **46/46** vitest. New tests:
  - blocks (friendship ends; requests hidden both ways, silently; unblock first);
  - reports (validation, snapshot), admin-only access, bans (signed out, sign-in refused);
  - a report outliving the reporter's account;
  - room chat across a block (Everyone, DMs, history on rejoin);
  - the room supplying a reported message's text; reports refused when the message isn't theirs;
  - the server clock in `room`.
- **App:** analyzer clean. **53/53 widget tests** (42 existing + **11 new** in `test/sprint5_test.dart`).
- **Engines:** 34 TypeScript + 5 Dart groups, unchanged.
- **New emulator test** (`integration_test/chat_test.dart`, CI only): chat both ways with a scripted player in a real
  room, then report + block from a message; their next message never arrives and the friendship is gone.

## [QA] → [Developer]: what QA found, and the fixes
| # | Found by | Finding | Fix |
| --- | --- | --- | --- |
| 1 | widget tests | **Opening the chat crashed the room screen:** marking the conversation read rebuilt the room screen while Flutter was building | Marked read just after the frame; on close, just after the screen is gone, never after the room has closed |
| 2 | widget tests | Each sent message's 10-second "not confirmed" timer outlived the room | Timers cancelled with the room |
| 3 | UX pass | **Chips were Material's default teal** (chat conversations, setup presets): off-brand in Noir | Noir red when selected (then a second pass caught the chip labels losing the app font; fixed) |
| 4 | UX pass | **In Arabic, an English chat line lost its direction** ("@P2 …" showed as "… yesterday@") | Each message takes its direction from its first letter |
| 5 | UX pass | Emoji show as boxes in the screenshots | Not an app bug: the test renderer has no emoji font; Android draws them. **On your playtest list.** |

## [BA] Acceptance review
| AC | Verdict | Evidence |
| --- | --- | --- |
| S5-1 AC1 chat button, badge, conversations | ✅ Accepted | Badge counts and clears (test); Everyone + one chip per player (screenshot 36) |
| S5-1 AC2 sending / not sent / retry / queued | ✅ Accepted | Tests: ack clears "Sending…", a refusal shows "Not sent · tap to retry" and retries, a message written during a drop goes out after reconnecting |
| S5-1 AC3 reply, reactions, edit, mentions | ✅ Accepted | Tests: swipe toward the middle in English and Arabic, long press → reaction, edit within 15 min only, @mention with its cn. Mentions buzz the phone. |
| S5-1 AC4 counter, slow down, RTL, Case-file look | ✅ Accepted | 200 counter, slow-down = "not sent"; Arabic screenshot after fix 4 |
| S5-1 AC5 history without duplicates | ✅ Accepted | Test: history replayed, nothing doubles |
| S5-2 AC1 block | ✅ Accepted | Server tests (every path); emulator test (the next message never arrives) |
| S5-2 AC2 unblock | ✅ Accepted | Test: Profile → Blocked players → Unblock |
| S5-2 AC3 report with snapshot, offer to block | ✅ Accepted | Tests: the dialog shows the message, reason, note, "also block" (on by default); the server stores the room's text |
| S5-2 AC4 admin dismiss / ban | ✅ Accepted, **one step left for you** | Tests: the admin sees the queue, ban works. **To become admin:** Profile → Account ID → copy and send it to me; I set the `ADMIN_IDS` GitHub secret (deploy puts it on the Worker). |
| S5-2 AC5 server | ✅ Accepted | Migration `0005` + rollback, endpoints, rooms respect blocks, deletion rules |
| S5-3 AC1 (W1) who's alive on the day | ✅ Accepted | Offline (test) and online (screenshot 34b, test); out players struck through, with their role offline when the reveal rule is on |
| S5-3 AC2 (W2) how the town decides | ✅ Accepted | Test: the choice first, then the pick list, and back |
| S5-3 AC3 (W3) online vote labels | ✅ Accepted | "Secret vote (each phone)" / "Table vote (everyone sees)" with a line each (screenshot) |
| S5-3 AC4 (W4) neutral avatars | ✅ Accepted | Lobby screenshot: masks, moon, eye… no role icons |
| S5-3 AC5 (W5) lobby summary + offline warning | ✅ Accepted | Test + screenshot: "4 players · 1 Mafia · Doctor · Classic", "P4 is offline and would be dealt in" |
| S5-3 AC6 (W6) @handles in Arabic | ✅ Accepted | Kept left-to-right everywhere (test) |
| S5-3 AC7 (W7) host controls off during a drop | ✅ Accepted | Test: nothing queues from a host button while disconnected; chat still queues |
| S5-3 AC8 (W8) How to play | ✅ Accepted | Offered once on first launch, always reachable from Home (test; screenshots 03/04, Arabic too) |
| S5-3 AC9 (W9) night number offline | ✅ Accepted | Night pick header |
| S5-3 AC10 one clock | ✅ Accepted | The server's `now` in every `room` message; timers use the measured offset |

**[BA] notes for the next audit:**
- **"How to play" shows twice on Home** (the offer card and the footer link) until the offer is used or closed.
  Acceptable for now.
- **The report dialog preselects "Harassment"** to save a tap; worth watching whether that skews reports.
- **The old reaction set includes 🖕** (kept for parity with the old app). Your call whether a public Play app keeps it.

## Caveats for your playtest
1. **Emoji** in chat and reactions (they render on a phone, not in the screenshots).
2. **Chat with friends** in a real room: swipe to reply (Arabic swipes the other way), reactions, editing, @mentions
   buzzing.
3. **Block someone in the middle of a game:** their messages stop at once.
4. **Send me your Account ID** (Profile) to turn on the admin queue.
