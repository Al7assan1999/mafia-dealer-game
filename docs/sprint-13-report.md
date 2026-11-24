# Sprint 13 Report: your 19 notes, a clean code structure, and what QA found

2026-11-24. Built against `docs/sprint-13-prd.md`, approved with your answers: #14 = (b) no update / hosting
notifications; "Mine" dropped; search by display name too; Noir is the team's call (→ Sprint 14); only you link old
names; P1 and P2 in. Run as the three personas. **Not committed, not deployed, not released.**

## [Developer] The code structure you asked for
Before: a few files of 1,500–3,000 lines each. Now `app/lib` is in layers, and **no file is over 500 lines** (the
largest is `features/wifi/local_room.dart`, 473):

```
lib/main.dart, app.dart        start-up and the app shell
lib/core/      api, prefs, audio, push, auth, ui, feedback, version   (no screens, no state)
lib/state/     account, room_conn, active_room, models                 (ChangeNotifiers; never import a screen)
lib/features/  home, settings, account, friends, notifications, online, room, chat, offline, wifi,
               stats, history, old_history, intro, guide, safety, update   (one folder per screen area)
```

- **State management, written down** in `docs/architecture.md`: state lives in `ChangeNotifier` controllers
  (`Account`, `RoomConn`, `ActiveRoom`, `Prefs`), handed to screens through their constructors, and read with
  `ListenableBuilder`. Screens own only their own UI state. No global singletons except the navigator keys.
- **Enforced, not just written:** `app/test/architecture_test.dart` fails the build if a file passes 500 lines, if
  `core/` imports anything outside `core/`, if `state/` imports a screen, or if a relative import sneaks in.
- The split came first and passed all 139 old tests unchanged before any Sprint 13 feature was added.

## [Developer] What changed, per PRD item
- **S13-1 One board** (notes 2, 3, 7; `server/src/stats.ts`, `legacy.ts`): one leaderboard from the database, the
  same on every phone: online + approved Wi-Fi + counted old games, ranked from 3 valid games. "Mine" is gone.
  Only the admin can import (server 403 for anyone else; the Profile entry shows only for you). Claims removed:
  only you link old names (Profile → Old players).
- **S13-2 Room** (13, 17, 18):
  - #17 fixed: re-opening the room from the bar first closes whatever is on top (the chat), so Home lands on Home;
  - the room bar: live dot, "Your room · 3 players" / "In Dareer's room", a "Back to room →" pill, and
    "Reconnecting to your room…" (amber dot) inside the bar when the link drops;
  - Rules is a folded card (preset badge + chips + talk time) that opens in place into Night / Day / Online groups.
- **S13-3 Chat** (4, 5, 6): typing "@" opens the player list above the box (filtered as you type, not inside a word
  like `email@x`); Send is centred on the box; the counter shows only past 150 characters; the reply bar is exactly
  the box's width.
- **S13-4 Friends** (9, 12): search from 2 letters, by the start of an @username or any part of a display name,
  Arabic included, never yourself, blocked or banned accounts. Let in → the room opens by itself with a toast
  "Dareer let you in" (and asks "Leave your room first?" if you're in another one).
- **S13-5 Home and Settings** (10, 11, 14, 15, 16):
  - Home footer "v0.4.3 · Check for updates · What's new" (the notes are kept, or fetched once from the Release);
  - Settings: × to close; no test notification button; no update-alerts switch;
  - #14 (b): no update notifications at all (phones are unsubscribed from the update topics; the release workflow
    no longer sends them). The Wi-Fi hosting notification can't be removed (Android requires one while hosting in
    the background), so it's now the quietest kind: no sound, no status-bar icon, folded at the bottom;
  - #15: the downloaded `update.apk` is deleted when the new version starts; long-press the version line in
    Settings shows what the app keeps, folder by folder (so your 101 MB can be explained from your phone).
- **P1 History tools:** All / Valid / Invalid filter; hide a game from my history (this phone only; it still counts),
  shown again under "Hidden".
- **P2** (players linked to profiles on a history entry) was already there from Sprint 10; checked, unchanged.
- **No database change this sprint** (no new migration, nothing to run before testing).

## [QA] How it was tested
| Check | Result |
| --- | --- |
| App tests (`flutter test`) | **152 / 152** pass (139 before; `test/sprint13_test.dart` adds 11 break attempts, plus fixes elsewhere) |
| Server tests (`npm test`) | **72 / 72** pass (new: one board for all accounts, admin-only import, friend search edge cases, rejoin keeps the seat) |
| Analyzer, TypeScript check, architecture test | clean |
| Click map (`tool/click_map_test.dart`) | 25 / 25 screens, no silent or crashing control |
| Emulator (profile build against a local server, a scripted second player) | 37 screenshots in `docs/qa/demo13/` |

Break attempts in `sprint13_test.dart`: the exact #17 path; the bar's dropped-link text appearing *and* going away;
the rules card folding/opening and a host change being sent; "@" mid-sentence, a filter matching nobody, "@" inside a
word, the counter at 160 characters, the reply bar's width measured against the box; search with 1 letter, part of a
display name, Add → Requested; a plain invite still asking first while a let-in opens by itself; Settings ×; What's
new from the kept notes, from the Release, and with nothing anywhere; the update file deleted, twice; History
filters and hide / unhide.

### Emulator walk-through (screenshots in `docs/qa/demo13/`)
- 01–03 Home footer; What's new on a build with no Release says "No notes for this version."
- 04–05 Settings with ×; × closes it.
- 06–08 Lobby; the folded Rules card; opened read-only for a non-host.
- 09–13 Chat: "@" list, mention sent (the server recorded it as a mention), reply bar the box's width.
- 14–17 **#17 on the device:** Home → chat bubble → bar → room → Home **lands on Home**.
- 18–19 Airplane mode: the bar turns amber "Reconnecting to your room…", back to normal when the network returns.
- 20–22 Search "halaw" finds "Sami Al-Halawy" by display name; Add → "Friend request sent" (confirmed on the server).
- 23–26 Leave, Ask to join, the host lets in → **the room opened by itself**, no tap.
- 28 Stats: one board with its explanation, no Mine / Everyone switch.
- 30, 37 Chat at 360 / 393 / 411 dp (Neon) and 360 dp Noir: Send centred, nothing clipped.
- 34–36 Arabic + Noir: Settings and the room bar mirror correctly; the storage readout: **2.0 MB cache after the whole
  session** (S13-5 AC4).

### [QA] What QA found on the emulator, and what was done
1. **Bug (server, older than this sprint):** leave a room in the lobby and come back, and your earlier messages
   show as "?" on the other side, because coming back gave you a new seat number. **Fixed** (`server/src/room.ts`):
   a leaver is kept as "left", so coming back restores the same number; a leaver no longer counts toward "room full".
   New server test; re-checked on the device (33: "after the fix" stays mine after leave + let in).
2. **Stale text:** Settings → Notifications still said "…and new versions" (EN + AR). **Fixed.**
3. **RTL nit:** the storage readout read "MB 2.0" in Arabic. **Fixed** (always left-to-right).
4. Two old tests broke because of intended changes (the night timer moved into the folded rules card; notes show as
   "• …"). Updated, not weakened.

### [QA] What the tests can't prove
- **Your 101 MB "Data":** not reproduced; the emulator holds 2 MB. The long-press readout on *your* phone will show
  which folder it is. Please send a screenshot of it after you install this version.
- **Update notifications gone on real phones:** phones stop getting them once they open this version (they
  unsubscribe on start). A phone still on 0.4.2 that never opens the app could get one more, but none will be sent:
  the release workflow no longer sends them.
- **The quiet hosting notification:** Android decides how "minimum" looks per phone maker; checked only on the
  emulator (Pixel image).
- **The Arabic chat screen** wasn't captured on the device (the language toggled back during that pass); the Arabic
  room bar and Settings were. Messages from a player who **left and never came back** still show "?" (they're no
  longer in the member list). Small; proposed below.
- Real two-phone timing over mobile data, and the old messages you already have in open rooms (sent before the fix)
  keep their "?".

## [BA] Acceptance review
| Item | AC | Verdict |
| --- | --- | --- |
| S13-1 | One board, same everywhere; 3 games; filters; admin-only import; titles from it | ✅ server test compares two accounts' boards; 28 |
| S13-2 | AC1 Home lands on Home (all paths) | ✅ test + 14–17 |
| | AC2 room bar like the old one | ✅ 14, 18–19 |
| | AC3 Rules card | ✅ test + 07–08 |
| S13-3 | AC1 "@" list · AC2 Send centred, counter >150 · AC3 reply width | ✅ test + 10–13 |
| | AC4 visual matrix (3 widths × EN/AR × Noir/Neon) | ⚠️ partly: 3 widths Neon EN, 360 Noir EN, AR in Settings and the bar; AR chat missing |
| S13-4 | AC1 search · AC2 let in opens the room | ✅ server + app tests, 20–26 |
| S13-5 | AC1 footer · AC2 × and no test button · AC3 update file deleted · AC4 size measured · AC5 storage readout | ✅ |
| #14 | (b) no update / hosting notifications | ✅ updates removed; hosting can't be removed (Android), made silent |
| P1 / P2 | History tools / players linked | ✅ / already there |
| #8 Noir | your call delegated to the team | → **Sprint 14**, starting with mockups of 3 screens for your OK (it touches every screen) |

### [BA] Challenge log
- **QA against Dev:** the "?" after rejoining passed every test; only a real leave → let in on the device found it.
  Dev fixed it at the root (the server) instead of patching the chat screen.
- **BA against QA:** the PRD promised a 12-cell screenshot matrix; QA delivered 6 cells. Marked ⚠️, not ✅.
- **BA against BA:** "Settings → Notifications" text was in no AC; nobody re-read old copy after removing a feature.
  Rule added for next sprints: when a feature is removed, grep both languages for its words.
- **Dev against BA:** #14 (b) asked for no hosting notification; Android won't allow it. Dev said so instead of
  hiding it in a way that gets the app killed in the background.

## Before release (your call)
1. Nothing to run on the database.
2. Version bump to 0.4.3, then your usual commit → push → release when you say so.
3. After installing, long-press the version line in Settings and send me the screenshot (the 101 MB question).

## Proposed next
- Sprint 14: Noir "case file" look (mockups first).
- Small: show the name of a player who left and never returned in old chat messages instead of "?".
