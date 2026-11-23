# Sprint 8 PRD: stats, titles and profiles; your old history; telling testers about a new build

Status: **signed off 2026-11-23** with these answers:
1. My games + **a leaderboard of all users** (S8-1 AC6).
2. The player-name list comes later: the import is built, and imports nothing until the list exists.
3. Releases yes, and the update must feel automatic, like the old app (S8-4 AC3).
4. A push for new versions too (S8-4 AC5).
5. All four [BA] proposals.
6. The emulator here: yes.

He also asked to plan the floating friends drawer, minimize-in-room and the intro (Sprint 9 and 10 in
`docs/old-app-parity.md`).

His answers of 2026-11-23 behind this sprint:
- Next sprint as recommended: Stats + the old history.
- Offline games stay unlogged.
- New builds announced "same as before for now".
- Neon comes back as a choice (planned for Sprint 9 with the other Settings items, see `docs/old-app-parity.md`).

## [BA] Audit

Walked as a player on the real screens (History → Online / Wi-Fi, a game's detail page, the end screen, Profile, Home)
and compared them with the old app's Stats, Profile and update screens (`../mafia-dealer/app/src/screens/stats.ts`,
`update.ts`; the old app is only read, never changed).

### A. A player can't see how good they are
The old app's Stats screen was the reason to mark games valid. In the new app the Valid / Invalid buttons exist, but
nothing reads them. What the old app had:
- **Five titles:**
  - **Best player:** the highest win rate with 3+ valid games.
  - **Best Mafia:** the best Mafia win rate, at least 2 Mafia games.
  - **Best Detective:** the most Mafia caught.
  - **Best Doctor:** the most saves.
  - **Most killed first.**
- **Leaderboard:**
  - ranked by win rate (ties: more wins, then more games);
  - unranked players shown greyed with "Needs 3 games";
  - each row: "Mafia 3/5 · Citizen 4/9".
- **Player profile** (tap a row):
  - win rate;
  - best role;
  - as Mafia;
  - as Citizens' side;
  - **killed most by** (the nemesis);
  - wins by role, as bars;
  - moments (saves, Mafia caught, times killed, times voted out);
  - the last 8 games as W / L.
  - Players with an account were opened on their account card.

### B. Whose games count
The old app counted **every game on that phone** (or in its shared group): the phone was the table. The new app has no
"table" until groups are redesigned. The closest honest equivalent: **the games I played in**.
- online;
- Wi-Fi games approved into online history;
- my imported old games.

The leaderboard then ranks **everyone who played in those games with me**. A player is one entry per account; a guest
or an old-app name is one entry per name. Groups (your prompt) can narrow this later.

### C. Your old history
- `docs/old-players-plan.md` (revised): the old app's own **Group history** uploads a phone's games; the new app
  imports them by the group code; only games whose every name is on your real-player list come in; names on the list
  can be tied to new accounts, so the games count for that person.
- **Offline games stay unlogged** (your answer). So the old games are the **only** one-phone games in the stats; new
  one-phone games still don't count. I'll say that on the Stats screen so nobody wonders why tonight's game is missing.

### D. Friends won't know a new build exists
Friends will install this sprint's APK to import their history. After that, every fix needs them to update by hand,
and nothing tells them.

The old app's flow:
- a check on every start (at most every 10 min);
- an "Update available" card on Home with "What's new" (3 bullets, See all);
- **Update downloads the APK inside the app** with a progress bar, and Android's "Update this app?" opens;
- "Updated to vX" once after updating;
- a background notification between 11:00 and 17:00;
- Settings: Check for updates, last check, version, New version alerts on / off;
- the lobby warns about players on an older version.

### E. Smaller things found on the way
- History cards say "1 rounds" (an old plural bug).
- The online History tab has no empty-state hint about Wi-Fi games.
- Game detail pages show roles and events but no MVP. The old recap card had one.

## Scope

### S8-1 Stats screen
- AC1: **Home → Stats** (next to History, signed in), and from History's top bar.
- AC2: The five titles as in the old app, same rules, from **valid** games only, each with its line ("67% · 8 wins of
  12", "Caught the Mafia 5 times"…).
- AC3: The leaderboard:
  - ranked by win rate, 3-game minimum, ties: wins then games;
  - unranked greyed with "Needs 3 games";
  - Mafia / Citizen split per row;
  - **you are highlighted**.
- AC4: **Counted:** my online games, my approved Wi-Fi games, my imported old games, valid only. A line under the
  board says so: "From your online, approved Wi-Fi and old-app games. One-phone games aren't recorded."
- AC5: Computed on the server (`GET /v1/stats`). Every phone shows the same, and a game made invalid by the host
  disappears from everyone's stats.
- AC6: **All players (his answer 1):** a second tab, **Everyone**, ranks all accounts.
  - **[BA] fairness rules:**
    - only games the server can vouch for count: online games and approved Wi-Fi games, valid only. Imported old games
      are self-reported, so they count on "Mine" but not on Everyone;
    - **10-game minimum** to be ranked;
    - top 100 shown, plus your own rank if you're lower.
  - **[BA] privacy:** Profile → "Show me on the Everyone leaderboard" (on by default). Off removes you from it; your
    own stats are unchanged. Banned accounts never show.

### S8-2 Player profile
- AC1: Tap a leaderboard row, a player in a game's detail page, or a friend: the profile.
  - win rate;
  - best role;
  - as Mafia;
  - as Citizens' side;
  - killed most by;
  - wins by role (bars);
  - moments;
  - last 8 games (W / L).
  
  Same rules as the old app.
- AC2: An account's profile also shows their card (avatar, @handle, favourite role) and the friend button. A name
  (guest or old-app) shows the name only.
- AC3: "My stats" from my own Profile screen.

### S8-3 Import my old history
- AC1: **Profile → Import old history**: a short guide (old app → Settings → Group history → Create group → Share the
  code), a code box, Import.
- AC2: The server reads that group from the old relay, **server to server**, once per request. The old app and its
  relay are not changed.
- AC3: **Only real games:** a game is imported only if every name in it is on the real-player list (your list, kept in
  a D1 settings row so it can grow; **empty until you send the names**, so until then an import reports "0 imported"
  and keeps nothing). The rest is counted and reported: "42 games imported, 17 skipped (test or unknown
  players)".
- AC4: **Names → accounts:**
  - the list maps each old name to a new account when that friend has one ("Halawy → @halawy");
  - the importer's own name is picked from the list on the import screen ("Which one were you?");
  - a later mapping applies to games already imported.
- AC5: Validity kept; duplicates skipped (same game imported twice, or by both of you from one group); each game kept
  raw with its format version.
- AC6: History gets an **Old app** tab with the same detail page (roles, what happened).
- AC7: A wrong or unreachable code says so ("No group with this code", "The old server didn't answer, try again").

### S8-4 New builds reach the testers (as before, until Play)
- AC1: **A release is made only when you say so:** a "Release" workflow in GitHub Actions, run by you (or by me when
  you ask), with the "What's new" bullets as its input. It builds a **release** APK (smaller and faster than today's
  debug build), signed with the upload key, and publishes it as a GitHub Release of the public repo.
- AC2: The app checks for a newer release on start and on return (at most every 10 min, quiet offline). Home shows
  **"Update available · What's new"** with the bullets and **Update**.
- AC3: **Update feels automatic (his answer 3):** Update downloads inside the app with a progress bar and installs
  through Android's PackageInstaller.
  - The **first** in-app update asks twice: Android's "Allow installs from Mafia Dealer" and "Update this app?".
    Android requires both for any app outside Play, as the old app did.
  - From then on the app is its own installer, so on **Android 12 and newer the next updates install without any
    prompt**: "Updating…", then the app closes and Android's notification "Mafia Dealer updated · tap to open" brings
    it back.
  - Older Android keeps the one "Update this app?" tap.
  - Any failure falls back to opening the download page.
- AC4: After updating: "Updated to vX" once, with its bullets.
- AC5: **The release sends a push** "Mafia Dealer X is out" to every phone with the app (an FCM topic, no account
  needed). It replaces the old 11:00–17:00 alarm and Telegram. Settings: New version alerts on / off, Check for
  updates, version and build.
- AC6: The lobby marks players on an older build (online and Wi-Fi), like the old app.
- AC7: **Switched off for the Play build:** Google Play doesn't allow an app to update itself, so the Play build
  (later) drops the in-app download and the install permission.

### S8-5 The small things (E)
- AC1: "1 round" / "2 rounds" (and the Arabic plural forms).
- AC2: The MVP on a game's detail page, as on the end screen.

## [BA] proposals (all four accepted, now in scope)
- **P1. Filters on Stats:** All / Online / Wi-Fi / Old app, and All time / Last 30 days. Party games usually let a
  group see "this season" without old games drowning it.
- **P2. Best partner:** on a profile, the teammate you win most with as Mafia (a twin of "killed most by").
- **P3. Share my profile:** a screenshot-friendly card (like the old recap card) to send to the group chat.
- **P4. Title changes in the bell:** "Dareer took Best Detective from you". Cheap, now that the bell and push exist,
  and it's what brings people back.

## Not in Sprint 8
- Neon theme, host defaults, minimize lobby, bell history, Invite from Home, "Close Mafia Dealer?" (Sprint 9).
- The welcome (Sprint 10).
- Groups (your prompt).
- Google Play (last).

## How [QA] will verify
- **Server:**
  - stats math against hand-counted games: every title's rule, ties, the 3-game minimum, invalid games;
  - an online + Wi-Fi + old game mix;
  - accounts vs names;
  - a game turned invalid leaving everyone's stats.
- **Import, adversarial:**
  - a fake old relay;
  - an unknown code;
  - the relay down;
  - test names skipped;
  - the same group twice and by two people;
  - a malformed old game;
  - a huge group (200 games);
  - a name mapped after import.
- **Update:**
  - an older / same / newer release;
  - offline;
  - the download interrupted;
  - "Updated to vX" exactly once;
  - alerts off.
- **Widget tests:** Stats, profile, import screen, Update card, Settings rows, EN/AR, small phone, large text.
- **Emulator in CI:** the release APK installs and starts; Stats and a profile from a real local Worker with seeded
  games.
- **The [QA] UX pass:** every new screen in EN and AR.
- **Exploratory session:** drive the real app on an emulator here, like a tester (see decision 5).
- **What only you can prove:**
  - the in-app update on your phone (Android's install prompt);
  - the release push;
  - your real old history imported from your phone.

## Decisions (answered above in Status)
1. **Whose games count:** the games I played in, ranking everyone in them (recommended until groups exist)?
2. **The real-player list for the import:** the exact names as written in the old app, and who is who (which one is
   you, which one is your friend with the history).
3. **Releases:** a GitHub Release made only when you ask (recommended), with the APK downloadable by anyone with the
   link, since the repo is public?
4. **[BA] proposals P1–P4:** which ones go in?
5. **An emulator on this PC** for the [QA] exploratory session: about 1.5 GB of Android system image, started only for
   testing and closed after. OK?
