# Sprint 11 Release Report: the two-phone playtest notes (R1–R12)

2026-11-23. Built against `docs/sprint-11-prd.md`, which you approved in advance. Run as the three personas. **Not
committed, not deployed.**

## [Developer] What changed, per note
- **R1 chat on Home** (`online.dart` `RoomChatButton`, `drawer.dart`, `main.dart`):
  - the minimized room's chat button sits **under the friends tab**, on the same edge, with the unread count;
  - the red bar is back to "back to the room" only;
  - a signed-out guest in a minimized Wi-Fi room still gets the chat button.
- **R2 Settings overflowing the top:**
  - every tall sheet (Settings, the bell, Wi-Fi rules and the rest) now keeps clear of the status bar (`useSafeArea`);
  - the Settings rows all use one text size: the switch and link rows used to be a size bigger.
- **R3 a profile with no games** (`stats.dart`):
  - a whole page: a big avatar, name, @handle, status (online / in a room / in a game / offline, friends only),
    "Friends", the favourite role;
  - the action that applies: **Add friend**, "Friend request sent", **Accept**, **Invite** (into my lobby) or
    **Ask to join**;
  - the four stat tiles showing "–" and "No games yet · Their record starts with your first game together".
- **R4 old history import** (`legacy.ts`, `wrangler.jsonc`, `lib.ts`):
  - **the cause:** Cloudflare refuses a fetch from one Worker to another Worker on the same account's `workers.dev`
    (error 1042). The old relay answers fine from outside (checked: 200), so only our server couldn't reach it;
  - **the fix:** the server now reaches the old relay through a **service binding** (`OLD_RELAY` → `mafia-relay`).
    That's Cloudflare's supported Worker-to-Worker path. It's read only, and the old relay and `../mafia-dealer`
    aren't touched;
  - local dev, which has no binding, still uses the URL.
- **R5 the swipe** (`chat.dart` `SwipeReply`):
  - the message follows the finger (at most 72 px), and a reply arrow fades in behind it;
  - the arrow turns red with a tick at 56 px; letting go there replies;
  - the bubble springs back either way;
  - both directions, both languages.
- **R6 the test notification:**
  - **the cause:** Android doesn't show a push while the app is open, and you press the button with the app open.
    The push reached the app, which ignored it;
  - the app now catches pushes that arrive while it's open (`PushService.received`);
  - the row reads "Sent. Waiting…", then **"Arrived on this phone ✓"**;
  - after 15 s with nothing: "Nothing arrived… check that notifications are allowed";
  - the server also says when it can't send at all (no Firebase key), and the row then says so instead of blaming
    the phone.
- **R7 buzz and ping, as in the old app:**
  - **lobby, player:** a "Buzz the host" button → "Buzz sent". At the host's limit it's replaced by "The host muted
    your buzzes."
  - **lobby, host:** "Ping everyone" on the player list's title row → "Everyone was pinged".
  - **receiving:** a double vibration (`vibrate` in `MainActivity.kt`, permission `VIBRATE`), the hit sound (even
    with narration off on that phone), a red flash, and "X buzzed you" / "The host pinged you!". This also works
    **while minimized on Home**;
  - Wi-Fi rooms too; the in-game icons stay.
- **R9 builds** (`ci.yml`, `release.yml`, `update.dart`):
  - every CI run uploads **two APKs**: `…-debug.apk` (as before) and **`…-release-arm64.apk`** (about 20–25 MB,
    full speed);
  - a Release ships **one APK per processor** (`-arm64-v8a`, `-armeabi-v7a`, `-x86_64`);
  - **the processor check:** the app picks the file for its own processor, using Dart's own `Abi`, so no plugin;
  - arm64 is uploaded first, alone, so phones still on 0.3.0 (which take the first APK) get the arm64 file.
- **QA's own fixes:** the kick dialog's text, "1 players" as a proper plural (EN/AR), and Ping moved onto the title
  row (it had a whole empty row to itself).

## [QA] Results
- **Server 70/70** (+1: the import goes through the binding). Typecheck clean.
- **App 128/128.** New tests in `test/sprint11_test.dart`:
  - R1: the chat button sits under the tab, not on the bar;
  - R3: the friend and stranger profiles;
  - R5: the bubble moves; a short drag springs back without replying, a long one replies;
  - R6: arrived / nothing within 15 s;
  - R7: the player's buzz and the muted state, the host's ping, the flash;
  - R9: the APK picker for each processor and for old releases.
- **Analyzer clean.**
- The emulator integration suite runs on GitHub CI only.

### Emulator session (profile build, `qa34`, the app plus a scripted second player against the local worker)
| Note | Tried for real | Result |
| --- | --- | --- |
| R1 | yes | Chat button with "1" under the friends tab, none on the red bar; it opens the room chat |
| R2 | yes | Settings starts below the clock |
| R3 | yes | Dareer's page: avatar, @handle, Offline, Friends, empty tiles, "No games yet" |
| R4 | **no** | It can only be proven on the deployed server. Covered by a server test of the binding. |
| R5 | yes | Mid-drag the bubble is moved, with a red arrow; let go, and the reply bar shows the message. A short drag springs back. |
| R6 | partly | The phone registered and the app waited. The local worker has no Firebase key, so nothing arrived. The real push needs the deployed server. |
| R7 | yes | The player's buzz reached the host: "Dareer… buzzed you". The host's ping reached the player (`{"t":"ping"}`). After 3 buzzes: "(muted)". |

**QA↔Dev:**
- QA found the kick dialog's outdated text, "1 players", the Ping row wasting a line and the uneven Settings text.
  Dev fixed all four in this sprint.
- QA asked why the local test notification said "Nothing arrived" when the phone was fine. Dev added the server's
  `canSend`, so a missing key isn't blamed on the phone.

**What no test here proves (only you and your friends can):** the vibration's strength on a real phone; sound;
smoothness on your phone with the release APK; a real push with the app open and closed; the import with a real old
group code after deployment.

## Answers to your other notes

### R8: where are the messages between players kept?
- **On the server only, in the room itself** (the room's Durable Object storage), never in D1 and never written to a
  phone's storage.
- **How long:**
  - the last **50 per conversation** (Everyone, and each 1:1);
  - all of it is **deleted with the room**, when the host closes it or after **12 hours** with nobody connected.
- **On the phone:** only in memory while you're in the room (also while minimized). Leave the room or close the app
  and it's gone from the phone. Coming back into the same room loads it again from the server.
- **A 1:1 message** is sent only to its two players; the server doesn't show it to anyone else.
- **Wi-Fi rooms:** kept on the host phone, inside the room's "Resume hosting" snapshot, until the host closes the
  room. No server is involved.

### R10: is QA doing a good job?
**No, not well enough, and the reason is clear.** R2, R4, R6 and R7 all passed every test because:
- **QA tested against fakes, not the real world.** The fake server answered the import; the fake push "arrived".
  Real Cloudflare (Worker to Worker) and real Android (no push shown while the app is open) behave differently, and
  nothing tried them.
- **The widget screenshots have no status bar**, so a sheet running under the clock can't show up in them.
- **Old-app parity was checked per feature, not per screen.** Buzz existed, but not where the old app had it (the
  lobby), so it counted as done.
- **Sprint 10's emulator session hadn't been run yet** when you tested.

What changes, written into `docs/team-workflow.md` as the QA checklist:
- anything that talks to the outside world is tried for real at least once;
- screens are checked at real phone insets on the emulator;
- old-app parity is checked per screen;
- social features are tried app-to-app with a scripted second player (done this sprint: `qa-bot`);
- feel is judged only on compiled builds;
- the report says what was real and what was fake.

What QA needs from you:
- **your OK to deploy before the report**, so R4 and R6 can be tried on the real server. Right now QA can't reach
  production on its own: wrangler isn't signed in here, and deploys go only through GitHub when you ask;
- and, when convenient, one friend's phone in each playtest.

### R11: Cloudflare usage
- **Real numbers aren't readable from here:** wrangler isn't signed in on this machine, and the deploy token lives
  only in GitHub.
- **Where to look:** the Cloudflare dashboard →
  - Workers & Pages → `mafia-dealer-game` → **Metrics** (requests, CPU);
  - **Durable Objects** (requests, duration);
  - Storage & Databases → D1 → `mafia-dealer-game` → **Metrics** (rows read / written).
- **The free plan per day:** Workers 100,000 requests; Durable Objects 100,000 requests (incoming WebSocket messages
  count 20 to 1) and 13,000 GB-s; D1 5 million rows read, 100,000 rows written, 5 GB. Since 2026-09-01, D1 queries
  fail past the daily limits instead of slowing down.
- **My estimate for your group** (not measured):

  | Item | Per busy evening (10 phones, 3 games) | Share of the free day |
  | --- | --- | --- |
  | Worker requests (opening the app, friends, bell, stats) | ~2,000 | ~2% |
  | Durable Object requests (room alarms about every 20 s, connects, game messages ÷ 20) | ~2,000–3,000 | ~3% |
  | D1 rows written (games, presence, notifications) | ~1,000 | ~1% |
  | D1 rows read | the one to watch, see below | |

- **The one to watch:** the stats boards read **every game and every seat row** each time someone opens them. Today
  that's tiny. At 1,000 games it's ~9,000 rows per opening, so 500 openings a day would be 4.5 M rows, near the
  5 M limit.
  - **When to act:** if the dashboard's D1 "rows read" passes ~1 M a day, the fix is to keep the board's totals in a
    table updated after each game.
  - **What it costs:** nothing to build now. Workers Paid ($5/month) also lifts the limits.

### R12: new roles
Recorded in `CONTEXT.md` → Later: Sniper, the Good Son, the Chief of Mafia (with 2+ Mafia), the Joker (wins with
either side; his biggest win is being voted out), and more. Nothing starts until the old app is fully revamped.

## [BA] Acceptance review
| Note | Verdict |
| --- | --- |
| R1 | Accepted (emulator) |
| R2 | Accepted (emulator) |
| R3 | Accepted (emulator) |
| R4 | **Accepted on the code and the test; to be confirmed after deployment** with one real old group code |
| R5 | Accepted (emulator) |
| R6 | **Accepted on the app; to be confirmed after deployment** with a real push (app open and closed) |
| R7 | Accepted (emulator, both directions). Vibration strength: your phone. |
| R8, R10, R11, R12 | Answered above |
| R9 | Accepted on the workflow files and the picker test. **Proven only on the next CI run / Release**, which waits for your go. |

**[BA] proposal:**
- **P1. A "Tried on the real server" step after every deploy:** QA signs in on the emulator against production and
  runs the test notification and one import. It needs your OK each time, as deploys do.

## Your next steps
1. Say "commit" (and "push" for CI). The emulator job should go green; the run then has the release-arm64 APK for
   your phone.
2. After the deploy: try the import with an old group code and the test notification with the app open and closed.
3. When you want a Release (Actions → Release), it ships per processor; 0.3.0 phones update to the arm64 file.
