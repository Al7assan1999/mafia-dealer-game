# Sprint 7 PRD: push notifications, Wi-Fi games into online history, the tie rule

Status: **signed off and built 2026-11-23** with the recommended answers to decisions 1–5 (results: `docs/sprint-7-report.md`). Not committed.

His instructions of 2026-11-23 behind this sprint:
- Start on Firebase push notifications.
- Engine oddities stay, except ties: "any tie implies skip". A dead Detective still sees their last result.
- Anything about publishing on Google Play waits until the app is fully finished.
- Sprint 7 = the Wi-Fi approval process (agreed in Sprint 6).

## [BA] Audit

Walked as a player on the real screens (`app/tool/screens_test.dart`, English and Arabic, 360 px): Home signed in and
signed out, the bell, Profile, the end of a game, and the Wi-Fi screens. The code was read where no screenshot exists.

### A. Nobody hears about anything while the app is closed
- Invites, "Let me in" requests, friend requests and "X let you in" reach a player only **while the app is open**
  (the bell, through the hub socket). With the app closed, nothing happens: a friend invites you, and you find out
  an hour later.
- The old app had Telegram for this. The new one has nothing yet. This is the biggest gap a player feels today.
- The Wi-Fi approval below depends on it too: every player must confirm, and nobody will confirm a request they
  never see.

### B. The bell can only be read and dismissed
- *Bell screenshot (EN/AR):* "Dareer wants to be your friend" has only an ✕. To accept, you must know to go to
  Friends. An approval request needs **Confirm / Not me** right there.
- Arabic mirrors correctly (avatar on the right, ✕ on the left).

### C. Wi-Fi games are invisible to guests
- **Bug:** History opens only when signed in (`main.dart`: the History link is behind `account.signedIn`). Sprint 6
  saves Wi-Fi games on every phone, **guests included**, but a guest can never open them. A guest who plays ten Wi-Fi
  games sees nothing.
- *End-of-game screenshot:* nothing tells a signed-in Wi-Fi player the game can be added to online history. The
  only place to ask for it should be the end screen and History → Wi-Fi.

### D. Ties at night
- The day vote already treats a tie as "nobody is out".
- At night the Mafia's tie is **broken at random**: two Mafia picking different people (or one picking "skip") lets
  chance choose, and can spend the one-time skip by luck.
- Your rule: **any tie means no kill.**

### E. Not covered by screenshots yet
The screens tool has no History screen (the Online / Wi-Fi tabs) and no Settings screen. [QA] adds both in this
sprint.

## Scope

### S7-1 Push notifications (Firebase Cloud Messaging)
- AC1: When signed in, the phone registers for push.
  - The token is tied to the session, so it's removed on sign-out, device removal and account deletion.
  - On Android 13+ the "Allow notifications" prompt appears **once, after sign-in**, not on first launch.
- AC2: **A push is sent only when the app isn't open** (no live hub socket). An open app keeps today's banner and bell.
  Covers:
  - an invite;
  - a "Let me in" request;
  - "X let you in";
  - a friend request and a friend accepted;
  - a Wi-Fi confirmation request and the approval result (S7-2).
- AC3: **Tapping the notification opens the right place:** the room (join), the bell, or Friends.
  - An expired invite opens the bell with "This invite has expired".
- AC4: **Android notification channels:** Invites, Friends, Game approvals. The player turns each one off in Android's
  own settings. Settings shows one row, "Notifications", that opens them.
- AC5: Texts follow the phone's app language (EN / AR). One notification per sender and kind is replaced, not
  stacked, so ten invites from Sami show as one.
- AC6: The Worker sends through the FCM HTTP v1 API with a Google service account. The key is a Worker secret, set by
  CI from a GitHub secret, never in the repo. If push isn't configured (no key), everything else works as today.

### S7-2 Adding a Wi-Fi game to online history (the approval process)
- AC1: **Who may ask.** A signed-in **host**, for a finished Wi-Fi game in which **every seat was a signed-in player**.
  - The button appears on the end screen and in History → Wi-Fi: "Add to online history".
  - If a guest played, the button is replaced by a line: "A guest played, so this game stays on the phones."
- AC2: **The request** carries the game's record, the seats (account, name), when it was played and the app version.
  It's stored **raw and untouched**, with the version of the rules it was judged by.
- AC3: **The automatic checks** run at once on the server. Each failure has a clear reason shown to the host:
  - the record replays to a finished game on the server's engine;
  - player count within limits;
  - a believable length (minimum seconds per round);
  - not older than N days;
  - at most N requests per host per day;
  - not already sent (same record).
- AC4: **Each other player confirms.** A bell item (+ push): "Sami asks to add the Wi-Fi game of 23 Nov (6 players,
  Mafia won) to online history." It shows their seat and role, with **Confirm** and **Not me**.
  - All confirm within the window (default 48 h): **approved**.
  - Any "Not me": **declined**.
  - Window over: **expired**.
  - The host gets the result in the bell (+ push).
- AC5: **Kept apart, as decided:** an approved game sits in History → **Wi-Fi** with an "Approved" mark. It's stored in
  D1, so it also shows on the player's other phones. Online history stays only server-judged games.
- AC6: **Changeable later without losing data:**
  - the limits live in a D1 settings row (`wifi_rules`, with a version number);
  - every request keeps its raw record and the rules version, so a future rule can judge old requests again;
  - migrations only add tables or columns.
- AC7: **The host's own phone also shows the request's status** in History → Wi-Fi: Waiting for 3 of 5 / Approved /
  Declined (reason) / Expired.

### S7-3 Ties at night mean no kill
- AC1: A tie in the Mafia's vote (between two players, or between a player and "skip") means **nobody is killed that
  night**. The morning says nobody died, like a save.
- AC2: A tie **doesn't spend the one-time skip** (nobody chose to skip). *Decision 3.*
- AC3: The day vote is unchanged: a tie already means nobody is out.
- AC4: **Old games still replay exactly:** the tie rule is stored in the game's rules when roles are dealt. Records
  saved before this sprint (online history, Wi-Fi history, a Wi-Fi game being resumed) keep the old behavior. Both
  engines (TypeScript and Dart) change together, and the shared test games prove it.
- AC5: Unchanged by your decision: a dead Detective still sees their last result. `QUIRKS.md` records both decisions.

### S7-4 Fixes from the audit
- AC1: **History is open to everyone.** Signed out, it shows the Wi-Fi tab alone (online history needs an account).
- AC2: **The bell gets actions:** Accept on a friend request; Confirm / Not me on an approval request.
- AC3: The screens tool renders History (both tabs, with an approved and a waiting game), Settings, and the bell with
  an approval request, in EN and AR.

## Not in Sprint 7
- **Anything for publishing on Google Play** (your instruction): privacy policy, account-deletion web page,
  data-safety form, closed test, AAB, In-App Updates, the licenses page. All of it waits until the app is finished.
- **App links** (`mafiadealer.app/j/<code>`): they need the domain, so they go with the Play work.
- **Groups:** waiting for your prompt.
- **Moving old players:** a separate plan for your approval (`docs/old-players-plan.md`).

## What I need from you before [Developer] starts push (S7-1)
I can't create Google accounts or projects for you. These are console steps, about 10 minutes:
1. **console.firebase.google.com → Add project → pick the existing Google Cloud project `mafia-dealer-game`**, so
   Firebase and the sign-in setup share one project. Analytics: off.
2. **Add app → Android:**
   - package `com.mafiadealer.game`;
   - nickname "Mafia Dealer";
   - SHA-1 `CA:44:FD:43:46:80:A8:17:63:58:38:83:30:C8:1E:6F:0A:8C:FA:AB`.
   
   Download **google-services.json**. Don't send it in chat.
3. **GitHub → repo Settings → Secrets → Actions → new secret `GOOGLE_SERVICES_JSON`:** paste the whole file's
   contents. CI writes it into the build. The file stays out of git.
4. **Project settings → Service accounts → Generate new private key.** This downloads a JSON key the server uses to
   send pushes. Save it as the GitHub secret **`FCM_SERVICE_ACCOUNT`** (the whole file). Delete the downloaded copy
   afterwards.
   - If Google says key creation is disabled by an organization policy, tell me, and we'll use another route.
5. For your own local builds, put `google-services.json` in `app/android/app/`. It's already git-ignored.

Steps 1–4 are needed for real pushes. [Developer] can build and test S7-1 against a fake FCM before you do them; only
real delivery waits.

## How [QA] will verify
- **Server (vitest):**
  - push sent only when the hub has no socket, to every device of the user, with the right channel and the
    replace-key;
  - tokens dropped on sign-out, device removal and account deletion;
  - a 404 "unregistered" from FCM deletes the token;
  - all against a fake FCM endpoint.
- **Approval (vitest), adversarial:**
  - a forged record that doesn't replay;
  - a seat claiming someone else's account (that player says Not me);
  - the same record twice;
  - over the daily limit;
  - too short;
  - too old;
  - a guest seat;
  - a non-host asking;
  - the confirm window running out;
  - two confirmations racing;
  - the settings row changed between request and decision.
- **Engines:** new tie tests in TypeScript and Dart, plus the shared fixtures. Every old record still replays to the
  same result.
- **Widget tests:**
  - History signed out;
  - the request button and its guest line;
  - waiting / approved / declined / expired in History;
  - Confirm / Not me and Accept in the bell;
  - a notification tap opening the right screen.
- **Emulator in CI:** a hosted Wi-Fi game with three signed-in scripted players, sent for approval, confirmed by the
  scripted players, then shown as Approved in History.
- **The [QA] UX pass:** every new and changed screen in EN and AR, small phone and large text.
- **Your playtest:** a real push with the app closed and the screen off (invite, friend request, confirmation),
  tapping it, and the per-channel switches.

## Decisions needed
1. **One sprint or two:** push and approval together (recommended: the approval needs push to reach the players), or
   push alone first?
2. **Where an approved Wi-Fi game lives:** History → Wi-Fi with an "Approved" mark, synced to all your phones
   (recommended, keeps the logs apart as you said). Or in the Online tab with a Wi-Fi badge?
3. **A Mafia tie and the one-time skip:** a tie means no kill and **keeps** the skip (recommended: nobody chose to
   skip). Or a tie spends the skip too?
4. **Starting limits** (editable later in the settings row):
   - 4–20 players;
   - at least 60 s per round;
   - games up to 7 days old;
   - 10 requests per host per day;
   - 48 h to confirm.
   
   OK?
5. **Push for chat messages:** not included (chat lives only while a room is open). Agree?
