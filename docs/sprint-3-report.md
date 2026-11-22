# Sprint 3 Release Report: accounts and friends in the app

2026-11-22. Built against `docs/sprint-3-prd.md` (signed off the same day with the recommended answers). **Not
committed yet.** On the next push, CI runs the new emulator test against a local Worker, and the deploy applies
migration `0004` to the live D1.

## Result: green locally
- **Server:** **42/42** vitest. New: saved names and setup (limits, ownership, deleted with the account), the Hub's
  automatic pong, and a guard that the test-only code route answers 404 without local test mode. Type check clean.
- **App:** `flutter analyze` clean. **31/31 widget tests** (20 from Sprint 2 + 11 new account tests against a fake
  server).
- **A local Worker in test mode,** walked by hand: email start → read the code → verify → token. That's exactly what
  the emulator test does.
- **Engines:** unchanged (34 TypeScript + 5 Dart groups).

## Found and fixed on the way
1. **Release builds had no INTERNET permission.** Only the debug manifest had it, so a Play build could never have
   reached the server. Added to the main manifest.
2. **CI-built APKs could never use Google sign-in:** each was signed with a throwaway key. All builds, local and CI,
   debug and release, are now signed with the upload key.

## Against the acceptance criteria

| AC | Status | Evidence / notes |
| --- | --- | --- |
| S3-0 AC1 Google Cloud | ⏳ you | The project exists. The consent screen, test users and the two client IDs are next (step-by-step list sent). |
| S3-0 AC2 signing key | ✅ | RSA 4096, valid until 2056, generated here into `C:\Users\WGN\.android-keys\`. It's in GitHub secrets (`ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`); the password never appeared in chat. **Keep a backup** of `mafia-dealer-upload.jks` + `pass.txt` (e.g. in your password manager): it's your Play upload key. SHA-1 `CA:44:FD:43:46:80:A8:17:63:58:38:83:30:C8:1E:6F:0A:8C:FA:AB`. |
| S3-0 AC3 `GOOGLE_CLIENT_IDS` | ⏳ | Set as soon as you send the IDs. The app also needs the Web ID at build time (a CI repository variable). |
| S3-1 AC1 Google | ✅ written, ⏳ real Google | Credential Manager via `google_sign_in` 7. Tested with a fake: success, cancel (no message), not configured (the button says so). The real flow needs your client IDs and a phone. |
| S3-1 AC2 email code | ✅ | Tested: wrong code, slow_down, no network, bad email. The resend waits 60 s. On the live server, email answers "isn't available yet, use Google" until Resend and the domain exist (decision 1). |
| S3-1 AC3 handle first | ✅ | Tested: too short, taken, then a free one. |
| S3-1 AC4 token storage, silent sign-in, 401 | ✅ | `flutter_secure_storage` (Android encrypted storage). Tested: silent restore; a refused session signs out cleanly and the game in progress stays. |
| S3-1 AC5 works offline | ✅ | Tested: offline start shows the cached profile marked "Offline"; offline play works; every call times out at 10 s. |
| S3-2 AC1 profile edits | ✅ | Tested: name, show online. |
| S3-2 AC2 avatar | ✅ | A preset tested. Photo: a 3000×2000 picture becomes a 256×256 JPEG ≤150 KB on the phone (tested end to end). |
| S3-2 AC3 devices | ✅ | List, sign one out, sign out here. |
| S3-2 AC4 delete account | ✅ | Tested: disabled until "delete" is typed; afterwards signed out, token and cached profile gone, offline play works. |
| S3-3 AC1–AC2 friends | ✅ | Tested: add by @handle, unknown handle, asked both ways at once = friends, unfriend asks first. |
| S3-3 AC3 presence | ✅ written, ⏳ CI | Live through the hub socket; checked by the emulator test. |
| S3-3 AC4 share | ✅ written | Android's share sheet with your @handle (not testable in widget tests). |
| S3-4 AC1 hub socket | ✅ written, ⏳ CI | Ping every 10 s; reconnect after 1, 2, 4 … 30 s; closed in the background. The emulator test checks a friend request arriving live. |
| S3-4 AC2 bell | ✅ | Tested: unread count, opening reads them, clear. |
| S3-4 AC3 Hub auto-pong | ✅ | Server test. |
| S3-5 AC1 server | ✅ | `0004_saved.sql` + rollback, `GET`/`PUT /v1/me/roster` and `/v1/me/setup`, server tests. |
| S3-5 AC2–AC3 app | ✅ | Tested: the phone's names merged into the account (no duplicates) and removed from the phone. |

## How to finish the last open piece
1. Send me the two client IDs (steps already sent).
2. I set `GOOGLE_CLIENT_IDS` in `server/wrangler.jsonc` (deployed by CI) and the repository variable
   `GOOGLE_SERVER_CLIENT_ID` (used for the APK build). Both are public values.
3. You install the next CI APK and sign in with Google, using one of the test-user Gmails.

## Caveats
- **Google sign-in is untested for real** until step 3 above.
- **Email sign-in on the live server** waits for Resend + `mafiadealer.app`, as decided.
- **The emulator account test only runs in CI** (no emulator here). Its server is a local Worker started by the job.
- **New cost:** none. Keep-alive pings to the hub no longer wake it; the hub socket closes in the background.
