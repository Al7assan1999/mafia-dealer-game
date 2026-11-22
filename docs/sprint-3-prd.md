# Sprint 3 PRD: accounts and friends in the app

Status: **signed off and built 2026-11-22** (results: `docs/sprint-3-report.md`). Not committed.

## Audit
- **The server already has it all** (phase 2/3, live): email code + Google sign-in, sessions per device,
  profile (@handle, display name, avatar preset 0–9 or a photo ≤150 KB, favourite role, "show me online"),
  account deletion, friend requests / accept / decline / unfriend, public cards with presence, the bell
  (friend_request, friend_accept notes), the per-account Hub socket (presence + live notes).
- **The app has none of it:** offline play only.
- **Nobody can sign in on the live server yet,** for three reasons on your side:
  1. **Google:** there's no Google Cloud project yet: no OAuth consent screen, no client IDs. `GOOGLE_CLIENT_IDS` is empty.
  2. **Email codes:** there's no Resend key. Resend can also only email *anyone* from a verified domain, and
     `mafiadealer.app` isn't bought yet. Without a domain, Resend only delivers to the Resend account's own address.
  3. **A fixed signing key:** Google ties Android sign-in to the app's signing-key fingerprint (SHA-1). Today every
     CI run signs with a fresh throwaway debug key, so a CI-built APK could never sign in with Google.
- **Gaps found in the server:**
  - The Hub answers `ping` by waking itself up, the same cost problem Sprint 1 fixed for rooms.
  - Saved names and the last setup have no place in D1 yet (decision 2 of 2026-11-22).
- **The old app** had: sign-in, profile with avatar presets and a photo, favourite role, "show me online", friends
  with Friends / Requests / Sent tabs, add by @username, share my @username, a bell with notes, account deletion.

## Scope

### S3-0 Prerequisites (you, guided step by step; nothing is built against Google until they exist)
- AC1: **Google Cloud:**
  - a project "Mafia Dealer";
  - an OAuth consent screen (External, **Testing** mode, your friends' Gmail addresses as test users, up to
    100, so there's no Google review yet);
  - a **Web** client ID (the server checks tokens against it);
  - an **Android** client ID for `com.mafiadealer.game` + the SHA-1 of the signing key.
  
  This is also the region check for Google.
- AC2: **The signing key:** I generate one release/upload key (`keytool`) and store it only in GitHub Actions
  secrets. You keep one backup copy offline: it becomes the Google Play upload key. CI and local builds sign with it,
  so every APK has the same SHA-1.
- AC3: `GOOGLE_CLIENT_IDS` set to the Web (and Android) client IDs, deployed by CI.

### S3-1 Sign-in
- AC1: "Continue with Google" through Android's Credential Manager. The app sends the Google ID token to
  `/v1/auth/google`. Cancelling, having no Google account on the phone, or no network each show a clear message.
- AC2: Email: enter an email → "we sent a 6-digit code" → enter it. Wrong code, expired code (10 min), too many tries
  (5) and "slow down" (rate limits) each have their own message. "Resend code" waits 60 s.
- AC3: A new account picks its @handle and display name before anything else. `handle_taken` is shown inline.
- AC4: The session token lives in Android's encrypted storage, never in plain preferences. Reopening the app signs
  in silently. A token the server refuses (401) signs out cleanly to the sign-in screen, and the game-in-progress
  stays.
- AC5: **The app works fully without an account or without network.** Offline play never waits on the server.
  Account screens show "offline" instead of spinning forever (10 s timeouts).

### S3-2 Profile and devices
- AC1: Edit handle, display name, favourite role and "show me online"; each saved with a visible success or error.
- AC2: Avatar: one of the 10 presets, or a photo from the gallery, cropped square and compressed to ≤150 KB on the
  phone before upload.
- AC3: "Signed-in devices": list them, sign one out, sign out here.
- AC4: **Delete my account** (a Play requirement): it asks, you type "delete", the server erases the account, and
  the phone forgets the account data. Offline play still works afterwards.

### S3-3 Friends
- AC1: Add by @handle (with or without the @); the result is a card with the relationship: send a request, or
  accept if they already asked.
- AC2: Tabs Friends / Requests / Sent: accept, decline, take back, unfriend (unfriend asks first).
- AC3: Friends show presence live: offline, online, in a lobby, in a game ("show me online" respected).
- AC4: "Share my @handle" opens Android's share sheet with the old app's text.

### S3-4 Live: the Hub socket and the bell
- AC1: While the app is in the foreground, one Hub socket: a ping every 10 s; reconnects with backoff (1, 2, 4 …
  30 s) when the network comes back; closed in the background.
- AC2: The bell: an unread count, notes for friend requests and accepted requests; opening a note marks it read;
  delete one or all.
- AC3: **Server:** the Hub answers `ping` with Cloudflare's automatic reply, as rooms do (no wake-up, no cost).

### S3-5 Saved names and setup in D1 (decision 2)
- AC1: **Server:**
  - migration `0004`: tables for saved names and the last setup, with a rollback;
  - `GET`/`PUT /v1/me/roster` (at most 30 names, 18 characters each);
  - `GET`/`PUT /v1/me/setup` (counts + rules, checked with the engine's limits);
  - both deleted with the account.
- AC2: **App:** signed in, the setup screen's name chips and the last setup come from the account. Signed out, they
  come from the phone.
- AC3: On the first sign-in on a phone, its recent names are merged into the account and then removed from the phone.

## Not in Sprint 3
- online rooms, invites and join requests (Sprint 4);
- Wi-Fi play (Sprint 5);
- push notifications and the web page for account deletion (Sprint 6);
- groups (waiting for your prompt).

## How QA will test
- **Server:** vitest for roster / setup (limits, ownership, deletion with the account) and the Hub's automatic
  pong.
- **App widget tests with a fake server:**
  - every sign-in path and error: Google cancelled, wrong / expired code, slow_down, handle_taken, 401 mid-session;
  - profile edits, the avatar upload size limit;
  - the friend flows (asked both ways at once, unfriend);
  - the bell, account deletion;
  - airplane mode everywhere (nothing hangs, offline play untouched);
  - English + Arabic at 3 phone sizes.
- **Emulator in CI against a real local Worker** (`wrangler dev` on the runner, with a test-only setting that prints
  the email code to the log instead of sending it): sign up by email, set a handle, two accounts befriend each other,
  presence turns on, the bell shows the request, delete the account.
  
  That setting can't reach production: it isn't in `wrangler.jsonc`, and the deploy job never sets it.
- **Google sign-in can't be automated** (it needs a real Google account). It's on your manual playtest list.

## Decisions needed
1. **Email sign-in before the domain exists:** ship Google sign-in first and enable email codes once
   `mafiadealer.app` is bought and verified in Resend (recommended). Or buy the domain now, so both work at the end of
   this sprint.
2. **The signing key:** I generate it and put it in GitHub secrets, and you keep the backup copy (recommended). Or you
   generate it yourself with the command I give you.
3. **Photo avatars in this sprint** (recommended, as the old app had them), or presets only for now?
4. **Local names on the first sign-in:** merge them into the account and remove them from the phone (recommended), or
   keep both?
5. **New app packages** (all widely used):
   - `google_sign_in` (Credential Manager);
   - `flutter_secure_storage` (the token);
   - `http`;
   - `share_plus`;
   - `image_picker` + `image` (crop and compress the photo).
