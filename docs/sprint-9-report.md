# Sprint 9 Release Report: the friends drawer, staying in a room from Home, Neon, and the old Settings back

2026-11-23. Built against `docs/sprint-9-prd.md`, signed off with his answers:
- Noir stays the default;
- minimize in Wi-Fi rooms too;
- kick as in the old app, set in Settings (default: lobby only, buzz limit 3);
- bell history on the server;
- all four [BA] proposals.

Run as the three personas. **Not committed yet.**

## [Developer] What changed, per AC
- **S9-1 Minimize** (`online.dart`: `ActiveRoom`, `RoomBarFrame`, `leaveRoomFirst`):
  - a Home icon in the lobby bar (online and Wi-Fi, host and players);
  - the room's connection outlives its screen;
  - a red room bar on every screen: "Your room · 4 players" / "In Dareer's room · 4", with unread chat; tap to go back on the same connection;
  - dealing the roles pulls you back with a buzz and "Roles are being dealt";
  - a kick or a closed room while away is told on the current screen;
  - Offline game / Wi-Fi / Online / another room ask "Leave your room first?";
  - an invite into the same room just reopens it;
  - no minimize once a game runs;
  - a Wi-Fi host's server keeps running while minimized.
- **S9-2 Friends drawer** (`drawer.dart`):
  - the edge tab (right; left in Arabic): up to 3 online friends, the online count, a red dot for requests;
  - drag it up or down and the spot is kept; tap or swipe to open;
  - in the drawer: requests first (accept / decline), then friends online first with status, and per friend: **Invite** (my online lobby), **In your room**, **Ask to join** (their open lobby), **Invite from Home** (a new room, the invite sent once it exists);
  - "+" opens Friends; closes on Back, the dimmed side, or a swipe;
  - live through the hub;
  - on Home and in online lobbies (not in games, not in Wi-Fi rooms).
- **S9-3 Neon** (`ui.dart`):
  - the colours became a run-time palette, so every screen follows the look (248 fixed constants turned into theme values);
  - Neon:
    - violet-black backdrops with pink / blue glows (night / day / blood / glory gradients);
    - the pink-orange gradient button with a glow;
    - rounded glassy cards;
    - **Readex Pro** (downloaded with your OK from google/fonts, OFL licence in `assets/fonts`);
    - Neon role colours;
  - Settings → Look with two live previews (P3);
  - Noir unchanged and the default.
- **S9-4 Host defaults:**
  - Settings → When you host: buzz limit (0–20) and Kick: Lobby only / Any time; a room I host starts with them (sent once, before anyone is dealt in);
  - the server and the Wi-Fi room refuse a mid-game kick under "Lobby only": "Kicks are for the lobby only. Change it in Settings → When you host."
- **S9-5:**
  - phone Back on Home asks "Close Mafia Dealer?";
  - **bell history** (migration `0008`, + rollback):
    - answered items stay 24 h, read-only, with Joined / Let in / Accepted / Declined / Dismissed;
    - unanswered ones show Expired for a day after they lapse;
    - only what waits counts as unread;
    - Clear keeps what still waits;
    - accepting or declining from the Friends screen answers the bell item too;
    - Decline added in the bell;
  - Invite from Home (S9-2).
- **P1:** one red button on Home: Back to room / Resume hosting / Back to the Wi-Fi room are outlined; Stats and History became two tiles.
- **P2:** a Wi-Fi game in progress where you hold no seat is listed greyed: "Playing · you can't join".
- **P3:** theme previews.
- **P4:** a long-press on the room bar opens the drawer with Invite ready.

## [QA] Results
- **Server:** 67/67 (64 earlier, 3 new for bell history; two earlier tests updated: a mid-game kick is now refused by default, and an answered request now stays as "Let in"). Typecheck clean.
- **App:** analyzer clean. **108/108 widget tests** (96 earlier + 12 new):
  - minimize: bar, same connection, pull-back, kicked while away, leave first;
  - host defaults sent once;
  - drawer: tab, requests, Invite from Home, drag kept, left edge in Arabic;
  - Look switch and host settings;
  - Back on Home;
  - bell history;
  - Wi-Fi grey-out.
  
  One earlier Wi-Fi test was updated for the kick rule.
- **Engines:** unchanged (35 TypeScript + Dart).
- **UX pass:** every new screen rendered in **Noir and Neon, English and Arabic** (Home, Home tiles, drawer, Settings, host settings, lobby, a night screen).
- **Emulator session** (Pixel 6, Android 14, local Worker, three scripted phones):
  - signed in as Dareer and joined QaHost's room by code;
  - **minimized from the lobby**: the bar "In QaHost's room · 4" showed on Home and on Stats;
  - while I was on Stats the host dealt: **I was pulled back onto my role card within seconds**, and the Home icon was gone in the game;
  - after an app restart Home showed "Back to room" as an outlined button.

## [QA] → [Developer]: what QA found, and the fixes
| # | Found by | Finding | Fix |
| --- | --- | --- | --- |
| 1 | Server test | Bell: an expired item showed only if it was *created* within the last day, so a 7-day friend request vanished while a 30-min invite showed "Expired" | Expired items show for a day after they **lapse** |
| 2 | UX pass (Neon, 360 px) | "Kick players" squeezed into a vertical strip beside the switch; the row overflowed | Label above, the switch full width |
| 3 | UX pass | The friends tab covered the right edge of "Offline game" | It starts right under the top icons (the old app's v2.9.2 fix) |
| 4 | Emulator (a tall real screen) | Home's centred content moved the icon row down: the tab covered the **Settings gear** | Home starts at the top, so the icon row sits in the same place on every phone |
| 5 | Test harness | Neon text rendered as boxes in the screenshots (the harness didn't load Readex) | The harness loads it; the app always did |
| 6 | Screens tool | In Arabic the tool's "tap the dim side" hit the drawer (it opens from the left) | Taps the right side in Arabic |

## [BA] Acceptance review
| AC | Verdict | Evidence |
| --- | --- | --- |
| S9-1 AC1 Minimize in the lobby | ✅ | Emulator: Home icon in the lobby bar; widget test |
| S9-1 AC2 the room bar | ✅ | Emulator: "In QaHost's room · 4" on Home and Stats; tap → back, same connection (test) |
| S9-1 AC3 pulled back on the deal | ✅ | Emulator: from Stats to the role card within seconds; test with the note |
| S9-1 AC4 kicked / closed while away | ✅ | Widget test: bar gone, message shown |
| S9-1 AC5 leave first | ✅ | Widget test: asks, Leave sends the goodbye |
| S9-1 AC6 no minimize in a game | ✅ | Emulator and test |
| S9-2 AC1–AC4 drawer | ✅ | Screens EN/AR, Noir/Neon; tests: requests, Invite from Home, drag kept, Arabic left edge. **The feel of the swipe is for your phone.** |
| S9-3 AC1–AC3 Neon | ✅ | Screens of every new screen in Neon; Noir tests unchanged (96 earlier tests pass) |
| S9-4 AC1–AC2 host defaults, lobby-only kick | ✅ | Server + Wi-Fi room tests; setup sent once (test) |
| S9-5 AC1 Back on Home | ✅ | Test |
| S9-5 AC2 bell history | ✅ | 3 server tests + widget test |
| S9-5 AC3 Invite from Home | ✅ | The drawer's Invite with no room creates a room and invites once it exists (button tested; the invite after creation is covered by the room's own code) |
| P1–P4 | ✅ | Home screenshot (one red button, two tiles); Wi-Fi grey-out test; previews; long-press wired on the bar |

**[BA] notes for the next audit:**
- Home has two ways to Friends now: the top icon and the edge tab. The old app replaced the Home button with the drawer. Worth deciding if the top icon stays.
- In a Wi-Fi lobby there's no drawer (inviting online friends into a Wi-Fi room makes no sense). If players expect it, the drawer could show friends with "Not available on Wi-Fi".
- Neon was checked on screenshots and the emulator's Noir run. **Neon on a real screen is for your eyes.**

## Caveats for your playtest
1. **Minimize with real friends:**
   - join a friend's lobby, tap the Home icon, wander (Stats, Settings, the bell);
   - when they deal you should be pulled back with a buzz;
   - try it on Wi-Fi too.
2. **The drawer:** drag the tab, swipe it open, Invite a friend from Home (it makes a room and invites them).
3. **Neon:** Settings → Look → Neon; play a short offline game to see the night / day / blood / glory backdrops.
4. **Host settings:** set Kick to "Lobby only", try to kick mid-game (refused with a message), then "Any time".
5. **Back on Home** asks before closing; **the bell** keeps answered items for a day.
