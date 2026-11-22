# Sprint 1 PRD: a game you can trust

Status: **signed off and built 2026-11-22** (results: `docs/sprint-1-report.md`). Not committed.

## Audit: where the product stands
- **Built and live:** the rules engine (TypeScript, 32 tests) and the Cloudflare server: accounts, friends, online
  rooms in Durable Objects, chat, history (30 tests).
- **Not built:** the app itself. There's no Flutter code yet, so there's no UI to audit or click through. The
  player-facing reference is the old app (v2.20.1): its connection bar, rejoin with your own role, "Continue without
  offline players", suspense reveals, Play again, stats, valid / invalid.
- **Nobody can sign in on the live server yet:** Resend (email codes) and the Google OAuth clients are still to set up
  on Alhassan's side.

### Gaps found, by risk to a release

| # | Gap | Where | What a player would see |
| --- | --- | --- | --- |
| G1 | **Two messages at the same moment can overwrite each other.** The room reads its state, then waits for D1 or for another Durable Object (`setRoom`, `saveGame`) before saving. Cloudflare lets the next message run during that wait, so it starts from the old state and the last save wins. | `server/src/room.ts`: `fetch`, `commit`, `drop` | Two friends join at once and one disappears from the lobby. The last vote and another action race, and the game is saved twice or an action is lost. |
| G2 | **A phone that silently loses signal still counts as online.** The server only learns of a drop when the connection closes, which can take minutes on mobile data. | `room.ts` `online()` | The host's controls stay with a dead phone. "Continue" refuses to skip the frozen player. The game freezes. |
| G3 | **A phone that reconnects misses what happened meanwhile.** Narration events are sent once, and a reconnecting phone gets only the current state. | `room.ts` `broadcast` | The morning result or verdict is never announced on that phone. Its suspense reveal shows nothing or the wrong thing. |
| G4 | **Messages carry no order number.** A phone can't tell whether it missed or double-applied an update. | protocol `RoomOut` | Rare stale screens after a reconnect, with nothing to detect them. |
| G5 | **Every keep-alive "ping" wakes the room.** That counts against the free tier's Durable Object requests (100,000 a day). | `webSocketMessage` | Nothing, until the free limit is reached, then rooms fail until the daily reset. |
| G6 | **No saved-game format the server can check.** The Wi-Fi approval process (decided 2026-11-22) must replay a game. The test games for the future Dart engine need the same thing. | engine | Nothing yet. It blocks Wi-Fi history and engine parity. |
| G7 | **Two old-rule oddities are still undecided** (`packages/engine/QUIRKS.md`): a dead Detective still sees their last result; a tie between a Mafia target and "skip" is broken at random. | engine | A dead player sees information; the one-time skip can be spent by chance. |

## Sprint 1 scope: G1–G6 (G7 waits for your decision)
The goal: make the game state and the room reliable on the server **before** the Flutter app is built on top of it.
Everything here can be tested automatically today.

### S1-1 One change at a time per room (G1)
- AC1: Two players who join within the same millisecond both end up in the lobby. Tested with 10 sockets joining at once,
  repeated 20 times.
- AC2: A game-ending vote racing another action (chat, kick, a second vote) produces **exactly one** row in `games`.
- AC3: No room action is lost or applied to an old state. A test sends 50 mixed actions in parallel; the final state
  equals the same actions applied one after another.
- AC4: The existing 30 server tests still pass.

### S1-2 Dead connections are noticed (G2)
- AC1: Phones send a keep-alive every 10 s. A phone that sends nothing for **30 s** is shown offline to everyone within
  **40 s**, without anyone else having to act.
- AC2: When that phone held the host's controls, they move to the next connected player in join order (the phase 3 rule)
  in the same update.
- AC3: "Continue" can skip a player shown offline this way.
- AC4: When the phone comes back, it gets its seat and role back and is shown online within 2 s.

### S1-3 Reconnecting catches up (G3, G4)
- AC1: Every `room`, `view` and `events` message carries a revision number that only grows within a room.
- AC2: A phone reconnects with its last revision. The server sends the current room and view plus the events it missed
  (the last 200 are kept). If more than 200 were missed, it sends only the current view, flagged as "missed events".
- AC3: No event is delivered twice to a phone that reconnects with its revision.
- AC4: A test drops a player's socket during the night, plays to the morning, and reconnects it: that player receives
  the morning result events exactly once.

### S1-4 Repeating a tap is harmless (follow-up to G3)
- AC1: Sending the same night choice, vote or "ready" twice (a phone retries after a drop) changes nothing the second time
  and returns no error.
- AC2: A choice for an old night or vote (`day` / vote `id`) answers `stale`, never an overwrite. That's already in the
  engine; a test pins it.

### S1-5 Keep-alives cost nothing (G5)
- AC1: `ping` → `pong` is answered by Cloudflare's automatic reply and doesn't wake the room. A test checks that the
  room's message handler isn't called for pings.
- AC2: S1-2's liveness check still works (it reads the last automatic-reply time).
- AC3: An estimate in the server README: Durable Object requests for one 10-player, 30-minute game, against the free
  daily limit.

### S1-6 A saved-game format the server can replay (G6)
- AC1: A versioned record (`format: 1`): the setup, the dealt roles, every action in order with its time. The engine
  produces it for every game.
- AC2: `replay(record)` rebuilds the exact final state and events. All 1,000 random games and all scenario tests
  replay identically.
- AC3: An edited record (a changed role, a removed or illegal action, a changed winner) is refused with a reason.
- AC4: The record files become the shared test games the future Dart engine must pass (assumption: two copies of the
  engine, as recommended; your answer to that is still open).
- AC5: Online games save this record too: one new nullable column through migration `0003`, with its rollback. Nothing
  already stored changes.

## Not in Sprint 1 (proposed order)
- **Sprint 2:** Flutter shell (EN/AR, RTL, `com.mafiadealer.game`), tools on the laptop, APK / AAB built in CI, the
  Dart engine passing S1-6's shared games, offline play (no account, no history).
- **Sprint 3:** sign-in, profile, friends (needs Resend + the Google OAuth clients from you).
- **Sprint 4:** online rooms in the app: connection bar, reconnect using S1-3, suspense reveals, chat.
- **Sprint 5:** Wi-Fi play, Wi-Fi history on the phone, the approval process (automatic rules, all players signed in,
  requests kept raw and versioned, limits in a D1 settings row).
- **Sprint 6:** push, Play updates, app links, Play readiness (privacy policy, account deletion page, data-safety form,
  closed test with 12 testers).
- **Groups:** waiting for your prompt.

## How QA will test this sprint
Playwright doesn't apply yet: there's no UI. The tests are vitest inside the Workers runtime (real Durable Objects, real
local D1, real WebSockets) and node tests for the engine. Phone screen sizes are tested from Sprint 2, in Flutter
widget and integration tests.

## Decisions needed before or during the sprint
1. Sign-off on S1-1 to S1-6 (or cut / add items).
2. G7: fix or keep the two oddities?
3. The 30 s / 40 s liveness numbers (S1-2): OK, or different?
