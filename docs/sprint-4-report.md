# Sprint 4 Release Report: online rooms in the app

2026-11-22. Built against `docs/sprint-4-prd.md` (signed off the same day with the recommended answers). **Not
committed yet.** On the next push CI runs the new emulator test: a whole online game against a local Worker.

## Result: green locally
- **Server:** **43/43** vitest. New: `/v1/me` says which room I'm in, through lobby, game and close.
- **App:** `flutter analyze` clean. **42/42 widget tests:** 20 game + 11 account + **11 new online tests** against a
  scripted room server.
- **New emulator test** (`integration_test/online_test.dart`, runs in CI only):
  - the app creates a room and hosts a whole game with three scripted players;
  - one of them joins through a friend invite;
  - mid-night the app's socket is cut and comes back in the same seat, still in the night;
  - the finished game then appears in History.
- **Done at your request in this sprint:**
  - **Launcher icon:** your old pick "Fedora over the town", as an adaptive icon plus the classic sizes.
  - **APK name:** CI now publishes `MafiaDealer-PartyGame-<version>-b<build>-debug.apk`, under an artifact of the same
    name. The file inside the build folder stays `app-debug.apk`; Flutter's tooling requires that name.

## Against the acceptance criteria

| AC | Status | Evidence / notes |
| --- | --- | --- |
| S4-1 `room` in `/v1/me` | ✅ | Server test: lobby → game → null after close. |
| S4-2 AC1 create / join | ✅ | Online screen: create, or a 6-digit code. `no_room` / `started` / `room_full` / `kicked` have messages (tested: `no_room`). Signed out, it leads to sign-in. |
| S4-2 AC2 share / copy | ✅ written | Share sheet and clipboard (not testable in widget tests). |
| S4-2 AC3 "Back to room" | ✅ | Home shows it from `/v1/me` (cached for offline starts). |
| S4-2 AC4 leave asks | ✅ | Back and the leave button ask first; leaving hands on the host controls (server). |
| S4-3 AC1 members | ✅ | Tested: list, crown, "(you)". Online dots, ready and muted marks are shown. |
| S4-3 AC2 host edits roles / rules | ✅ | The offline setup's editors, shared (refactor) and read-only for players. |
| S4-3 AC3 deal, hold, ready, start | ✅ | The same role card as offline (refactor). Ready count; the host's "Start now". |
| S4-3 AC4 invites, ask to join, let in | ✅ | The host's invite sheet. Friends in an open lobby show "Ask to join"; the bell shows invites (tap = join), join requests ("Let in") and let-ins. The emulator test checks the invite arriving. |
| S4-4 AC1 own view only | ✅ | Every phase screen reads the server's view for my seat (tested: night, vote, waiting, dead view). |
| S4-4 AC2 per-phone suspense | ✅ | Tested with the narrator off: held, then shown on the fallback timer. With the narrator on, it opens when the name clip starts. |
| S4-4 AC3 host controls | ✅ | Tested: timer, secret vote, Continue (only with someone offline), host-only. Also: next night, start day, kick (asks first), unmute, back to lobby, Play again, close, valid / invalid. |
| S4-4 AC4 buzz / ping | ✅ | Buttons for player / host; a toast and vibration when one arrives (tested: the buzz button for players). |
| S4-4 AC5 history | ✅ | A list of my online games (who won, my role, valid) and a detail page (roles, what happened). The host marks valid / invalid there too. |
| S4-5 AC1 connection bar | ✅ | Tested: nothing on a normal join; red after 3 s down; green on return for 2 s; amber when weak (no pong within 1.2 s); amber "P2's connection is lost". |
| S4-5 AC2 reconnect + catch-up | ✅ | Tested: reconnects with `?rev=<last>`; the missed morning is narrated and shown once; `missed` = current view only, no narration. |
| S4-5 AC3 newest rev; taps resent | ✅ | Tested: an older room / view is ignored; a choice tapped during a drop goes out exactly once after reconnecting. |
| S4-5 AC4 killed mid-game | ✅ | Reopening shows "Back to room"; joining again puts me in my seat (server rule). The emulator test covers the drop. |
| S4-5 AC5 background | ✅ written | The socket closes in the background and reconnects in the foreground (lifecycle). |

## Decisions I made while building
- **The amber bar for a lost player:** the server moves the host controls to the next online player at once, so
  the old "host lost" warning would never show. The bar instead names the first seated player who's offline during a
  game ("Sami's connection is lost"), which is what the table needs to know.
- **Timers use the phone's clock** against the server's end time. A phone whose clock is off by a few seconds shows
  the timer off by that much. Room for a server-time sync later if it matters.

## Caveats for your playtest
1. **The real thing:** an online game with friends on different networks, including one phone going into a tunnel,
   or airplane mode for 20 s.
2. **Narration in one living room:** switch "This phone narrates" (speaker button in the room's top bar) off on all
   phones but one.
3. **Not in this sprint:** room chat (Sprint 5), push for invites while the app is closed (Sprint 7).
