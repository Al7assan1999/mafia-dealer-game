# Sprint 19 PRD: the suggestions box (1.2.0)

His request (2026-11-26): players send an opinion or report a problem, with at most one screenshot. We read them and
empty the box. Each player has a limit, so the box can't be spammed.

## [Ben · BA] audit
- What we have: Report a player (Sprint 5), the admin's report queue (Profile → Reports), photo upload for avatars (the
  app shrinks it to a small JPEG first), and per-account rate limits on the server (rooms, imports, sign-in).
- What's missing: no way to send the team anything. Today problems reach him by WhatsApp, with no app version and no
  screenshot.
- Old app: nothing like it (parity: none needed).
- Cost: the box lives in the same database as games. A screenshot is kept small (see S19-2), and the box has a total
  cap, so the database can't be filled.

## Stories and acceptance criteria

### S19-1 Send a suggestion or a problem
- AC1. Settings has **"Suggestions & problems"** (Arabic: «اقتراحات ومشاكل»). It opens a short form:
  - the type: **Suggestion** or **Problem**;
  - the text: required, 10 to 1000 characters;
  - **one** optional screenshot, picked from the gallery (a picked one can be removed or replaced).
- AC2. Send shows "Thanks, it was sent" and closes the form. A failed send keeps what was typed, says why, and can be
  tried again.
- AC3. The phone adds by itself, and the form says so: app version, build, language, and the Android version.
- AC4. Only for a signed-in player (the limit needs an account). Signed out, the item says "Sign in to send" and opens
  sign-in.
- AC5. Works in English and Arabic, on a small phone with large text.

### S19-2 Limits (against spam)
- AC1. Each player can send **3 per day**, and can have at most **5 waiting** in the box. Over either one, the form
  says "You've sent a lot today; try again tomorrow" (or "…once we've read your last ones") **before** they type.
- AC2. A screenshot is shrunk on the phone to at most 1280 px on its long side, as JPEG, **300 KB at most**. The server
  refuses anything bigger, or anything that isn't a picture.
- AC3. The whole box holds at most **300 waiting**. When it is full, new sends get "The box is full right now", and
  nothing is lost silently.
- AC4. A banned account can't send.
- AC5. The text is stored as text only (no links opened, nothing run), and shown the same way.

### S19-3 The box (admin only)
- AC1. Profile → **Suggestions** (only for admin accounts, as Reports), with a count of the unread ones.
- AC2. Newest first. Each shows: the type, who sent it (name and @username, tap to open their profile), when, the
  text, the version and phone details, and the screenshot as a small picture (tap to see it full size).
- AC3. Opening one marks it read. A filter switches between All, Suggestions and Problems.
- AC4. **Delete** one, or **Empty the box** (asks first: "Delete all N? This can't be undone"). Deleting removes the
  screenshot too. Deleted items free that player's "5 waiting".
- AC5. Nobody else can read, list or delete them: the server checks the admin on every call.

### S19-4 Release
- AC1. 1.2.0. The server keeps accepting 1.1.0 / 1.1.1 at tables (no new game rule). Older phones just don't have the
  form.
- AC2. Migration 0012 (a new table, only added) with a rollback. It's applied by CI before the deploy, as usual.

## [Ben · BA] proposals (yours to accept or drop)
- **P1 · An answer back.** In the box, "Mark done" sends the player a bell note: "Your suggestion was read — thank
  you" (or "The problem you reported is fixed in 1.x"). Players who hear back keep sending.
- **P2 · Report from where it happened.** On a game's end screen and in History, "Report a problem with this game"
  opens the form with the game already attached. You then see that game's record next to the text.
- **P3 · "My messages".** The player sees what they sent and whether it's been read. This answers "did it arrive?".

## Questions for you
1. Signed-in players only (AC4)? Default: **yes** (the per-player limit needs an account).
2. Limits: **3 a day, 5 waiting, one screenshot of 300 KB at most, 1000 characters, 300 in the whole box**. OK, or
   other numbers?
3. Only admin accounts (you) see the box? Default: **yes**.
4. "Empty" deletes for good, screenshots included (nothing kept). Default: **yes**.
5. Proposals P1, P2, P3: which ones?
6. Version **1.2.0**?

## His answers (2026-11-26)
1. Signed-in only: yes. 2. Limits: yes (3 a day, 5 waiting, one screenshot ≤ 300 KB, 1000 characters, 300 in the box).
3. Admin only: yes. 4. Empty deletes for good: yes. 5. Proposals: "all options are acceptable so you decide": the
team takes **P1, P2 and P3**; P2 kept small (an online game's id attached, from the end screen and History).
6. 1.2.0: yes.
