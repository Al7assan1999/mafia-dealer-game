# Sprint 13 PRD: your 19 notes after 0.4.2 (draft for your sign-off)

Status: **waiting for your sign-off.** Nothing is built until you approve or change it.

Each note was traced by [Developer] in the code or measured on the emulator before this draft. The BA compared the
old app's own styles and screenshots (`../mafia-dealer/app/assets/style.css`, `tests/h1.png`, `h5.png`), read only.

## [BA] Challenge log (first, as the new rule says)
- **BA against itself:**
  - the "Mine" leaderboard (Sprint 8) and "anyone can import" (Sprint 8) were my designs. Your notes 2, 3 and 7 show
    they split one group's truth into one truth per phone. I own that;
  - QA's click map passed every chat control, but notes 4–6 are about **how** they look and behave. A tap test
    can't see a misaligned button. QA's rule gains a visual check per screen (below).
- **QA against Dev:**
  - #17 (chat → room → Home lands back in the chat) passed every test, because no test walks that path. Every
    "go back" path from the room bar and the chat button gets a test;
  - #15: the app keeps every downloaded update (`update.apk`, ~27 MB) in its cache forever.
- **Dev against BA:**
  - #14 can be read two ways (see Questions); Dev won't guess.

## What we found, per note
| # | Your note | Cause found | Proposal |
| --- | --- | --- | --- |
| 1 | Redeployed; stats came back | ✅ | – |
| 2 | Sami best on my phone, Halawy on Dareer's | Stats opens on **Mine**, and Mine is built from *that phone's* games: your online games plus the old games **you imported**. Dareer's Mine holds other games, so other titles. | S13-1 |
| 3 | The board should be one, from the database | Agreed. The shared board ("Everyone") leaves out old games and needs 10 games. | S13-1 |
| 4 | Mentions should work by typing "@" | Today it's a separate @ button. | S13-3 |
| 5 | Send isn't aligned with the box | The "6/200" counter under the box pushes the box up, and Send centres on box + counter. | S13-3 |
| 6 | The reply bar is wider than the box | The reply bar spans the full width; the box doesn't. | S13-3 |
| 7 | Only the admin imports | Today anyone can. | S13-1 |
| 8 | Noir doesn't look like the old app | The old Noir was a **"case file"**: cream paper cards with hard red offset shadows (stamps), typewriter headings, dashed dividers, a red **CLASSIFIED** stamp on the role card, paper tiles on Home. The new Noir is flat dark cards with thin lines. | S13-6 (its own sprint, see Questions) |
| 9 | Ask to join → host approves → straight into the room | Today, after "Let in", the player gets "X let you in, tap to join" and must tap. | S13-4 |
| 10 | Remove the test notification button | – | S13-5 |
| 11 | Release notes on the main screen, like the old app | The old Home footer: "v2.20.1 · Check for updates · **What's new**". The new app shows the notes once after an update, then they're gone. | S13-5 |
| 12 | Search friends, not only the exact @username | Only an exact @username lookup exists. | S13-4 |
| 13 | Rules in an expandable card, like the old app | Old: a **Rules card** (preset badge + chips of the active rules) opening the full rules grouped Night / Day / Multiplayer. New: one long list. | S13-2 |
| 14 | No notification when the update is finished, nor for hosting a game | Two possible meanings; see Questions | ? |
| 15 | 101 MB data, 36 MB cache | **Cache:** every downloaded update stays as `update.apk` (~27 MB), never deleted. **Data:** not reproduced. The same build uses ~2 MB of data on the emulator, so it's from your phone's history: most likely the earlier debug builds (~200 MB each) left files behind when the normal build replaced them. | S13-5 |
| 16 | An X to close Settings | – | S13-5 |
| 17 | Room → Home → chat → bar → Home lands back in the chat | Confirmed. The bar opens the room *on top of* the chat, and Home just closes the room again. | S13-2 |
| 18 | A friendlier room bar, like the old app | Old bar: a **live status dot**, "Your room · 3 players", and an explicit **"Back to room →"**; connection trouble ("Reconnecting…") shown inside it. New: a plain red strip with a chevron. | S13-2 |
| 19 | The roles must compete seriously | Written into `docs/team-workflow.md` (challenge log, blocks, quotas). This PRD is the first one under it. | done |

## Scope
### S13-1 One leaderboard for everyone, from the database (2, 3, 7) · must
- AC1: Stats shows **one board, the same on every phone**: every counted game in the database (online, approved
  Wi-Fi, and old games whose players are all marked real), whoever imported them.
- AC2: The old app's rule: ranked from **3 valid games**. Old players without an account appear under their old name;
  once linked or claimed, under their account.
- AC3: Filters stay (All / Online / Wi-Fi / Old app, all time / 30 days) and give the same answer on every phone.
  Your own row is highlighted and "You: #3" shows even below the top.
- AC4: **Only the admin can import** (server and app). Profile → Import old history disappears for everyone else.
- AC5: Titles (Best Player…) come from this one board. *(Recommendation: drop "Mine". See Questions.)*

### S13-2 Room navigation, the room bar, the rules card (17, 18, 13) · must
- AC1: From the room bar or the chat button, Home always lands on **Home**. Every path is tested: bar → Home; chat
  button → chat → bar → Home; chat → back.
- AC2: The room bar, as the old one:
  - a status dot (green: connected, amber: reconnecting);
  - "Your room · 3 players" / "In Dareer's room";
  - a clear **"Back to room →"**;
  - "Reconnecting…" inside the bar when the link drops.
- AC3: In setup and the lobby, **Rules** is a card: preset badge + chips of the active rules + the timer. A tap expands
  it in place into the groups Night / Day / Multiplayer (the old grouping); a tap on the header folds it.

### S13-3 Chat that feels right (4, 5, 6) · must
- AC1: Typing **@** in the box opens a list of the room's players above it, filtered as you type; a tap inserts
  @Name. The separate @ button goes.
- AC2: Send is centred on the box. The character counter shows only past 150 characters, inside the box's corner.
- AC3: The reply preview is exactly as wide as the box, with the same corners, and no shadow beyond it.
- AC4: QA's visual check: the chat at 360 / 393 / 412 px wide, EN / AR, Noir / Neon, with screenshots in the report.

### S13-4 Friends: search, and Ask to join that goes straight in (12, 9) · must
- AC1: Add friend is a **search**: 2+ letters match the start of an @username **or** any part of a display name, in
  either case; up to 20 results with avatars and Add / Requested / Friends. The exact @username still works.
  Blocked and banned accounts never show.
- AC2: Ask to join → the host's **Let in** → the player's app **opens the room by itself** if it's open and they're in
  no room ("Dareer let you in"). With the app closed, the notification opens it in one tap. In another room, it asks
  "Leave your room first?".

### S13-5 Home and Settings (11, 10, 16, 15) · must
- AC1: Home footer as the old app: "v0.4.3 · Check for updates · **What's new**". What's new shows this version's
  notes at any time (kept on the phone; fetched once if missing).
- AC2: Settings gets an **×** at the top right. The test notification button goes (the server route stays for QA).
- AC3: The downloaded update file is deleted once the new version starts (cache back to a few MB).
- AC4: Size: QA measures data and cache on the emulator after a full session and reports the numbers.
- AC5 *(BA proposal)*: Settings → long-press the version line shows "Storage: app data X MB · cache Y MB · biggest
  folder Z". Then your phone can tell us what the 101 MB is, instead of us guessing.

### S13-6 Noir, the "case file" look (8) · must, as its own sprint (Sprint 14)
- Paper cards (cream, dark text, hard red offset shadow) for the Home tiles, the recap and the role card.
- Typewriter headings and dashed dividers.
- The "CLASSIFIED" stamp on the revealed role card.
- Home laid out like the old app: big mode cards with an icon box, title and subtitle inside; History / Stats / How to
  play as a row of three tiles; one-tap language and theme buttons at the top.
- **QA's evidence:** side-by-side screenshots of the old Noir and the new one, per screen.
- *(Its own sprint because it touches every screen. Sprint 14 starts with mockups of three screens for your OK, then
  the rest.)*

## [BA] proposals
- **P1. History tools** (from the parity list):
  - change valid / invalid later (host);
  - hide a game from my history;
  - a valid / invalid filter.
- **P2. "Players in this game" on a history entry, linked to their profiles.**

## Questions (each changes what gets built)
1. **#14:** which do you mean?
   - (a) After an in-app update finishes installing, there's no notification saying "Updated to vX". Add one.
   - (b) There should be **no** notifications for those (the update and the Wi-Fi "hosting" notification bar): remove
     them.
   - (c) Something else.
2. **#3:** drop "Mine" completely (one board), or keep it as a filter "Games I played in"? *(Recommendation: drop it.)*
3. **#12:** may people be found by their **display name** too (not only @username)? *(Recommendation: yes, 2+ letters,
   20 results max.)*
4. **#8:** Noir as Sprint 14 with mockups first? *(Recommendation: yes.)*
5. **Claims:** with only you importing, should friends still pick "Which one were you?" themselves, or only you link
   names? *(Recommendation: both; your link wins.)*
6. P1 and P2: in or out?

## How [QA] will try to break it
- **S13-1:** two phones, the same board: compare the board's JSON from two accounts in a server test; a non-admin
  import → 403.
- **S13-2:** every room-bar / chat-button / Home path as widget tests, plus the emulator.
- **S13-3:** screenshot matrix (3 widths × EN/AR × Noir/Neon); "@" typed mid-word, Arabic names, a deleted player.
- **S13-4:** search with "da", "DAR", an Arabic name, a blocked user, a banned user; let in while the player is in
  another room or offline.
- **S13-5:** cache before and after an update on the emulator (numbers in the report).
- **The click map** reruns; any new silent or crashing control blocks the release.
