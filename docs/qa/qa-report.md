# [QA] Full-cycle QA report, v0.4.0 (for the [BA] Sprint 12 review)

2026-11-23. Build: 0.4.0 (main f805252) and a **profile build** of the same code on the emulator (`qa34`, Pixel 6,
Android 14), against a local worker, with `qa-bot` as the second player. Everything lives in `docs/qa/`:
- `test-cases.md`: 120 cases and 20 edge cases, with results;
- `click-map.md`: every reachable control on 25 screens, tapped once from a fresh start;
- `demo/`: the screenshots and two videos for the BA (index below).

## 1. What was run
| Layer | Run | Result |
| --- | --- | --- |
| Server tests (real Worker code, local D1) | 70 | ✅ 70/70 |
| App widget tests (every screen against the fake server) | 128 | ✅ 128/128 |
| Emulator suite on CI (6 files: offline game, cold start, accounts + live friends, online game with a drop, chat + report, Wi-Fi host + resume, Wi-Fi approval) | 7 | ✅ 7/7 on 02f3e46 |
| **Click map** (`app/tool/click_map_test.dart`) | 176 controls / 25 screens | ✅ **0 crashes**. 19 "nothing visible" were checked one by one (§4). |
| Emulator session by hand | ~45 checks, 48 screenshots, 2 videos | 9 findings (§3) |
| **Your own report** (old-history import, from your phone) | 1 | ❌ Q1 |

**Test cases:** 117 pass · 8 pass with a finding or fail · 7 only provable by people (`test-cases.md`).

## 2. Proven for the first time
- **The old-history import reaches the old server in production.** Your screenshot shows "119 skipped", which means
  the server read the group. Before the service binding (R4) it couldn't connect at all.
- **The whole two-phone loop on Android, by hand:**
  - sign-up with an email code;
  - a friend request arriving live as the banner;
  - a full profile with no games;
  - create a room, the second player joins;
  - buzz → the host is told; Ping everyone → the player receives `ping`;
  - minimize → the chat button with its unread count under the friends tab → the chat;
  - the swipe moves the message and replies;
  - airplane mode → red bar → back by itself;
  - the app killed in the lobby → "Back to room" on Home;
  - close the room → the player is told "closed".
- **Robustness:** text at 130% holds, the app stays portrait when rotated, Arabic mirrors everything (the dual
  «لاعبان» is right), Neon renders, and Back asks before leaving a room.

## 3. Findings (severity for a player)
| # | Severity | What I saw | Where | Evidence |
| --- | --- | --- | --- | --- |
| **Q1** | **High** | **Import old history: all 119 games skipped, nothing kept.** The server only takes a game when *every* name is on the real-player list (`settings.old_players`). That list is empty (waiting for your names), so every game is dropped and none is stored. Importing later means fetching again. The line *"0 imported, 0 already here, 119 skipped (test or unknown players)"* doesn't say why or what to do. | Profile → Import old history | your screenshots; `server/src/legacy.ts`, `stats.ts oldNameOwners` |
| **Q2** | Medium | **Join with an empty or 5-digit code does nothing:** no message, no shake. | Online → Join | `demo/15`, `demo/16`; click map "Join" ❓ |
| **Q3** | Low | **A wrong code opens a whole empty "Room 123459" screen** just to say "No room with that code" (and Home takes you all the way Home, not back to Online). | Online → Join | `demo/17` |
| **Q4** | Medium | **English plurals:** "**1 votes**" on the verdict (and the live vote tallies); "{n} players" in the Wi-Fi list and the Wi-Fi request; "Needs {n} games"; the import line. Arabic plurals are right. | game, Wi-Fi, stats, import | `demo/48_verdict` |
| **Q5** | Medium | **Cold start shows "Sign in" for 3–5 s** before the saved account (and "Back to room") appears. A player can tap Sign in by mistake and think they were logged out. | Home after the app is killed | `demo/27` then `demo/31` |
| **Q6** | Low | **The live banner covers the top icons for 6 s** (Friends, bell, Settings). It caught real taps twice (both CI failures this week), and a player trying to open the bell meets the same thing. | every screen | CI logs; `demo/13` |
| **Q7** | Low | **A closed room's screen keeps chat, sound, leave and the friends tab**, none of which do anything there. | room after "Close room" | `demo/37` |
| **Q8** | Low | **The friends edge tab sits over the room-code card** (right in English, left in Arabic). | online lobby | `demo/20`, `demo/33` |
| **Q9** | Low (access) | **The role card's "press and hold" isn't an action for TalkBack**, so a player using the screen reader can't see their role. Found because Android's accessibility tree lists it as plain text. | offline deal | `demo/40` |
| **Q10** | Low | Chat: **tapping a message does nothing** (only long-press or swipe), and **Send with an empty box does nothing**, silently. Telegram opens the menu on a tap. | room chat | click map ❓ rows |

## 4. The 19 "nothing visible" taps in the click map, one by one
| Control | Verdict |
| --- | --- |
| Noir (already chosen), Lobby only (already chosen), Mine and Online (already selected), Friends / Requests tabs (already open) | Expected: tapping the selected one changes nothing |
| Notifications row, Photo, Share my username ×2, Share room code ×2 | Expected: they open Android's own screens, which the widget test can't show. **Not tapped on the emulator this time (⏭).** |
| The drawer's swipe area | Expected: it closes on a swipe, not a tap |
| Chat message rows ×4 | **Q10** |
| Send with an empty box | **Q10** |
| Join with an empty code | **Q2** |

## 5. What these tests can't prove (only you and your friends can)
- sound: the intro, buzz, ping; vibration strength;
- smoothness on a real phone with the release APK;
- **a real push** with the app open and closed (the local worker has no Firebase key);
- real Wi-Fi / hotspot between phones;
- Google sign-in on a real Google account;
- the import with real names, once Q1 is solved.

**Not run this time:** long and emoji names (X8); the host minimized while a player leaves (X13); the Android screens
behind Share / Photo / Notifications.

## 6. Demo for the [BA] (`docs/qa/demo/`)
**Videos:**
- `demo-sign-in-friends-room.mp4` (3 min): sign-up with a code → @username → a friend request as the banner →
  Online → empty / 5-digit / wrong codes (Q2, Q3) → create a room → the second player joins and buzzes → Ping
  everyone → minimize → chat from Home → airplane mode and back.
- `demo-offline-game-neon.mp4` (3 min): an offline game in Neon. Setup → six role cards (press and hold) → night
  turns → morning → secret ballot → the verdict ("1 votes", Q4).

**Screenshots, in order:**
| Range | What they show |
| --- | --- |
| `01`–`05` | The intro and first launch |
| `06` | Online while signed out |
| `07`–`08` | Settings (R2 fixed) |
| `10`–`12` | Sign-up |
| `13`–`14` | The banner |
| `15`–`17` | Join edge cases |
| `18`–`21` | Lobby, buzz, ping |
| `22`–`23` | Minimized + chat |
| `24`–`26` | Airplane mode |
| `27`, `31` | Cold start (Q5) |
| `28`–`30` | Rotation, large text |
| `32`–`36` | Arabic, the leave and close dialogs |
| `37` | Closed room (Q7) |
| `38`–`48` | Offline game in Neon |

The demo folder is 21 MB (mostly the two videos). Whether to commit it is your call; otherwise it stays local.

## 7. Handed to the [BA]
This report, `test-cases.md` and `click-map.md`. The click-map tool can rerun at any time
(`cd app && flutter test tool/click_map_test.dart`).
