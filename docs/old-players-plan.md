# Plan: bringing the old app's game history into the new app

Status: **revised after Alhassan's answers (2026-11-23), waiting for his approval.** Nothing is built.

## His answers
1. **Only the phone history** moves (no accounts, friends or profiles). Leave out the games from my tests ("Player 1",
   "Player 2"…).
2. The old games must **count in the new app**, not sit in a read-only tab: "almost only me and my friend have old
   history, so we need to keep going". He offered the exact player names.
3. The old data is deleted 3 months after the Play release: OK.
4. Timing: just before the Play work: yes.
5. **Don't change `../mafia-dealer`.** No new old-app version, no relay change.

## How, without touching the old app
The old app already has **Settings → Group history** (v2.4):
- "Create a group" uploads every game on the phone (`S.log`, up to the last 100) to the old relay, and returns an
  8-character code.
- Anyone with the code can read the games back (`GET /g/<CODE>` on `mafia-relay`).

Nothing new is needed on the old side. It's the feature the old app shipped with.

**Steps for you and your friend (once, in the old app):**
1. Old app → Settings → Group history → **Create group**. Your games upload, and the code shows (Share copies it).
2. Your friend taps **Join** with your code, so their games join the same group. Duplicates are skipped by the old
   relay. Or they create their own group and send their own code.
3. In the new app: Profile → **Import old history** → enter the code.

## What the import does (new app and server only)
- The new server reads the group from the old relay once, **server to server**. The code is the only key.
- **Test games are left out** with your list of real player names. A game is imported only if **every** name in it is
  on your list. That drops "Player 1…20", "A B C D" and anything else my tests made.
- **Names become accounts.** Each name on your list can be linked to a new-app account (yours, your friend's), so the
  imported games count in **that person's** stats. The other friends stay names until they have accounts; their games
  can be linked later from the same list.
- **Validity is kept.** Games marked invalid in the old app stay invalid (shown, not counted), as before.
- **Kept raw**, in its own table with the old format version:
  - names, roles, alive, winner, days, the old event log, valid, the date;
  - so a later fix can re-read them without asking the phones again.
- **They count in stats:** the leaderboard, titles and player profiles (Sprint 8, see `docs/old-app-parity.md`). The
  old games show in History as **"Old app"** games, next to online and Wi-Fi, with the same detail page (roles, what
  happened).
- **Once per game:** importing the same code twice, or your friend importing the same group, adds nothing new.

## What I need from you
1. **The exact player names** as they're written in the old app, with who is who. For example: Alhassan (you), Dareer,
   Halawy, Farouq, Sami, Hokan, Fater, Khaddour. Tell me which one is your friend with the history.
2. Whether games from **one-phone (offline) play** count in stats. Nearly all old games are offline, and the new app
   doesn't log offline games (decision of 2026-11-22). See question 2 in `docs/old-app-parity.md`.

## When
With **Sprint 8 (Stats)**, because the import only matters once stats exist. Your answer 4 put it "just before the
Play work"; Stats is the earliest it can mean anything. Your call.

## Size
- Server: one import endpoint, one table + migration and rollback, the name list.
- App: the Import screen in Profile, "Old app" games in History.

About a third of a sprint, inside Sprint 8.

## The old data afterwards
3 months after the Play release, the old relay's group data can be deleted by you in Cloudflare. I don't change the
old relay (answer 5).
