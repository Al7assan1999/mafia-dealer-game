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
- Server: Node 24 + TypeScript, Fastify (REST), Socket.IO (realtime), Postgres (a friend's VPS, own database + owner
  role, 13+) through `pg` + Kysely. Everything in Docker, deployed only by GitHub Actions (the friend gives the IP
  and secrets). Migrations: SQL files with rollbacks, applied by a one-shot `migrate` container on deploy.
- The server judges online games with the shared engine; Wi-Fi and offline play need no server.
- Sign-in: email 6-digit code (Resend) + Google (Credential Manager through our own Kotlin plugin). No username or
  password. Public @handle for friends, emails never shown. Sessions: opaque random tokens, stored hashed, per device.
- Push: Firebase Cloud Messaging in the first Play release (no Telegram).
- Cloudflare free plan: DNS, Tunnel (`cloudflared` container, no open ports on the VPS), proxy (TLS, DDoS, rate
  rules), caching of static pages.
- Backups: nightly `pg_dump`, encrypted, copied to Cloudflare R2 (7 daily + 4 weekly), monthly restore test in Actions.
- Old users: migrate if easy, else a fresh start. Phone history doesn't carry over to a new package without an export.

## Phases
1. **Engine** (done 2026-11-19, not committed): `packages/engine`, 31 tests (setup limits, one per rule, test7/test9
   scenarios, 1,000 random games). Open questions in `packages/engine/QUIRKS.md`.
2. Server base: schema, accounts, sessions, friends / invites over REST, Docker, Tunnel, Actions deploy, backups.
3. Realtime: presence, invites, chat, server-judged online games (Socket.IO).
4. App: Capacitor shell, Kotlin plugin (Wi-Fi server, keep-alive service, Google sign-in), online via the server, Play updates.
   Open: building the Android app (Google's Maven server has been unreachable at times; the old project decided not
   to route around that with cloud runners).
5. Play readiness. 6. Migration of old users (optional). 7. Firebase push wiring if not already in 4.
