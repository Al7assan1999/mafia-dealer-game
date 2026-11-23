# Sprint 12 Release Report: what the full QA cycle found

2026-11-23. Built against `docs/sprint-12-prd.md` (approved: "Yes approved", all items and P1–P3). Run as the three
personas. **Not committed, not deployed.**

## [Developer] What changed
- **S12-1 Old history that's kept and fixable** (Q1; `server/src/legacy.ts`, `stats.ts`, app `stats.dart`):
  - an import keeps **every valid game** and answers `{found, imported, duplicates, broken, waiting}`;
  - a game counts once every name in it is marked a real player; a test name keeps it out for good. Counting
    decides this at read time, so marking names later needs no re-import;
  - **Old players** (admin only): `GET/PUT /v1/legacy/players` lists every name found, with its game count, and
    marks it Real (optionally linked to an @username, which must exist), Test, or Not sure;
  - app: Profile → **Old players** (admin only, next to Reports, where the admin tools already are);
  - the import line now reads, for example: *"119 games found: 119 new, 0 already here. 119 games wait until their
    players are confirmed, then they count in stats."*;
  - History → Old app tags "waiting for player names" / "test game · not counted";
  - **no schema change:** the marks live in the existing `settings.old_players` value (a `tests` list beside
    `names`), so no migration is needed. The raw games are never changed.
- **S12-2 Joining by code** (Q2, Q3): Join stays off until 6 digits are typed ("Type all 6 digits"). The code is
  checked first (`GET /v1/rooms/:code`), and "No room with that code" shows on the Online screen. Typing clears it.
- **S12-3 Plurals** (Q4): 1 vote / 2 votes, 1 player, Needs 1 game, the Wi-Fi list and request, the import line, in
  English and Arabic (Arabic duals and few / many forms, the MVP lines too). **Guard test:** a counted English text
  without a plural fails the build.
- **S12-4 Cold start** (Q5): the saved account (and Back to room) shows on the first frame, from the phone's memory.
  If there turns out to be no session, it's cleared.
- **S12-5 Banner** (Q6): below the top bar, never over Friends, the bell or Settings; swiped away up or sideways.
- **S12-6 Polish:**
  - a closed room shows only its message and Home (Q7);
  - the lobby's friends tab starts below the code card (Q8);
  - **TalkBack** can open and close the role card with "double-tap and hold" (Q9);
  - tapping a chat message opens its menu; Send is dimmed while the box is empty (Q10).
- **S12-7** `docs/old-app-parity.md` rewritten from both apps (below).
- **P1** CI runs the click map; any control that throws fails the build.
- **P3** friends' status shows the room size: "In a room · 3 players" / "In a game · 5 players" (drawer, Friends,
  profiles):
  - migration **`0009_room_size.sql`** (+ `rollbacks/0009_room_size.sql`): `users.room_size`;
  - rooms report their size when it changes.
- **QA's own find, fixed:** in Neon the room title cut the code ("Room 4386…"); it now shrinks to fit.

## [QA] Results
- **Server 71/71** (the import test rewritten for "keep everything"; +1 for Old players: admin only, marking,
  linking, recount). Typecheck clean.
- **App 139/139:**
  - 11 new in `test/sprint12_test.dart`: Old players; admin-only; join; the plural guard; cold start ×2; banner;
    closed room + tab; chat; TalkBack; P3;
  - the import line test updated. Analyzer clean.
- **Click map rerun:** 174 controls on 25 screens, **0 crashes**.
  - 15 "nothing visible", all expected: already-selected choices; buttons that open Android's own screens; swipe-only
    areas;
  - Q2's and Q10's silent controls are gone from the list.
- **Emulator** (profile build on `qa34`, local worker with migration 0009, `qa-bot` second player; screenshots in
  `docs/qa/demo12/`):

  | Item | Seen on the device |
  | --- | --- |
  | S12-4 | The first app frame after a cold start shows @Host4801 (and the unfinished offline game); no "Sign in" flash |
  | S12-2 | Join greyed with "Type all 6 digits"; a wrong code → "No room with that code" on the Online screen; the right code opens the room |
  | S12-5 | An invite banner under the top bar (back arrow and title free); a swipe up removes it |
  | S12-6 | Friends tab below the code card; a tap on my message opens React / Reply / Edit; Send dimmed when empty, red with text |
  | R7 (S11) | A player's lobby shows "Buzz the host" |

- **Not proven on the device:**
  - **S12-1** against the real old server: needs the deploy and your Account ID in `ADMIN_IDS`; covered by the server
    tests;
  - **P3** live counts: the scripted player has no friends connection, so it shows Offline; covered by tests;
  - **TalkBack:** not switched on in the emulator; covered by the semantics test;
  - the closed-room screen: covered by its test.

**QA↔Dev:**
- QA found the Neon title cut-off on the device; Dev fixed it.
- QA asked why Old players isn't in Settings as the PRD said. Dev: the admin's Reports already live in Profile next
  to the import, so one place for admin tools. **BA accepts (below).**

## [BA] Acceptance review
| Item | Verdict |
| --- | --- |
| S12-1 AC1–AC5 | **Accepted** (server + widget tests). AC3's place changed from Settings to Profile, next to Reports and the import; I accept it as better. **To confirm after the deploy:** your import of `JYJ8WU9J` again → "119 found… waiting", then Old players. |
| S12-1 AC6 | **Changed and accepted:** no schema change was needed, so no migration. The marks are in the existing settings row. |
| S12-2 | Accepted (device). Full and kicked rooms are still told by the room screen, since the server only knows those once you connect. |
| S12-3 | Accepted, with the guard test |
| S12-4 | Accepted (device) |
| S12-5 | Accepted (device) |
| S12-6 | Accepted (device + tests) |
| S12-7 | Delivered: `docs/old-app-parity.md` |
| P1 | Accepted, in CI. Proven on the next run. |
| P2 | **Waiting:** needs the deploy and your OK to create one QA account on production |
| P3 | Accepted (tests); the live count shows after deploy and migration 0009 |

### S12-7: the "revamp complete" list (from `docs/old-app-parity.md`)
Everything from the old app is in the new one, except:
1. **Groups** (one shared history and leaderboard per group code): waits for your prompt.
2. **History tools:** change valid / invalid later (host); hide a game from my history; a valid / invalid filter.
3. **Home:** one-tap language / theme buttons; "What's new" any time.

**My recommendation:** 2 + 3 as Sprint 13 (small), Groups as Sprint 14. Then the new roles.

## For you
1. **Before the push:** put your Account ID (Profile → Account ID) in the GitHub secret `ADMIN_IDS`. The deploy
   copies it to the server, so setting it later needs another deploy.
2. **Commit + push** (the deploy applies migration 0009 and the new server). I need your go for each.
3. **After the deploy:**
   - import `JYJ8WU9J` again;
   - open Profile → **Old players** and mark the names;
   - your friends then pick "Which one were you?".
4. **P2:** may QA create one account on production (`qa@` an address you choose) for the after-deploy check?
5. Approve the "revamp complete" list, or change it.
