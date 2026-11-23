# [QA] Full-cycle test cases (v0.4.0)

Written 2026-11-23 for the Sprint 12 review. One line per case: what to do, what must happen, and how it's run. The
**Result** column is filled in by the run (`docs/qa/qa-report.md` has the details and the evidence).

**How:**
- **W**: widget test (the app's screens against a fake server; `app/test`);
- **S**: server test (the real Worker code in the Workers runtime; `server/test`);
- **E**: emulator test (the real app on Android with scripted players; `app/integration_test`, CI);
- **M**: run by hand on the emulator in this QA session (profile build, local worker, the `qa-bot` second player);
- **H**: only people on real phones and networks can prove it.

**Result:** ✅ pass · ❌ fail (see the report) · ⚠️ passes with a finding · ⏭ not run (why in the report).

## A. Install, first launch, updates
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| A1 | Fresh install, open | The intro plays: six scenes, captions type out, no Skip, Back does nothing | W, M | ✅ |
| A2 | Tap through the intro | Each tap moves on; the title waits; "Tap to start" → Home with How to play highlighted | W, M | ✅ |
| A3 | Update from an older build | No intro; "Updated to vX" with the release bullets once | W | ✅ |
| A4 | Second launch | No intro (unless Settings → Show the intro at start) | W | ✅ |
| A5 | Show the intro at start on → relaunch | Intro with Skip | W | ✅ |
| A6 | Watch the intro (Settings / How to play) | Plays with Skip; Back skips | W | ✅ |
| A7 | A newer GitHub Release exists | The update card with bullets; Update downloads with progress and hands the APK to Android | W | ✅ |
| A8 | Installs from this app not allowed yet | Android's "allow" page opens; coming back continues | W | ✅ |
| A9 | Download fails | The download page opens instead | W | ✅ |
| A10 | Phone's processor | The Release APK for that processor is chosen | W | ✅ |
| A11 | The "new version" push | Arrives on every phone in its language; tap opens the update card | H | ⏭ human |
| A12 | Phone Back on Home | Asks "Close Mafia Dealer?" | W | ✅ |

## B. Settings
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| B1 | Settings opens | Starts below the status bar, scrolls, all rows one text size | M | ✅ |
| B2 | Language EN ↔ AR | The whole app mirrors and stays after restart | W, M | ✅ |
| B3 | Narrator / sound sliders | Volume changes; 0 = silent | H | ⏭ human |
| B4 | Look: Noir / Neon | Switches at once everywhere, remembered | W, M | ✅ |
| B5 | Host defaults: buzz limit, kick rule | Kept; a room I host starts with them | W | ✅ |
| B6 | Send me a test notification (app open) | "Arrived on this phone ✓" | W, H | ⏭ human (needs Firebase on the real server) |
| B7 | Test notification, server without a key | "The server can't send…" (not blamed on the phone) | W, M | ✅ |
| B8 | Test notification, phone not registered | "This phone isn't registered…" | W | ✅ |
| B9 | Notifications row | Opens Android's notification settings for the app | M | ⏭ |
| B10 | New version alerts off/on | Unsubscribes / subscribes the language topic | W | ✅ |
| B11 | Check for updates | "You're up to date" or the card on Home | W | ✅ |

## C. Offline game (one phone)
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| C1 | New game → setup | 6 name fields, roles, rules, Deal | W, M | ✅ |
| C2 | Add / remove players, 4–20 | Limits respected; Deal off with fewer than 4 | W | ✅ |
| C3 | Empty or duplicate names | Setup refuses with a reason | W | ✅ |
| C4 | Mafia / Detective counts, rules presets | Only valid combinations; summary updates | W | ✅ |
| C5 | Deal: pass the phone | "Pass to X", hold to see the role card, Memorized | W, E | ✅ (M: 6 players dealt) |
| C6 | Night: each role picks, Mafia teammates see each other | Choices confirmed; locked screens | W, E | ✅ |
| C7 | Dawn / morning | Narrator says the name; reveal held until then | W | ✅ |
| C8 | Day: discussion timer | Start, pause, +1 min, reset, time up | W | ✅ |
| C9 | Day: secret ballot | Everyone votes on the phone in turn; verdict | W, E | ✅ (M: ballot to verdict) |
| C10 | Day: decide together | Pick list, then decide | W | ✅ |
| C11 | Tie | Nobody out (vote and Mafia night) | S, W | ✅ |
| C12 | End | Winner, roles, recap; Play again / Home | W, E | ✅ |
| C13 | Back mid-game | Asks; the game is kept; Resume on Home | W, E | ✅ |
| C14 | App killed mid-game | Cold start resumes at the same step | W, E | ✅ |
| C15 | Discard a saved game | Asks; gone | W | ✅ |
| C16 | Double taps everywhere | Nobody skipped, nothing twice | W | ✅ |
| C17 | Role card hidden when the app goes to background | ✓ | W | ✅ |
| C18 | Offline games are never logged | No history entry, no server call | W | ✅ |

## D. Account
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| D1 | Sign in by email code | Code screen, sign in, pick @handle | W, E, M | ✅ |
| D2 | Wrong code / no network / "slow down" / bad email | Each says what happened, nothing hangs | W | ✅ |
| D3 | Handle taken | "That username is taken" | W, M | ✅ |
| D4 | Google sign-in (configured / not / cancelled) | Signs in / button off and says so / says nothing | W, H | ✅ W · Google itself ⏭ human |
| D5 | Saved session | Silent sign-in; offline shows the cached profile | W | ✅ |
| D6 | Profile: name, handle, favourite role, show online, avatar preset, photo | Saved; photo under 150 KB | W | ✅ |
| D7 | Devices: sign out another device | It's signed out | W | ✅ |
| D8 | Sign out | Signed out, offline play still works | W | ✅ |
| D9 | Delete account | Typing "delete" required; friendships go | W, E | ✅ |
| D10 | Phone's recent names move to the account on first sign-in | ✓ | W | ✅ |

## E. Friends and profiles
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| E1 | Add by @handle | "Friend request sent"; their bell / banner | W, M | ✅ |
| E2 | Accept / decline / cancel a request | Lists update both sides | W, E, M | ✅ |
| E3 | Remove a friend | Asks first | W | ✅ |
| E4 | A friend's row → profile | Whole page even with no games | W, M | ✅ |
| E5 | A stranger's profile | Add friend; no presence shown | W | ✅ |
| E6 | Edge tab: online friends, request dot; drag; open | ✓ (left in Arabic) | W | ✅ |
| E7 | Drawer actions: Invite / In your room / Ask to join / Invite from Home | The right one per state | W | ✅ |
| E8 | Block / report a player | They disappear; report reaches the admin queue | W, E | ✅ |

## F. Online rooms
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| F1 | Create a room | 6-digit code, share / copy, me as host | W, E, M | ✅ |
| F2 | Join with a code (valid / wrong / closed / full / kicked) | Joins / says why with a way home | W, S, M | ⚠️ Q2, Q3 |
| F3 | Members list in join order, crown, online dot, old-version tag | ✓ | W | ✅ |
| F4 | Host edits roles and rules; players see them read-only | ✓ | W | ✅ |
| F5 | Deal with fewer than 4 | Off, says why | W, M | ✅ |
| F6 | Deal → ready on every phone → night | ✓ | W, E | ✅ |
| F7 | Night, morning, day, vote, verdict, end online | Every phone in step | E | ✅ |
| F8 | Host controls: timer, secret / table vote, next night, continue anyway | Host only | W | ✅ |
| F9 | Mark the game valid / invalid; play again; back to lobby | ✓ | W, E | ✅ |
| F10 | Invite a friend from the lobby | Their banner / bell; Join opens the room | W, E | ✅ |
| F11 | Ask to join a friend's lobby; host lets in | ✓ | W, S | ✅ |
| F12 | Kick in the lobby; rejoin by code refused; invite back lets in | ✓ | S, M | ✅ |
| F13 | Kick mid-game under "Lobby only" | Refused with the Settings hint | S, W | ✅ |
| F14 | Host leaves | Host passes in join order; back again, host again | S | ✅ |
| F15 | Close the room | Everyone told; bar gone | W, S | ⚠️ Q7 |
| F16 | Minimize (Home icon) | Red bar on every screen; chat button under the friends tab; tap the bar → back | W, M | ✅ |
| F17 | Dealing while minimized | Pulled back with "Roles are being dealt" | W | ✅ |
| F18 | Start something else while in a room | "Leave your room first?" | W | ✅ |
| F19 | Buzz the host (lobby / game), limit and mute, unmute | ✓ | W, S, M | ✅ |
| F20 | Ping everyone | Every other phone vibrates and is told | W, M | ✅ |
| F21 | This phone narrates on/off | Remembered online | W | ✅ |
| F22 | Connection drop / weak / back | Coloured bar; taps resent once; catch-up | W, E | ✅ |
| F23 | Phone silent 30 s | Closed; host can Continue | S | ✅ |
| F24 | Repeated taps / stale choices | Ignored | S, W | ✅ |

## G. Chat
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| G1 | Everyone and 1:1 | Delivered to the right people only | S, W, E | ✅ |
| G2 | Unread badges (room, chat button on Home) | ✓ | W, M | ✅ |
| G3 | Swipe to reply (moves with the finger) / long press → reply | ✓ both directions, both languages | W, M | ✅ |
| G4 | React, edit within 15 min, mention | ✓ | W, S | ✅ |
| G5 | Out players only reach out players | ✓ | S, W | ✅ |
| G6 | Sending / not sent / retry, written during a drop | ✓ no duplicates | W | ✅ |
| G7 | Report a message (+ block) | ✓ their next message never arrives | W, E | ✅ |
| G8 | Rate limit 8 per 10 s | Refused politely | S | ✅ |

## H. Wi-Fi / Hotspot
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| H1 | Host a Wi-Fi room | Code + address; host narrates | W, E | ✅ |
| H2 | Find rooms / join by address / nothing found | ✓ | W | ✅ |
| H3 | Guest (signed out) joins | Plays; narration off by default | W | ✅ |
| H4 | A whole Wi-Fi game | Kept in History → Wi-Fi | W, E | ✅ |
| H5 | Host phone killed → Resume hosting | Room, game and chat back | S(Dart), E | ✅ |
| H6 | Ask to add to online history; Confirm / Not me; approved | ✓ | W, E | ✅ |
| H7 | Real Wi-Fi between real phones, hotspot | Works | H | ⏭ human |

## I. Notifications
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| I1 | Live banner (invite, request, let in, friend request) | Top, 6 s, one action | W, M | ✅ |
| I2 | Bell: unread marks, read when seen, Mark all as read, Clear | ✓ items stay 30 days | W | ✅ |
| I3 | Push with the app closed: invite / friend / approval / title | Shown; tap opens the right place | W, H | ✅ W · real push ⏭ human |
| I4 | Tapped invite to a closed room | "This invite expired", the bell | W | ✅ |

## J. Stats, history, old app
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| J1 | Stats: Mine / Everyone, filters, minimum games, titles | ✓ | W | ✅ |
| J2 | Player profile with games: win rate, roles, nemesis, partner, moments, form, Share | ✓ | W | ✅ |
| J3 | History: Online / Wi-Fi / Old app tabs, detail pages | ✓ | W | ✅ |
| J4 | Import old history by code (wrong code, old server down, result) | ✓ | W, S, H | ❌ Q1 |
| J5 | "Which one were you?" claim | One account per name | W, S | ✅ |
| J6 | Show me on the Everyone board off | Saved at once | W | ✅ |

## K. Looks, languages, sizes
| ID | Case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| K1 | Arabic everywhere: RTL, Arabic plurals, @handles stay LTR | ✓ | W | ⚠️ Q4 |
| K2 | Small phone 360×640, text ×1.3 | Nothing cut or overflowing | W | ✅ |
| K3 | Neon on every screen | Readable | W (screens), M | ✅ |

## Edge cases (tried on purpose)
| ID | Edge case | Expected | How | Result |
| --- | --- | --- | --- | --- |
| X1 | Every control on every screen tapped once from a fresh state | No crash; every control does something visible | W (click map) | ✅ 176 controls, 0 crashes |
| X2 | Tapping a button twice fast (deal, vote, ready, send) | Acts once | W, S | ✅ |
| X3 | Airplane mode in the lobby, then back | Red bar, then green; still in the room | M | ✅ |
| X4 | Airplane mode mid-game, then back | Same seat, caught up | E (drop), M | ✅ |
| X5 | App killed in a lobby, reopened | Back in the room from Home ("Back to room") | M | ⚠️ Q5 |
| X6 | App killed mid offline game | Resumes at the same step | W, E | ✅ |
| X7 | Font size large (system) | Layout holds | W (×1.3), M | ✅ |
| X8 | A 20-character name, emoji names, Arabic + Latin mixed | Fits, right direction | W, M | ⏭ |
| X9 | Join a room with a code of 5 digits / letters / spaces | Refused politely | W, M | ⚠️ Q2 |
| X10 | Two phones accept the same friend request both ways at once | One friendship | W, S | ✅ |
| X11 | Kicked player tries the code again | "You were removed" | S, M | ✅ |
| X12 | Buzz spam past the limit | Muted; host isn't spammed | S, M | ✅ |
| X13 | Host minimizes, a player leaves, host comes back | Members right | M | ⏭ |
| X14 | Open the bell / drawer / settings while a banner shows | Nothing hidden behind; all reachable | M | ⚠️ Q6 |
| X15 | Rotate the phone | Stays portrait | M | ✅ |
| X16 | Back button on every screen | Goes back or asks; never loses a game silently | W, M | ✅ |
| X17 | Server down (no network) on every account screen | Says so; nothing hangs | W | ✅ |
| X18 | Session refused (signed out elsewhere) | Signs out, keeps the offline game | W | ✅ |
| X19 | Two rooms: invite to another room while in one | "Leave your room first?" | W | ✅ |
| X20 | Very old build in a lobby | Others see "old version" | W | ✅ |
