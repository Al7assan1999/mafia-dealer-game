# Sprint 6 PRD: Wi-Fi / Hotspot play

Status: **signed off and built 2026-11-23** (results: `docs/sprint-6-report.md`). Not committed.

## [BA] Audit

### A. The player's view today
- Home offers **Offline** (one phone) and **Online** (everyone on their phone, through the internet). There's **no way
  to play on separate phones without internet**: in a café without Wi-Fi, on a trip, or when mobile data is weak.
  The old app's third mode, "Wi-Fi / Hotspot", is the one players lose by moving to the new app.
- The online screens (lobby, every game phase, chat, the connection bar, catch-up after a drop) were walked through
  in Sprint 5 and work well. **A Wi-Fi player should get exactly those screens.** Learning a second set would be
  friction.
- In one room, the online default "every phone narrates" would mean six phones talking at once. Wi-Fi is always the
  same room: **the host's phone should be the narrator, and the others quiet by default.**

### B. What the old app did (v2.0–v2.20, confirmed on real phones)
- **The host phone was the server:** an HTTP server on port 8765; players polled every 0.7 s.
- **Discovery:** the joining phone scanned its subnet for port 8765, which was fast on hotspots and home routers,
  with **manual address entry** as a fallback.
- **Keeping the host alive:** a foreground service (`connectedDevice`) with a partial wake lock and a Wi-Fi lock
  while hosting, so the screen can turn off.
- **Recovering from problems:**
  - the host's room survived the app being killed ("Resume hosted game");
  - players rejoined by themselves;
  - a player who lost the host rescanned for it by name (the host's address changed).
- **v2.20 host takeover:** if the host phone vanished, a chosen successor took over with a hidden backup of the game.
- Players didn't need accounts.

### C. Decisions already made (2026-11-22)
- **Offline and Wi-Fi need no server and no account.**
- **A Wi-Fi game with a guest** (not signed in) is never logged online.
- **Wi-Fi history is kept apart from online history**; whether it lives on the phones was "we'll see".
- **Adding a Wi-Fi game to online history** is a formal request judged by **automatic rules**:
  - the server replays the record;
  - plus player count, a believable length, a daily limit and no duplicates;
  - each player confirms;
  - requests are kept raw and versioned; limits live in a D1 settings row; migrations only add.

### D. Size
Wi-Fi play alone is the largest piece of work so far:
- a server running on the host phone;
- the room's rules ported to Dart;
- discovery;
- a native keep-alive service;
- resume after the app is killed.

The approval process is a second, separate system (server rules, a request queue, confirmations in the bell).
**[BA] recommends two sprints:** this one for Wi-Fi play, the next for the approval process. That keeps each one
fully testable and reviewable.

## Scope (Sprint 6 = Wi-Fi play)

### S6-1 The host phone runs the room
- AC1: **Home gets a third button, "Wi-Fi / Hotspot"** ("Same Wi-Fi or a phone hotspot. No internet needed."):
  Host a room, or Join.
- AC2: **The host phone runs a local room server** speaking **the same messages as the online room** (`room`,
  `view`, `events` with `rev`, catch-up, `missed`, chat, buzz / ping). That way every phone, host included, uses the
  online screens unchanged.
- AC3: **The room's rules are ported to Dart** (the `Room` Durable Object's behavior) on top of the Dart engine:
  - lobby, setup, deal / ready / start;
  - the host's controls passing in join order, Continue, kick;
  - Play again, back to lobby;
  - chat with its limits and out-player rules;
  - repeats ignored, silent players marked offline after 30 s.
  
  The online room's widget tests are reused against the local server.
- AC4: **No account needed.** A guest joins with a name. A signed-in player joins with their profile (name, avatar),
  which the host records for the next sprint's approval process.
- AC5: Narration: **the host phone narrates; the other phones start with "This phone narrates" off.** Anyone can
  switch it on.

### S6-2 Finding the room
- AC1: **Join** lists the rooms found on the network within a few seconds: a scan of the local subnet, like the old
  app (works on a phone hotspot, another phone's hotspot, and a home router). Each entry shows the host's name and
  the player count.
- AC2: **Manual address** as a fallback (the host's screen shows its address, e.g. `192.168.43.1`).
- AC3: Clear messages for "no Wi-Fi", "nothing found" (with tips: same network, host still open), and a room that's
  full or already playing.

### S6-3 Staying alive
- AC1: **While hosting:** a foreground service (a notification "Hosting a Mafia Dealer room"), a partial wake lock and
  a Wi-Fi lock, so the room keeps running with the screen off or the app in the background. Android 14's rules for
  foreground services are followed (the type and permissions declared).
- AC2: **The host's app killed or the phone restarted mid-game:** "Resume hosting room 123456" restores the room and
  game from the phone (the game's record + the room). The players' phones reconnect by themselves and catch up.
- AC3: **A player's phone that loses the host** keeps trying the last address, then rescans the network for the same
  room. Once found, it rejoins in its seat.
- AC4: **Host takeover** (the old v2.20 successor) is **not** in this sprint: if the host phone is gone for good, that
  game ends. *Decision 3.*

### S6-4 Wi-Fi history on the phone
- AC1: When a Wi-Fi game ends, **every phone that played it saves it** (the record, names, my seat, when), including
  games with guests.
- AC2: **History has two tabs: Online / Wi-Fi.** Wi-Fi games open the same detail page (roles, what happened). Up to
  100 games; the oldest drop off.
- AC3: These stay on the phone, the agreed exception to "data in D1", until the approval process (next sprint) can
  add the fully signed-in ones to online history.

### S6-5 Small [BA] notes carried over from Sprint 5
- AC1: Home shows "How to play" once (the footer link hides while the first-launch offer is shown).
- AC2: The report dialog has no reason preselected; "Send report" waits for a choice.
- AC3: 🖕 out of the reaction set? *Decision 4* (the slot is replaced, so existing reactions keep their place).

## Not in Sprint 6
- **The approval process** (Sprint 7): server rules, the request queue, confirmations in the bell.
- **Push notifications and Play readiness** (Sprint 8).
- **Groups** (your prompt).

## How [QA] will verify
- **Dart unit tests for the local room:** the online room's server test cases ported (lobby, a full game, host
  hand-over, kick, Continue, catch-up with `rev`, `missed`, repeats, silent players, chat rules).
- **Widget tests:** the existing online widget tests run against the local server through a loopback socket. Plus:
  join by list and by address, "nothing found", host resume after a kill, the history tabs.
- **Emulator in CI:** the app hosts a Wi-Fi room on the emulator; scripted players connect over its local address and
  play a whole game. The host app is restarted mid-game and resumes; the players catch up.
- **The [QA] UX pass:** screenshots of every new screen (Wi-Fi home, host screen with its address, the join list,
  manual entry, "nothing found", resume, history tabs) in English and Arabic.
- **Your playtest** (the part no emulator can prove): real phones on a hotspot, a home router, and a third phone's
  hotspot; screen off on the host for a few minutes; the host app swiped away and resumed.

## Decisions needed
1. **Split:** Wi-Fi play now and the approval process in Sprint 7 (recommended), or both in one sprint?
2. **Native keep-alive:** a small Kotlin plugin of our own for the foreground service + Wi-Fi lock (recommended:
   exactly what the old app proved works). Or a package that has no Wi-Fi lock.
3. **Host takeover** left out this sprint (recommended), or ported now (the old v2.20 successor with a game backup)?
4. **🖕 reaction:** replace it (recommended for a public Play listing) or keep it?
5. **Your Sprint 4 / 5 playtest notes:** add them here before we start?
