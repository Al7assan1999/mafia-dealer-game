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
- Work runs in sprints: BA / PM writes a PRD with acceptance criteria → Alhassan signs off → developer → QA
  (adversarial tests, green build, Sprint Release Report). PRDs in `docs/`.

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
   Next sprints (proposed): 3 sign-in and friends; 4 online rooms in the
   app; 5 Wi-Fi play + approval; 6 push, Play updates, app links, Play readiness. Groups wait for his prompt.
5. Play readiness. 6. Migration of old users (optional).
