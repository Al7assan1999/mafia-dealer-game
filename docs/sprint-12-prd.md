# Sprint 12 PRD: what the full QA cycle found (draft for your approval)

Status: **waiting for your sign-off.** Nothing is built until you approve or change the list.

Inputs, from [QA]:
- `docs/qa/qa-report.md`;
- `docs/qa/test-cases.md` (140 cases: 117 pass, 8 with findings, 7 human-only);
- `docs/qa/click-map.md` (176 controls, 0 crashes);
- the demo in `docs/qa/demo/`;
- your import screenshots.

## [BA] Review
**What the QA cycle shows:**
- The app is **stable**: no crash anywhere, every flow works on a real Android build, and the network and
  kill / reopen cases recover by themselves.
- **One thing is broken from a player's point of view:** the old-history import (Q1). You ran it and nothing came in.
- The rest is **friction a player feels but can work around:**
  - silent buttons (Q2, Q10);
  - wrong grammar (Q4);
  - a scary "Sign in" flash (Q5);
  - a banner in the way (Q6);
  - leftovers on screens (Q3, Q7, Q8);
  - one accessibility gap (Q9).

**What I challenge:**
- **Q1 is my own Sprint 8 design, and it was wrong for how you'll actually use it.** I made the import wait for a
  name list you'd send by chat, and in the meantime it **throws the games away**. You did exactly what the screen
  told you, and got "0 imported" with no reason. The fix shouldn't depend on you sending me anything:
  - the games are kept as soon as they're imported;
  - the app shows **the names it found** in them;
  - **you mark the real players in the app** (and later, each friend picks "Which one were you?", which already
    exists).
- **`docs/old-app-parity.md` is out of date:** it still lists stats, the welcome, minimize and the drawer as missing,
  though all of them are built. Since new roles wait until "the old app is fully revamped", we need a true list of
  what's left. I'll redo the parity check screen by screen in this sprint.

## Scope
### S12-1 Old history that's kept and fixable (Q1) · must
- AC1: An import **keeps every valid game** from the group, whether or not its names are known yet. A game is
  "waiting for names" until every name in it is marked real or test.
- AC2: The result line says what happened in plain words, for example: *"119 games found. 112 are waiting for you to
  confirm who the players are. 7 were empty or broken."* Importing the same code again only adds new games.
- AC3: **Old players** (admin only, in Settings):
  - every name found, with how many games it appears in;
  - per name: **Real player** (optionally linked to an @handle) or **Test**;
  - saving updates the stats at once.
  
  This replaces "send me the list". Being admin needs your Account ID in the `ADMIN_IDS` secret, which still isn't
  set: you copy it from Profile and set the secret yourself.
- AC4: A game where every name is marked counts in stats, as Sprint 8 decided. A game with a Test name is kept but
  never counted.
- AC5: History → Old app shows the imported games straight away, with "waiting for names" where it applies.
- AC6: The server change ships as a D1 migration with its rollback file; the raw games are never changed.

### S12-2 Joining by code (Q2, Q3) · must
- AC1: Join is disabled until 6 digits are typed; the field says "6 digits" while it's shorter.
- AC2: A code with no room is answered **on the Online screen** ("No room with that code"), without opening an empty
  room screen. A closed or full room, or "you were removed", is also said there.

### S12-3 Words and plurals (Q4) · must
- AC1: Every English count uses a proper plural: 1 vote / 2 votes, 1 player, 1 game, 1 win, the import line, the
  Wi-Fi list, "Needs 1 game".
- AC2: A test fails if a counted English string doesn't use a plural (so it can't come back).

### S12-4 Cold start keeps you signed in (Q5) · must
- AC1: Opening the app shows your saved account (avatar, @handle) and "Back to room" at once, from the phone's
  memory. The network only refreshes it. "Sign in" shows only when there's no saved session.

### S12-5 The live banner out of the way (Q6) · should
- AC1: It sits **below** the top bar instead of over its icons, and can be swiped away.
- AC2: It lasts 6 s, or until it's swiped or tapped; the item stays in the bell.

### S12-6 Small polish (Q3, Q7, Q8, Q9, Q10) · should
- AC1: A closed room's screen shows only the message and Home.
- AC2: The friends tab never covers the room-code card (it starts below it).
- AC3: TalkBack can open the role card ("double-tap and hold to see your role").
- AC4: Tapping a chat message opens the same menu as a long press (Reply, React, Edit, Report); Send is dimmed while
  the box is empty.

### S12-7 The true parity list (BA) · must
- AC1: `docs/old-app-parity.md` is rewritten from both apps, screen by screen, with each item ✅ / ❌ / ➖. What's
  still ❌ becomes the "revamp complete" list for you to approve. After that, the new roles can start.

## [BA] proposals (yours to accept or drop)
- **P1. The click map as a CI gate:** the tap-everything tool runs on every push and fails the build if any control
  crashes. That keeps today's "0 crashes" true every day.
- **P2. "Tried on the real server" after each deploy:** QA signs in on the emulator against production (a QA
  account) and runs the import and a test notification. That's what would have caught Q1 before you did. It needs
  your OK to create one QA account on production.
- **P3. Room status before joining:** when a friend's room shows in the drawer, also show "playing · 5/8" or
  "lobby · 3 players", so nobody asks to join a game already running (the old app greyed these out).

## Not in Sprint 12
Groups (your prompt), the new roles (after S12-7), Google Play.

## How [QA] will verify
- **S12-1:** server tests (kept, re-import adds only new games, marking recounts, test names never count) plus your
  real code on production after the deploy.
- **S12-2 to S12-6:** widget tests, plus the click map rerun (no ❓ left except the expected ones), plus the emulator.
- **S12-3:** the new plural test.
- **S12-7:** you read the list.
