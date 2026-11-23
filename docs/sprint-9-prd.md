# Sprint 9 PRD: the friends drawer, staying in a room from Home, Neon, and the old Settings back

Status: **built 2026-11-23** (results: `docs/sprint-9-report.md`), not committed. Signed off with his answers:
1. Noir stays the default.
2. Minimize in Wi-Fi rooms too.
3. Kick as in the old app, decided in Settings (old defaults: buzz limit 3, kick **lobby only**).
4. Bell history on the server.
5. All four [BA] proposals.

His instructions behind this sprint:
- "Try to match the missing points from the old app, like the floating drawer and the minimize option when in a room
  (so a player doesn't need to leave the room to go to the home screen)".
- "Neon back as a choice".
- The Sprint 9 line of `docs/old-app-parity.md`.

## [BA] Audit

Walked as a player on the real screens (`app/tool/screens_test.dart`, EN/AR, 360 px: Home signed in, Friends, the
online lobby, Settings, the bell, the Wi-Fi list) and on the emulator. Compared with the old app (`../mafia-dealer`,
read only: CONTEXT v2.9.1 drawer, v2.10 side column, v2.11–v2.13 friends and bell, v2.12 minimize, v2.17 invite from
Home and Back, v2.4 Settings).

### A. Leaving the lobby screen means leaving the room
- *Lobby screenshot:* the only ways out are Back (which asks to leave) and Close room / Leave. A player who wants to
  check a friend, the rules or their stats while everyone gathers has to leave and rejoin.
- **The old app (v2.12):**
  - **Minimize** in the lobby header: the room keeps running and you go Home;
  - every screen shows a bar on top, "Your room · 4 players" / "In Dareer's room", that takes you back;
  - when the host deals the roles, everyone minimized is **pulled back** with a buzz;
  - a kick or a closed room tells you on whatever screen you're on;
  - starting an offline game, hosting or joining another room while minimized asks "Leave this room?" first;
  - during a game nothing changes: no minimize.

### B. Friends are a screen away
- *Friends screenshot:* the Friends screen works (tabs, requests, status), but to invite someone from the lobby you go
  Lobby → Invite friends, and from Home → Friends → pick.
- **The old app (v2.9.1, v2.10, v2.13):** a **tab on the screen edge** (right; left in Arabic) with online friends'
  avatars, the count and a red dot for requests. It slides out over menus and lobbies (never during a game, never
  signed out) with:
  - requests (Accept / Decline);
  - friends online first, with status pills (online / in a room / in a game);
  - **Invite** in an online lobby, **Ask to join** for a friend in an open lobby, **In your room** for one already
    there;
  - "+" opens the Friends screen.
  
  The tab and the chat button formed one column you could **drag up and down**; the app remembered where you left it.

### C. Settings lost its host defaults and the look
- *Settings screenshot:* language, voices, notifications, updates.
- **The old Settings** also had:
  - **Look** (Neon / Noir);
  - **When you host**: the buzz limit and **kick: lobby only / any time**.
  
  In the new app each room starts from built-in values, and the host can kick at any moment, mid-game too, with no
  setting to stop that.

### D. Neon
The old app's default look:
- a deep violet-black background with soft pink and blue glows;
- glassy cards with rounded corners;
- a pink-to-orange gradient on primary buttons;
- the **Readex Pro** font (Arabic + Latin, already licensed with the old app, OFL);
- its own role colours (Mafia pink #ff4d7d, Doctor mint, Detective blue, Citizen amber);
- night / day / blood / glory backgrounds as gradients.

Only Noir exists today.

### E. Smaller old behaviours that are gone
- **Phone Back on Home closes the app at once.** The old app asked "Close Mafia Dealer?".
- **The bell forgets.** A handled invite or request disappears. The old bell kept handled items for 24 h with their
  result (Joined, Let in, Accepted, Declined, Dismissed, Expired).
- **Invite from Home.** The old app's Invite next to an online friend, while you weren't in a room, opened an online
  room and invited them in one tap.

### F. Notes carried from earlier audits
- Stats and History are small text links at the bottom of Home (Sprint 8 note).
- Two red buttons on Home when a Wi-Fi room can be resumed (Sprint 6 note).
- The Wi-Fi list offers rooms that are already playing, then refuses (Sprint 6 note).

## Scope

### S9-1 Minimize a room (lobby only)
- AC1: **A Minimize button in the lobby header** (online and Wi-Fi, host and players) goes Home; the room keeps running.
- AC2: **The room bar** on every screen outside the room:
  - "Your room · 4 players" (host) / "In Dareer's room · 4" (player), with the chat unread count;
  - a tap returns to the lobby;
  - the narrator and sounds stay quiet while minimized.
- AC3: **Pulled back when roles are dealt:** the lobby reopens on its own, with a buzz and the deal sound, from any
  screen.
- AC4: **Kicked or the room closed while minimized:** the bar goes and a message says so ("Dareer closed the room",
  "You were removed").
- AC5: **Starting something else while minimized** (Offline game, Host, Join, Wi-Fi) asks "Leave your room first?":
  Leave / Stay.
- AC6: During a game there's no Minimize (as before); Back still asks before leaving.

### S9-2 The friends drawer
- AC1: **An edge tab** (right; left in Arabic) on Home and in lobbies (never in a game, never signed out):
  - up to 3 online friends' avatars and the online count;
  - a red dot when there's a friend request.
  
  **Drag it up or down**; the spot is remembered. The room's chat button sits in the same column in lobbies.
- AC2: **Tap or swipe from the edge** to slide the drawer out over the screen:
  - **Requests** first (Accept / Decline);
  - then friends: **online first**, with status pills;
  - each friend's action:
    - **Invite** (I'm in an online lobby);
    - **In your room** (already in it);
    - **Ask to join** (they're in an open lobby);
    - **Invite** from Home (S9-5 AC3);
  - **+** opens the Friends screen.
- AC3: Back, a tap on the dimmed side or a swipe closes it.
- AC4: Live: presence and requests update as they happen (the hub).

### S9-3 Neon, as a choice
- AC1: **Settings → Look: Noir / Neon**, applied at once and remembered on the phone.
- AC2: Neon as listed in D:
  - colours and gradients;
  - glassy cards;
  - Readex Pro for Latin and Arabic;
  - Neon role colours;
  - night / day / blood / glory backgrounds.
  
  Every screen follows the theme. No screen hard-codes Noir any more.
- AC3: Noir stays exactly as it is.

### S9-4 Host defaults in Settings
- AC1: **When you host:**
  - **Buzz limit** (as the old app: mute a player after N buzzes);
  - **Kick: lobby only / any time.**
  
  New rooms you host start with these (online and Wi-Fi).
- AC2: "Lobby only" means the server and the Wi-Fi room refuse a mid-game kick, so the host can't remove a player by
  accident during a game. The lobby still allows it.

### S9-5 The small old behaviours
- AC1: **Phone Back on Home** asks "Close Mafia Dealer?" (Close / Stay). An open sheet closes first.
- AC2: **Bell history:** handled items stay 24 h, read-only, with their result:
  - Joined / Let in / Accepted / Declined / Dismissed / Expired;
  - "Clear" removes them;
  - the unread count is only what still needs an answer, plus new notes.
- AC3: **Invite from Home:** Invite next to an online friend while I'm in no room creates an online room and invites
  them in one tap. For an offline friend it's offered only from inside a room (old rule).

## [BA] proposals (all four accepted, now in scope)
- **P1. Home tidy-up:**
  - Stats and History as two visible tiles side by side, instead of small links at the bottom;
  - "Back to the Wi-Fi room" / "Resume" as one outlined card above the mode buttons, so only one red button stays.
  
  (Closes the Sprint 6 and 8 notes.)
- **P2. Grey out playing rooms** in the Wi-Fi list: "Playing · you can't join" unless this phone holds a seat there.
- **P3. A theme preview** in Settings: two small cards (Noir / Neon) showing the look before you tap.
- **P4. Drawer shortcut on the room bar:** a long-press on the minimized room bar opens the drawer with Invite ready,
  for the host gathering players.

## Not in Sprint 9
- The intro (Sprint 10, "same as before").
- Groups (your prompt).
- Google Play (last).
- Host takeover on Wi-Fi (left out in Sprint 6).

## How [QA] will verify
- **Server:**
  - kick mode: a mid-game kick refused under "lobby only", allowed in the lobby;
  - bell history: handled items kept 24 h with their result, the unread count, Clear;
  - invite from Home creates the room and the invite.
- **Widget tests:**
  - minimize / bar / pull-back on deal / kicked while minimized / "Leave your room first?";
  - the drawer: open, close, swipe, drag position kept, each friend action, requests, live updates;
  - Back on Home;
  - Look switch;
  - host defaults reaching a new room;
  - EN/AR.
- **UX pass:** every screen in **both themes and both languages** (the screens tool renders Noir and Neon).
- **Emulator exploratory session:**
  - minimize a real lobby and wander (Profile, Stats, Settings, the bell), get pulled back by a deal from a second
    scripted phone;
  - drag the drawer;
  - Back on Home;
  - airplane mode while minimized.
- **What only you can prove:** the feel of the drawer gesture, and Neon on a real screen.

## Decisions (answered above in Status)
1. **Default look:** Noir stays the default and Neon is the choice (recommended: the new app has always been Noir), or
   Neon as the default like the old app?
2. **Minimize in Wi-Fi rooms too** (recommended, as the old app), or online only?
3. **Kick default:** "any time" (today's behaviour, recommended) or "lobby only"?
4. **Bell history on the server** (recommended: it follows you to your other phone, and fits "data in D1"), or on the
   phone like the old app?
5. **[BA] proposals P1–P4:** which ones go in?
