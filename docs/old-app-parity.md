# [BA] Old app → new app: the true parity list (S12-7)

Rewritten 2026-11-23 for Sprint 12, from both apps:
- the old app: `../mafia-dealer/app/src` screens (home, setup, rules, history, stats, settings, guide), its 630 English
  texts, and the welcome;
- the new app: the code, the click map (`docs/qa/click-map.md`) and the emulator session.

The first version (before Sprint 8) is replaced: most of what it listed as missing is now built.

Legend: ✅ in the new app (sprint) · ➖ dropped on purpose (your decision) · ❌ still missing.

## Settings
| Old | New | |
| --- | --- | --- |
| Language | ✅ | Settings |
| Theme Noir / Neon | ✅ S9 | Settings → Look, with previews |
| Narrator and effects volume | ✅ | |
| Show me as online | ✅ | Profile |
| When you host: buzz limit, kick (lobby only / any time) | ✅ S9 | |
| Show the welcome at start / watch it | ✅ S10 | Also in How to play |
| Check for updates, version, new-version alerts | ✅ S8 | Push instead of the alarm |
| **Group history (one shared history and leaderboard per group code)** | ❌ | Waits for your groups prompt |
| Password, Telegram link and reset | ➖ | Email code + Google instead (Sprint 3) |

## Home
| Old | New | |
| --- | --- | --- |
| Offline / Wi-Fi / Online, Resume, Stats, History, How to play | ✅ | |
| Profile menu from the avatar | ✅ | The account bar |
| Back asks "Close Mafia Dealer?" | ✅ S9 | |
| **One-tap language and theme buttons on Home** | ❌ | Small; now only in Settings |
| **"What's new" whenever you want** | ❌ | The new app shows the notes once after an update, then they're gone |

## The game (offline, Wi-Fi, online)
| Old | New | |
| --- | --- | --- |
| Setup: players, saved names as chips, roles, recommended Mafia, rules and presets | ✅ | |
| Pass-and-play deal, night turns, suspense reveals, narrator and name clips | ✅ | |
| Live table vote, secret vote, skip vote, ghost view, night timer, discussion timer | ✅ | |
| Recap: winner, player of the game, roles, timeline; Play again | ✅ | |
| Tie = nobody out | ✅ S7 | Your rule |
| Offline games in history | ➖ | Your decision: never logged |

## History
| Old | New | |
| --- | --- | --- |
| The games, newest first, with the recap | ✅ | Online / Wi-Fi / Old app tabs |
| Mark valid / invalid at the end | ✅ | Online: the host at the end screen |
| **Change valid / invalid later, from History** | ❌ | Old: a toggle on each game. New: only on the end screen. |
| **Delete a game / clear history** | ❌ | Old: from the phone. New: records are shared with the others in the game, so "delete" would mean "hide from my history". Needs your decision. |
| **Filter: valid / invalid, my group** | ❌ | |
| Old app's games | ✅ S8 + S12-1 | Import, the admin's Old players, "Which one were you?" |

## Stats
| Old | New | |
| --- | --- | --- |
| Leaderboard by win rate, 3-game minimum, Mafia / Citizen sides | ✅ S8 | Plus an Everyone board |
| Titles: Best Player, Best Mafia, Best Detective, Best Doctor, Most Killed First | ✅ S8 | |
| Player profiles: win rate, best role, killed most by, by role, moments, recent form | ✅ S8 + S11 | A whole page even with no games |

## Rooms
| Old | New | |
| --- | --- | --- |
| Wi-Fi host, discovery, address, keep-alive, resume hosting | ✅ S6 | |
| Online rooms by code | ✅ S4 | |
| Host takeover | ➖ | The online server judges; Wi-Fi left out (S6) |
| Minimize + "Your room" bar; pulled back on deal | ✅ S9 | |
| Lobby rules for players; copy / share code or address | ✅ | |
| Buzz the host, Ping everyone, buzz limit and unmute | ✅ S11 | In the lobby, as the old app |
| Old-version tag | ✅ S8 | |
| Connection bar | ✅ | |

## Social
| Old | New | |
| --- | --- | --- |
| Accounts, profile, avatar or photo, favourite role | ✅ | |
| Friends, requests, status, Ask to join, Let in | ✅ | Status shows the room size (S12 P3) |
| The edge-tab drawer; Invite from Home | ✅ S9 | |
| The in-app banner; bell history | ✅ S9 + S10 | |
| Chat: Everyone and 1:1, reactions, swipe to reply, edit, mentions, out players | ✅ S5 + S11 | |
| Telegram announcements | ➖ | Push |

## [BA] "Revamp complete" list: what's left, for your approval
1. **Groups** (one shared history and leaderboard per group): **waits for your prompt.** It's the biggest piece left.
2. **History tools:** change valid / invalid later (host only); "hide from my history" for a game; a valid / invalid
   filter.
3. **Home:** one-tap language and theme buttons; "What's new" any time (the notes of the installed version).

**My recommendation:** 2 and 3 in one small sprint (Sprint 13). Groups as Sprint 14, once your prompt arrives. After
that, "the old app is fully revamped", and the new roles can start.
