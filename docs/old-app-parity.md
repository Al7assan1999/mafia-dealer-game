# [BA] Old app → new app: what's carried over, what's missing

2026-11-23. Every feature of the old app (v2.0–v2.20.1, from `../mafia-dealer/CONTEXT.md` and its Settings screen) checked
against the new app's code and screens. This is the requirement coverage the earlier PRDs lacked: they covered your
instructions, not what the old app already gave your friends.

Legend: ✅ in the new app · ➖ dropped on purpose (your decision) · ❌ missing · ❓ for you to decide

## 1. Settings (the old Settings screen, group by group)
| Old setting | New app | Note |
| --- | --- | --- |
| Look: language | ✅ | Settings |
| Look: theme Neon / Noir | ➖ | Sprint 2: you chose the Noir look only. ❓ Do you want Neon back as a choice? |
| Sound: voice volume, effects volume | ✅ | Settings |
| Account: Show me as online | ✅ | Moved to Profile |
| When you host: buzz limit | ⚠️ | The room has a buzz limit (`buzzMax`), but no default you set once in Settings: each room starts from the built-in value |
| When you host: kick (lobby only / any time) | ❌ | The host can kick, but the choice "lobby only / also mid-game" is gone |
| Group history (shared group code) | ❌ | Waits for your groups prompt |
| More: show the welcome at start / watch the welcome | ❌ | The welcome itself is missing (see 3) |
| More: check for updates, version, new-version alerts | ❌ | Play In-App Updates come with the Play work. **Until then, friends on the CI APK never hear about a new build.** ❓ |
| Notifications | ✅ new | Sprint 7 |

## 2. Play and records
| Old feature | New app | Note |
| --- | --- | --- |
| Offline game (one phone), rules, presets, suspense reveals, narrator, name clips | ✅ | |
| Recommended Mafia (players ÷ 4, one tap) | ✅ | Setup |
| Live table vote / secret vote, ghost view, night timer, skip vote | ✅ | |
| Recap card (winner, player of the game, roles, timeline) | ✅ | End screen |
| **History of offline games, valid / invalid** | ➖ ❓ | Decision 2026-11-22: offline games are never logged. **Most of your and your friends' old history is offline (one-phone) games**, so a group that plays on one phone gets no new records at all. ❓ Keep that decision, or log offline games on the phone (like Wi-Fi) so they count? |
| **Stats: leaderboard by win rate (3-game minimum), Mafia / Citizen sides** | ❌ | **Not in the new app at all.** |
| **Titles: Best Player, Best Mafia, Best Detective, Best Doctor, Most Killed First** | ❌ | |
| **Player profiles: win rate, best role, killed most by, wins by role, moments, recent form** | ❌ | |
| Saved names as chips, no duplicates | ✅ | In the account (D1) |
| Rematch (Play again, same players) | ✅ | |

**Stats are the biggest gap.** Your answer "we need to keep going with the old history" only means something once the
new app shows stats again. Without them, imported games would just be a list.

## 3. The look and feel
| Old feature | New app | Note |
| --- | --- | --- |
| The welcome (six animated scenes with sounds, blood, the laugh), with Skip, mute, replay | ❌ | The new app opens straight on Home |
| Launcher icon "Fedora over the town" | ✅ | |
| Phone Back on Home asks "Close Mafia Dealer?" | ❌ | Back closes the app at once |
| Transitions (screen fade, sheet slide) | ✅ | Flutter defaults |

## 4. Rooms (Wi-Fi and online)
| Old feature | New app | Note |
| --- | --- | --- |
| Wi-Fi hosting, discovery, manual address, keep-alive, resume | ✅ | Sprint 6 |
| Host takeover (v2.20) | ➖ | Online: not needed (the server judges). Wi-Fi: left out in Sprint 6 (decision 3). |
| Connection bar | ✅ | |
| **Minimize a room (lobby) + "Your room · N players" bar on every screen** | ❌ | Leaving the lobby screen leaves the room |
| Players see the host's rules in the lobby | ✅ | Lobby summary |
| Copy / Share the code or address | ✅ | |
| Old-version warning in the lobby | ❌ | Matters once friends run different builds (see the update gap) |

## 5. Social
| Old feature | New app | Note |
| --- | --- | --- |
| Accounts, profile, avatar presets or photo, favourite role | ✅ | Google sign-in instead of a password |
| Friends: requests, tabs, status pills, Ask to join, Let in | ✅ | |
| Friends drawer (the edge tab) | ❌ | A Friends screen instead. Fine, unless you miss the drawer. |
| Invite from Home (opens a room and invites) | ❌ | Invites only from inside a room |
| Bell history (handled items kept 24 h with their result: Joined, Declined, Expired…) | ❌ | The new bell drops an item once handled |
| Chat: 1:1 + Everyone, reactions, swipe to reply, edit 15 min, mentions, out-player rules | ✅ | Sprint 5 |
| Telegram (invites, password reset, update announcements) | ➖ | Replaced by push (Sprint 7) |

## [BA] Proposal: order of the missing pieces
1. **Sprint 8: Stats + old history.**
   - The leaderboard, titles and player profiles, from online, approved Wi-Fi and imported old games.
   - The old history import (`docs/old-players-plan.md`).
   - The offline-logging question settled first.
2. **Sprint 9: Settings, room parity and the drawer** (his note: match the old app):
   - **the floating friends drawer**, the old edge tab with online friends, requests and Invite / Ask to join;
   - **minimize while in a room**, so a player goes Home without leaving; a "Your room · N players" bar on every
     screen; pulled back when roles are dealt;
   - Neon as a theme choice.
   - Host defaults (buzz limit, kick mode).
   - Minimize the lobby + room bar.
   - "Close Mafia Dealer?" on Back.
   - Bell history.
   - Invite from Home.
   - Old-version warning.
   - A way for APK testers to hear about new builds.
3. **Sprint 10: the intro, same as before** (his note): the six scenes:
   - dawn town;
   - the crack at night;
   - chalk outline and crowd;
   - the Doctor;
   - the Detective;
   - the Mafia's laugh.

   Then the title, with the old sounds (birdsong, crickets and owl, the blade, the healing glow, the mystery theme, the
   drone and the laugh) and the blood. Plays once on first launch without Skip, then only when switched on; Skip, mute
   and "Watch the intro" in Settings and How to play. Both themes, EN/AR, reduced motion respected. Built in Flutter
   from the old SVG and sound recipes (`../mafia-dealer/app/src/welcome.ts`, `audio/welcomeSfx.ts`), only read.
4. **Groups**: whenever your prompt arrives (it may change 1).
5. **Play readiness** last, as you said.

## His answers (2026-11-23)
1. Neon back as a choice. 2. Offline games stay unlogged. 3. Update notices "same as before" for now (in Sprint 8).
4. The order as proposed.

## Questions for you (answered above)
1. Neon theme back as a choice, or Noir only?
2. Offline games: keep "never logged", or log them on the phone so stats keep growing for one-phone groups?
3. Until Play: how should friends on the APK hear about a new build? (a) A "New version" line on Home that links to a
   download page. (b) Nothing; you tell them.
4. Is the order above right? Stats first?
