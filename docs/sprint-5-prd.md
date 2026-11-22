# Sprint 5 PRD: room chat, safety, and what the player walkthrough found

Status: **signed off and built 2026-11-22** (results: `docs/sprint-5-report.md`). Not committed.

## [BA] Audit

### A. Player walkthrough of the real screens (first one: it covers Sprints 2–4 too)
The screens were rendered with `app/tool/screens_test.dart`: 55 screens, English and Arabic, at a small 360×640 phone.
I looked at 15 of them as a player would. Findings, most important first:

| # | Where | What a player runs into |
| --- | --- | --- |
| W1 | **Day, offline and online** | **Nothing shows who is still alive** during the discussion. Offline, the alive players are only inside the vote list; online, the day screen is just the timer. The whole day is about "who is left and who do we suspect". |
| W2 | Day, offline | **Two ways to vote, side by side, no explanation:** "Who did the town vote out?" with "Confirm decision", and "Start secret ballot". A new group doesn't know which to use, or that they're alternatives. |
| W3 | Day, online (host) | The button says "Start secret **ballot**" (the offline pass-the-phone wording). Online, each phone votes on its own: it should say "secret vote" and explain table vs secret. |
| W4 | Avatars everywhere | **The default avatar is the Mafia symbol** (preset 0), and other presets are the Doctor / Detective / Citizen icons. In a game about hidden roles, a lobby full of Mafia icons misleads people (inherited from the old app). |
| W5 | Lobby, host | **The host can't see what they're dealing** without scrolling past the players: the roles and rules sit below the fold under the Deal button. Dealing with an offline player gives no warning either. |
| W6 | Arabic, everywhere | **@handles render backwards** ("p1@" instead of "@p1"): the Latin handle isn't isolated inside right-to-left text. |
| W7 | Online, connection lost | **The host's buttons stay live during a drop.** The taps queue and fire after reconnecting, possibly into a phase that moved on (for example a queued "next night"). |
| W8 | First run | **No "How to play".** Google Play users who don't know Mafia get no explanation of roles and phases (the old app had a guide). |
| W9 | Offline night pick | The night number isn't shown (it is online). |

### B. Chat and safety
- **The server has room chat already** (phase 3):
  - Everyone, plus 1:1 by player;
  - out players only reach out players;
  - 30 reactions, replies, mentions, edits for 15 min;
  - 200 characters, rate limits, the last 50 per conversation;
  - the history on joining.
- **The app has no chat.** The old app's chat was the "Case file" look: swipe to reply, an @ list, a failed message
  with retry, the quick six reactions 👍 ❤️ 😂 😮 🔪 🤫.
- **Google Play rule:** apps where users send each other text must let users **report** and **block**, and someone
  must act on reports. **The server has neither yet.**

### C. Polish noted in Sprint 4
Timers use each phone's own clock against the server's end time: a phone with a wrong clock shows a wrong timer.

## Scope

### S5-1 Room chat (lobby and game)
- AC1: A chat button in the room's top bar with an unread badge. Conversations: Everyone, plus one per player.
  Out players see the "out players only" rule at the top.
- AC2: Sending shows "sending" until the server confirms it (`cid`). A failure shows "Not sent · tap to retry";
  messages written during a drop go out after reconnecting.
- AC3: Reply by swipe (right in English, left in Arabic) or long press; the quick six + all 30 reactions; edit my
  own message for 15 min ("edited"); @mention from the players I can reach. A mention buzzes my phone.
- AC4: A 200-character counter, "slow down" on the rate limit, right-to-left in Arabic, the "Case file" Noir look.
- AC5: History comes back after a reconnect or rejoin, with no duplicates.

### S5-2 Safety: block and report (Play)
- AC1: **Block** from a message, a name in the room, or a friend card:
  - their messages and DMs are hidden from me;
  - no DMs, friend requests, invites or join requests from them;
  - an existing friendship ends;
  - they aren't told.
  
  Enforced by the server.
- AC2: **Unblock** in Profile → "Blocked players".
- AC3: **Report** a message or a player (spam, harassment, hate, other + note). The server keeps a snapshot (text,
  who, when, room), so it survives the room's deletion. Reporting offers to block.
- AC4: **Acting on reports:** the admin sees open reports in an admin screen and can dismiss them or **ban** the
  account (signed out, no new sign-ins).
- AC5: **Server:**
  - migration `0005` (blocks, reports, `banned_at`) + rollback;
  - endpoints for block / unblock / list, report, and the admin's reports;
  - rooms and the hub respect blocks;
  - an account's data goes with the account, except reports about it.

### S5-3 What the walkthrough found
- AC1 (W1): **Who's alive, on the day screen,** offline and online: every player, alive or out (with their role if
  "reveal on elimination" is on), in seat order.
- AC2 (W2): Offline day: the town first chooses **how** to decide: "Decide together" (pick on this phone) or "Secret
  ballot" (pass the phone). Each has a one-line explanation, and the unused path isn't on screen at the same time.
- AC3 (W3): Online: "Secret vote (each phone)" and "Table vote (everyone sees the board)", each with a one-line
  explanation.
- AC4 (W4): **Neutral avatar presets:** 10 non-role pictures (fedora, moon, mask, eye, crown, knife-free town
  symbols…). The default is neutral; no role icons as avatars.
- AC5 (W5): The lobby shows a one-line summary next to Deal ("5 players · 1 Mafia · Doctor · Classic rules"; tapping
  it scrolls to the settings). A warning if an offline player would be dealt in.
- AC6 (W6): @handles render correctly in Arabic everywhere (isolated left-to-right).
- AC7 (W7): While the connection is lost, the host's controls are disabled with "Waiting for the connection…";
  only chat queues.
- AC8 (W8): **How to play**: a short guide from Home (roles, night / day / vote, winning; English + Arabic), offered
  once on first launch.
- AC9 (W9): The offline night pick shows "Night N".
- AC10: **One clock:** the server's time comes in every `room` message; timers on two phones show the same second.

## How QA will verify
- **Server:** vitest for blocks (every delivery path), reports (snapshot after the room is gone), bans, admin-only
  access, deletion, the clock.
- **App widget tests:**
  - chat (ack, retry, queue while dropped, swipes in both directions, reactions, edits and their limit, mentions,
    badge, out-players rule, no duplicates);
  - block / report;
  - the day roster;
  - the new voting choices;
  - the disabled host controls during a drop;
  - the guide.
- **Emulator test:** chat with a scripted player, block them (their next message never arrives), report them (the
  admin list shows it).
- **[QA] UX pass:** the screenshot tool again, with chat, safety, the day roster, voting, avatars, the lobby summary,
  the guide, and Arabic handles. Findings go back to the Developer before the report.
- **[BA] acceptance review:** each AC checked against the build and the screenshots, in the release report.

## Decisions needed
1. **Admin:** your account only, as an `ADMIN_IDS` server setting, with an admin screen only you see (recommended).
2. **Reports about a deleted account:** keep them for moderation (recommended; the privacy policy will say so).
3. **Word filter:** none for now, report / block only (recommended).
4. **Avatar presets (W4):** replace the role icons with 10 neutral ones (recommended)? It changes how existing
   accounts' avatars look (preset numbers stay, pictures change).
5. **How to play (W8):** in this sprint (recommended), or later?
6. **Your Sprint 4 playtest notes:** I'll add them to S5-3 when you send them.
