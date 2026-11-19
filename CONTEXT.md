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

## Phases
1. **Engine** (done 2026-11-19, not committed): `packages/engine`, 31 tests (setup limits, one per rule, test7/test9
   scenarios, 1,000 random games). Open questions in `packages/engine/QUIRKS.md`.
2. **Server base on Cloudflare** (built 2026-11-19, not deployed yet): Hono + zod Worker, D1 schema
   (`server/migrations/0001_init.sql`), email-code + Google sign-in, sessions, profile, avatars, friends; 17 vitest
   tests in the Workers runtime; `ci.yml` deploys on main once `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` and
   the D1 `database_id` exist; `backup.yml` weekly. The VPS secrets were deleted.
3. Realtime: presence, invites, chat, server-judged online games (Durable Objects + WebSockets).
4. App: Capacitor shell, Kotlin plugin (Wi-Fi server, keep-alive service, Google sign-in), online via the server, Play updates.
   Open: building the Android app (Google's Maven server has been unreachable at times; the old project decided not
   to route around that with cloud runners).
5. Play readiness. 6. Migration of old users (optional). 7. Firebase push wiring if not already in 4.
