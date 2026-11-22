# Sprint 4 PRD: online rooms in the app

Status: **signed off and built 2026-11-22** (results: `docs/sprint-4-report.md`). Not committed.

## Audit
- **The server has online rooms already** (phase 3, hardened in Sprint 1):
  - create a room (6-digit code); join by its socket;
  - a lobby with members, ready marks and the host's setup;
  - deal, then night choices and votes on each player's own phone, judged by the server;
  - host controls that pass in join order when the host is offline; "Continue" past offline players;
  - kick, buzz (with a limit), ping;
  - Play again, back to the lobby, close; mark the game valid / invalid;
  - per-seat views, events for narration, `rev` + catch-up on reconnect, silent sockets closed after 30 s;
  - invites, join requests and "let in" through the bell; finished games saved with their record.
- **The app has none of it:** offline play, accounts and friends only (Sprints 2–3).
- **The old app** had all of this. Players knew it by:
  - the room code to share;
  - the lobby list with online dots and crowns;
  - **the connection bar**: red "Connection lost · reconnecting…", amber "Weak connection" or "X's connection is
    lost", green "Connected again";
  - roles held to see;
  - the suspense reveal, sounds;
  - the host's controls: deal, start, day, timer, vote, next night, continue, kick;
  - buzz and ping;
  - Play again;
  - chat (Everyone + 1:1, reactions, replies, mentions, edits).
- **Gaps found in the server:**
  1. After a reinstall or on a new phone, the app can't tell it was in a room: `GET /v1/me` doesn't say so (the
     database knows: `users.room_code`).
  2. Narration: every phone gets the same `events`, so in one living room six phones would all narrate at once. The
     old app narrated on the host phone only, because everyone sat at the same table.

## Scope

### S4-1 Server
- AC1: `GET /v1/me` also returns `room: { code, status } | null`. A tested change; nothing stored changes.

### S4-2 Into a room
- AC1: Home → **Online**: "Create a room" (`POST /v1/rooms`) or "Join with a code" (6 digits; `no_room`, `started`,
  `room_full` and `kicked` each have a clear message). Signed out, Online leads to sign-in first.
- AC2: Room code shown big, with **Share** (Android's share sheet) and **Copy**.
- AC3: Opening the app while in a room (from `GET /v1/me`, or the code the phone remembers) offers "Back to room 123456".
- AC4: Leaving asks first. A host who leaves hands the controls on for good (server rule).

### S4-3 The lobby
- AC1: Members in join order: avatar, name, @handle, online dot, crown for whoever has the host controls, ready mark,
  muted mark.
- AC2: The host edits roles, rules and the buzz limit with the offline setup's widgets and limits; everyone sees
  them live.
- AC3: The host deals; each player holds to see their role (same card as offline). "Ready" on every phone; the host
  can start without waiting.
- AC4: Invite a friend from the friends list (online friends first). A friend in an open lobby gets "Ask to join"; the
  host gets the request in the bell and taps **Let in**.

### S4-4 The game on every phone
- AC1: Each phone shows only its own view (the server's): night options, votes (table vote = everyone sees the board
  live), dead / ghost view, the Detective's result.
- AC2: **Suspense reveal per phone** (phase 3 decision): the result arrives at once, but each phone holds it until
  its narrator says the name, with the offline fallback timers and "Reveal now".
- AC3: Host controls: start day, timer (start / pause / +1 min / reset), table vote or secret vote, next night,
  "Continue" past offline players (only when someone is offline), kick (asks first), back to lobby, Play again,
  close the room, mark the game valid / invalid at the end.
- AC4: Buzz (players → host, with the limit), ping (host → everyone), with sound and vibration.
- AC5: A finished game is saved by the server. "History" lists my online games (`GET /v1/games`) with a detail page:
  recap, roles, what happened. Offline games still aren't logged.

### S4-5 Connection resilience (Sprint 1's server work, used for real)
- AC1: **The connection bar,** as in the old app:
  - red "Connection lost · reconnecting…" after 3 s down;
  - amber "Weak connection" (answers over 1.2 s, or 2.5 s silent);
  - amber "<host>'s connection is lost" (my link is fine, the host's isn't);
  - green "Connected again" for 2 s.
  
  Nothing shows for a normal join or a short blip.
- AC2: Keep-alive `ping` every 10 s. Reconnect with backoff (1, 2, 4 … 10 s) and `?rev=<last seen>`. The missed
  events play once, in order (the morning result is narrated even after a drop). On `missed`, the phone just shows
  the current view, with no narration of old events.
- AC3: Messages with an older `rev` are ignored. A tap sent during a drop is resent after reconnecting; the server
  ignores repeats (Sprint 1).
- AC4: The app killed mid-game → reopened → back in the same seat, with the same role, at the current step.
- AC5: In the background the socket closes. Back in the foreground it reconnects and catches up. Other players see
  me offline after at most ~40 s (Sprint 1).

## Not in Sprint 4 (proposed)
- **Room chat** (Everyone / 1:1, reactions, replies, mentions, edits): the server has it; the app gets it in Sprint 5,
  so this sprint stays about the game itself.
- **Wi-Fi play** and the approval process (moves to Sprint 6).
- **Push notifications** (an invite when the app is closed) and Play readiness (Sprint 7).
- **Groups** (waiting for your prompt).

## How QA will test
- **Server:** vitest for `room` in `/v1/me`.
- **App widget tests with a fake room socket** (a scripted server):
  - lobby updates, the host controls appearing and moving;
  - every phase screen at 3 phone sizes in English and Arabic;
  - the connection bar's states with simulated delays and drops;
  - `rev` ordering and catch-up (the morning narrated once after a drop, no narration after `missed`);
  - a tap during a drop resent once;
  - double taps;
  - the per-phone suspense.
- **The emulator in CI against the local Worker:** the app plus three scripted players (sockets from the test) play
  a whole online game. Mid-night, the app's socket is cut and comes back: same seat, the morning narrated once. A
  friend invite is sent and let in. The finished game shows in History.
- **Your playtest:** a real online game with friends on different networks.

## Decisions needed
1. **Who narrates online?**
   - **every phone** (right for friends in different places), with a per-phone switch "This phone narrates";
   - or **only the host's phone** (right for one living room, like the old app).
   
   Recommended: **every phone, with the switch** (off on all but one phone when you sit together).
2. **Chat in Sprint 5** rather than now (recommended, to keep this sprint about the game). Or chat in Sprint 4 too.
3. **Joining by code:** any signed-in player with the code may join (the server's current rule), or friends of the
   host only? Recommended: **anyone with the code**, as before.
4. **The new sprint order:** 5 chat + online polish, 6 Wi-Fi + approval, 7 push + Play readiness. OK?
