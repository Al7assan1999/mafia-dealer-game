# Sprint 11 PRD: the two-phone playtest notes (R1–R12)

Status: **approved in advance** (2026-11-23: "I already approve it, go directly to implementation after setting the
plan"). Sprint 10's emulator QA session and report run alongside (`docs/sprint-10-report.md`).

His notes after v0.3.0 with two users, each traced in the code by [Developer] before this plan.

| # | His note | What we found | Fix |
| --- | --- | --- | --- |
| R1 | The chat should be on Home with the drawer, not on the top | N7 put the chat button on the red room bar at the top. The friends edge tab already has a slot under it for a room's button. | The chat button moves under the friends tab on Home (with the unread count); the red bar keeps "back to the room" only. Guests (Wi-Fi, signed out) get the chat button alone on the edge. |
| R2 | Settings overflows the top | Settings is a full-height sheet; Flutter drops the status-bar inset inside a sheet, so the title runs under the clock. Same for the bell, the Wi-Fi rules and two more sheets. | Every tall sheet keeps clear of the status bar (`useSafeArea`) and shows a drag handle. |
| R3 | A profile with no games looks empty | A player with no counted games got a name and "No games yet" on a blank page. | A real profile page in every case: big avatar, name, @handle, status (online / in a room / in a game), favourite role, friendship, the actions (Add friend / Invite / Ask to join), the four stat tiles with "–", and "No games together yet". |
| R4 | Import from the old app: "the old server didn't answer" | The old relay answers from outside (checked: 200). From inside our Worker it doesn't: **Cloudflare refuses a fetch from one Worker to another on the same account's workers.dev** (error 1042). Tests used a fake reader, so they never saw it. | A **service binding** to the old relay (`OLD_RELAY` → `mafia-relay`): Worker-to-Worker, read only, the old relay unchanged. Falls back to the public URL where there's no binding (local dev). |
| R5 | Swipe to reply works but the message doesn't move | Only the end of the swipe was read. | Telegram-style: the bubble follows the finger, a reply arrow fades in behind it, a tick at the threshold, it springs back and the reply opens. |
| R6 | The test notification button doesn't work | **Android never shows a push while the app is open**, and the button is pressed with the app open. FCM handed it to the app, which ignored it. | Pushes that arrive while the app is open are caught; the test one turns the Settings row into "Arrived on this phone ✓". If it doesn't arrive in 15 s: "Nothing arrived: check Android's notification permission". |
| R7 | Buzz and ping don't exist | They exist only as two small icons in the game's top bar. **The old app had them in the lobby:** a big "Buzz the host" button for players while they wait (with "Buzz sent" and "The host muted your buzzes"), "Ping everyone" next to the player list for the host, and a vibration + sound + flash on the receiving phone. | As the old app: "Buzz the host" in the lobby, "Ping everyone" by the member list, "Buzz sent" / muted notice, and the receiving phone vibrates, plays the hit sound and flashes. Wi-Fi rooms too. |
| R8 | Where are private messages kept? | Answered below; nothing to build. | – |
| R9 | Testers get a 200 MB debug APK; add the processor check | CI only uploads the debug APK (all processors + debug runtime). The GitHub Release is already a release build, but one 69 MB file for every processor. | CI uploads **both**: the debug APK and a release APK for arm64 (≈25 MB). Releases ship one APK per processor; the in-app updater picks the one for the phone's processor. |
| R10 | Is QA doing a good job? | Answered in the report: no, and why. | `docs/team-workflow.md` gains a QA checklist that would have caught R2, R4, R6, R7. |
| R11 | Cloudflare usage | Answered in the report with today's numbers and an estimate. | – |
| R12 | New roles (Sniper, Good son, Chief of Mafia, Joker…) | Not now: after the old app is fully revamped (his words). | Kept in `CONTEXT.md` → Later. |

## Acceptance criteria
- **R1:** on Home with a minimized room, the chat button with its unread count sits under the friends tab; tapping it
  opens that room's chat; the red bar has no chat icon. Signed out in a minimized Wi-Fi room the chat button still shows.
- **R2:** Settings, the bell and every other tall sheet start below the status bar on a 640 px phone and on a phone
  with a notch; the content scrolls inside.
- **R3:** a friend with no games: avatar, name, @handle, status, favourite role (if set), "Friends", Invite or Ask to
  join when it applies, four tiles showing "–", "No games together yet". A stranger: Add friend. Myself: no actions.
- **R4:** the import reaches the old relay in production through the binding; 404 for an unknown code still reads
  "No group with that code"; the old relay and `../mafia-dealer` are not changed.
- **R5:** dragging a message moves it (at most ~70 px), the arrow appears, letting go past ~56 px replies (with a tick);
  less springs back without replying; the list still scrolls vertically; both directions, both languages.
- **R6:** with the app open, a test notification that arrives shows "Arrived on this phone ✓" under the row; with the
  app closed Android shows it as before; nothing within 15 s shows the permission hint.
- **R7:** lobby, player: "Buzz the host" → "Buzz sent", the host's phone vibrates, sounds and flashes with "X buzzed
  you!"; at the limit "The host muted your buzzes" replaces the button; host: "Ping everyone" → every player's phone
  vibrates with "The host pinged you!". Same in Wi-Fi rooms. The in-game icons stay.
- **R9:** a CI run has two artifacts, `…-debug.apk` and `…-release-arm64.apk`; a Release has
  `…-arm64-v8a.apk`, `…-armeabi-v7a.apk`, `…-x86_64.apk`; an arm64 phone updates to the arm64 file; 0.3.0 phones (which
  take the first APK in the list) get arm64, which is listed first.

## Not in this sprint
Groups (his prompt), the old-player import list (his names), Google Play, new roles.

## How [QA] will verify
Widget tests for R1, R3, R5, R6 (fake push), R7; a server test for R4's binding path; the emulator suites; the
emulator session on `qa34` with a release build against a local worker (intro, sound, smoothness, test push, kick and
invite back, buzz / ping between the app and a scripted player).
