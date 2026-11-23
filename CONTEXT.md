# Handoff: Mafia Dealer: Party Game (read this first)

The Google Play successor of Mafia Dealer, an app for the Mafia party game made for Alhassan and his friends. The old
sideloaded app lives in `../mafia-dealer` (its CONTEXT.md has the full history up to v2.20.1) and stays untouched;
files are copied from there only when a phase needs them.

## Ground rules
- Features go: discuss → plan → Alhassan approves → build. Ask when something is unclear.
- Never commit, push, deploy or publish unless he asks for that action.
- Never commit secrets (see .gitignore); they live in GitHub Actions secrets and on the VPS.
- Narration and sounds English only; UI English + Arabic with working RTL.
- Don't start his apps or servers.

## Decisions (2026-11-19)
- Name "Mafia Dealer: Party Game", package `com.mafiadealer.game`, domain `mafiadealer.app` (Cloudflare Registrar; to be bought by him).
- Google Play: Capacitor (Gradle, AAB); Play In-App Updates instead of self-updating; report / block in chat; account
  deletion in the app and on a web page; privacy policy; closed test with 12 testers. Reviewers use offline / Wi-Fi play
  and Google sign-in.
- Backend: **Cloudflare** (decided 2026-11-19, replacing a friend's VPS: 1 shared vCPU at 100%, ~1.7 GiB RAM free).
  A TypeScript Worker for the REST API, **D1** (SQLite) for accounts / friends / history, one **Durable Object per
  online room** running the shared engine (the server judges; no host takeover needed), plain WebSockets with
  hibernation. Deployed only by GitHub Actions. Migrations: D1 SQL files with a rollback file each, applied in CI
  before the deploy. Free plan first; Workers Paid ($5/month) when the daily limits get close.
- Wi-Fi and offline play need no server.
- Sign-in: email 6-digit code (Resend) + Google (Credential Manager through our own Kotlin plugin). No username or
  password. Public @handle for friends, emails never shown. Sessions: opaque random tokens, stored hashed, per device.
- Push: Firebase Cloud Messaging in the first Play release (no Telegram).
- Cloudflare also gives DNS + registrar for the domain, TLS, DDoS protection and caching.
- Backups: D1 Time Travel (point-in-time restore) plus a scheduled, encrypted `wrangler d1 export` in Actions.
- Old users: migrate if easy, else a fresh start. Phone history doesn't carry over to a new package without an export.

## Decisions (2026-11-22)
- **The app is Flutter** (not Capacitor). The server stays TypeScript, so the rules exist twice: TypeScript (server,
  online games) and Dart (phone, offline and Wi-Fi). Both must replay `packages/engine/fixtures/records.json`
  identically. (Recommended; Alhassan asked what "two copies" means and hasn't objected.)
- **Data moves off the phone into D1**: history, saved names, the setup. What belongs to the device stays there:
  language, theme, volume, UI flags, the game in progress, the session token (secure storage).
- **Offline play needs no account and is never logged.**
- **Wi-Fi games**: a game with a guest (not signed in) is never logged online. Online and Wi-Fi logs stay separate;
  whether Wi-Fi history lives on the phones is open ("we will see"). Adding a Wi-Fi game to online history is a formal
  request from the host, judged by **automatic rules** (the server replays the record; plus player count, believable
  length, a daily limit, no duplicates; each player confirms). Requests are kept raw and versioned, the limits live in
  a D1 settings row, and migrations only add, so the rules can change later without losing data.
- **Groups**: to be redesigned entirely (Alhassan's prompt still to come).
- **Work runs in sprints as three visible personas, every sprint until the end** (his rule, restated 2026-11-22 after
  I drifted): [BA] audits as a player from screenshots of the real screens, writes the PRD, stops for his sign-off →
  [Developer] → [QA] adversarial tests plus a hands-on UX pass → [BA] acceptance review → Sprint Release Report.
  Read `docs/team-workflow.md` before every sprint.

## Decisions (2026-11-23)
- **Engine oddities:** a dead Detective still sees their last result (kept). **Any tie means skip:** a tied Mafia vote
  kills nobody (was a random pick); the day vote already treats a tie as nobody out. Built in Sprint 7, stored in the
  game's rules so old records replay unchanged.
- **Firebase push starts now** (Sprint 7, with the Wi-Fi approval process).
- **Everything about publishing on Google Play waits until the app is fully finished** (privacy policy, deletion page,
  data safety, closed test, AAB, In-App Updates, app links).
- **Moving old players** (his answers, same day): only the phone history moves, test games ("Player 1"…) left out; the
  old games must count in the new app's stats (not a read-only tab); old data deleted 3 months after Play; timing just
  before the Play work; **`../mafia-dealer` is never changed**. Route: the old app's existing Group history uploads a
  phone's games, the new server imports by the group code (`docs/old-players-plan.md`, revised, waiting approval + his
  name list).
- Sprint 7 answers confirmed (push + approval together, "Approved" mark, a tie keeps the skip, limits, no chat push).
  Firebase: Android app registered with the SHA-1; secrets `GOOGLE_SERVICES_JSON` and `FCM_SERVICE_ACCOUNT` set (key
  checked against FCM with a dry run).
- **[BA] old-app parity audit** (`docs/old-app-parity.md`): the biggest gaps are stats / titles / player profiles, the
  welcome, minimize-lobby, host defaults in Settings, update notices for APK testers. Workflow rule strengthened: the BA
  covers the old app and brings its own proposals; QA states what each test layer can't prove.
- His answers to the parity questions: **Neon comes back as a choice** (Sprint 9); **offline games stay unlogged**;
  new builds announced **"same as before"** until Play (in-app check + download + install, from a GitHub Release he
  asks for, push instead of the alarm; switched off for the Play build); next sprint **Stats + old history** (Sprint 8
  PRD `docs/sprint-8-prd.md`, waiting sign-off).
- graphify set up (graph in `graphify-out/`, git hooks post-commit / post-checkout, Claude hook in
  `.claude/settings.json`; all git-ignored except `CLAUDE.md` and `.gitattributes`).

## Phases
1. **Engine** (done 2026-11-19, not committed): `packages/engine`, 31 tests (setup limits, one per rule, test7/test9
   scenarios, 1,000 random games). Open questions in `packages/engine/QUIRKS.md`.
2. **Server base on Cloudflare** (built 2026-11-19, not deployed yet): Hono + zod Worker, D1 schema
   (`server/migrations/0001_init.sql`), email-code + Google sign-in, sessions, profile, avatars, friends; 17 vitest
   tests in the Workers runtime; `ci.yml` deploys on main once `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` and
   the D1 `database_id` exist; `backup.yml` weekly. The VPS secrets were deleted.
3. **Live play** (built 2026-11-19): `Room` Durable Object per room code (lobby + game on the shared engine,
   per-seat views, night timer as an alarm, chat in room storage deleted with the room), `Hub` per account (presence,
   live bell notes), migration `0002_live.sql` (rooms, presence columns, notifications, games + game_players), REST
   for rooms / invites / join requests / bell / history. His decisions: host controls pass in join order; each phone
   holds its own suspense reveal; a kick that decides the game ends it (engine). 30 server tests (13 live: full
   6-phone game, host hand-over, kick, night timer, continue, close, buzz, chat rules, invites, presence).
4. Replaced by sprints (2026-11-22). **Sprint 1, a game you can trust** (`docs/sprint-1-prd.md`, built 2026-11-22, not
   committed): one change at a time per room (a real race: simultaneous joins lost a member), silent phones closed
   after 30 s (Cloudflare answers the 10 s pings itself), `rev` on every room message with catch-up on reconnect
   (`?rev=`, last 200 events, else `missed`), repeated taps ignored, engine game records with `replay` and 60 shared
   test games, `games.record` (migration `0003`). 34 engine + 38 server tests.
   **Sprint 2, the app exists** (`docs/sprint-2-prd.md`, built 2026-11-22, not committed): tools in `C:\Users\WGN\sdk\`
   (Flutter 3.47.9, Temurin JDK 21, Android SDK 36 + NDK 28.2; licenses accepted with his OK); `packages/engine_dart`
   (byte-identical records with the TypeScript engine); `app/` (offline play on one phone, Noir look, EN/AR + RTL,
   the old narrator clips and rendered sounds, resume after a kill, screen kept on); CI jobs `app` and `emulator`.
   His Sprint 2 answers: recent names on the phone while signed out; Noir look; keep the friends' name clips;
   tools in `C:\Users\WGN\sdk\`; G7 unchanged.
   **Sprint 3, accounts and friends** (`docs/sprint-3-prd.md`, built 2026-11-22, not committed): the upload key in
   `C:/Users/WGN/.android-keys/` and the GitHub secrets (SHA-1 CA:44:FD:43:46:80:A8:17:63:58:38:83:30:C8:1E:6F:0A:8C:FA:AB);
   app sign-in (Google via Credential Manager, email code), handle, profile + photo, devices, delete account, friends,
   bell, hub socket, saved names / setup in D1 (`0004`), Hub auto-pong, a local test mode for the emulator. His answers:
   Google first (email once the domain exists), I generate the key, photos in, local names merged on first sign-in.
   Google Cloud (project `mafia-dealer-game`, consent screen in Testing): Web client
   `347831426258-e0guv95d25aq2adumf8cbvl8grf347qc.apps.googleusercontent.com` (server `GOOGLE_CLIENT_IDS` and the CI
   variable `GOOGLE_SERVER_CLIENT_ID`); Android client `347831426258-b2vm9tov5d7pue2cohlq2jsikth5enah.apps.googleusercontent.com`
   (package + upload-key SHA-1; not used in any setting: tokens are issued for the Web client).
   Sprint 3 committed and green on CI 2026-11-22 (38fc1be, 09669f0), live with the Google Web client.
   **Sprint 4, online rooms** (`docs/sprint-4-prd.md`, built 2026-11-22, not committed): `user.room` in `/v1/me`;
   app: create / join by code, lobby (shared role and rules editors), the game on every phone with host controls,
   per-phone narration + suspense with a "This phone narrates" switch, the connection bar, reconnect with `?rev=`,
   taps resent after a drop, invites / join requests / let in, online history. His answers: every phone narrates (with
   the switch), chat moves to Sprint 5, anyone with the code may join, new order 5 chat + polish / 6 Wi-Fi + approval /
   7 push + Play readiness. Also at his request: the launcher icon is now the old app's "Fedora over the town", and CI
   names the APK `MafiaDealer-PartyGame-<version>-b<run>-debug.apk`.
   Sprint 4 committed and green on CI 2026-11-22 (0a57ff2, ecd66cb).
   **Sprint 5, chat + safety + walkthrough fixes** (`docs/sprint-5-prd.md`, built 2026-11-22, not committed): run as
   the three personas again after he restated the rule. Room chat in the app; block / report / admin moderation / bans
   (migration `0005`, `ADMIN_IDS` secret; not set yet: he sends his account ID from Profile); the server clock in
   `room`; the player walkthrough's fixes W1–W9 (day roster, how the town decides, online vote labels, neutral avatar
   presets, lobby summary + offline warning, LTR @handles in Arabic, host controls off during a drop, How to play,
   offline night number). His answers: admin = his account only; keep reports about deleted accounts; no word
   filter; neutral avatars; guide in this sprint.
   Sprint 5 committed and green on CI 2026-11-22 (eb6fd15, migration 0005 live). Admin queue waits for his Account ID.
   **Sprint 6, Wi-Fi / Hotspot play** (`docs/sprint-6-prd.md`, built 2026-11-23, not committed): `app/lib/lan/` (the
   Room ported to Dart, the host server on port 8765 + discovery `/mafia`, subnet scan, identity tokens), Kotlin
   `KeepService` (connectedDevice FGS + wake lock + Wi-Fi lock, channel `mafia/keep`), "Resume hosting" from a
   snapshot, players relocating a moved host, Wi-Fi history on the phone (History tabs), host narrates by default.
   His answers: approval process in Sprint 7; own keep-alive plugin; no host takeover yet; 🖕 replaced by 🤨.
   Sprint 6 committed and green on CI 2026-11-23 (b94d330).
   **Sprint 7, push + Wi-Fi approval + the tie rule** (`docs/sprint-7-prd.md`, built 2026-11-23, not committed): FCM
   push (tokens per session, only when the hub is closed, channels invites / friends / approvals, secrets
   `GOOGLE_SERVICES_JSON` + `FCM_SERVICE_ACCOUNT`; push off without them), Wi-Fi games into online history by automatic
   rules (migration `0006`: `settings.wifi_rules`, `wifi_requests` raw + versioned, `wifi_seats`, `games.source`; hourly
   cron expires), Confirm / Not me in the bell, History open signed out, `rules.tieSkip` (old records replay random).
   His answers: recommended 1–5. After it: groups (his prompt), old players (plan), Play readiness last.
   **Sprint 8, stats + old history + in-app updates** (`docs/sprint-8-prd.md`, built 2026-11-23, not committed): the old
   app's titles / board / profile on the server (`stats.ts`: Mine = my online + approved Wi-Fi + old games, 3-game min;
   Everyone = accounts, server-vouched games, 10-game min, opt-out switch), best partner, share card, title-taken notes
   (Titles channel), old history import by the old Group-history code (`legacy.ts`, migration `0007`, real-player list in
   `settings.old_players`, empty until he sends names), History → Old app, in-app updates from GitHub Releases
   (`update.dart`, `Updates.kt` PackageInstaller, silent on Android 12+ after the first, `release.yml` run only when he
   asks, push topics `updates_en/ar`), old-build tag in lobbies. His answers: Everyone board added; names later; updates
   automatic like the old app + push; P1-P4 all; local emulator for QA (Pixel 6 API 34 AVD `qa34`).
   Next: Sprint 9 (friends drawer, minimize in room, Neon, Settings parity), Sprint 10 (the intro), groups, Play last.
   Next sprints (proposed): 3 sign-in and friends; 4 online rooms in the
   app; 5 Wi-Fi play + approval; 6 push, Play updates, app links, Play readiness. Groups wait for his prompt.
5. Play readiness. 6. Migration of old users (optional).
