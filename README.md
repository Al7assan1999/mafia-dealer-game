# Mafia Dealer: Party Game

The Google Play version of Mafia Dealer: a Capacitor app, a TypeScript server judging online games, and one
shared rules engine. Package id `com.mafiadealer.game`, domain `mafiadealer.app`. The old sideloaded app
(`com.mafiadealer.app`, repo `../mafia-dealer`) and its Cloudflare Worker relay stay as they are.

## Layout
| Path | What |
| --- | --- |
| `packages/engine/` | Every game rule, pure TypeScript (done, phase 1). See its [README](packages/engine/README.md). |
| `packages/protocol/` | API and socket messages + zod schemas (phase 2) |
| `server/` | Fastify (REST) + Socket.IO + Kysely on Postgres (phase 2-3) |
| `app/` | The web app + Capacitor (`android/`), Kotlin plugin for Wi-Fi hosting (phase 4) |
| `db/migrations/` | SQL migrations, each with a rollback (phase 2) |
| `deploy/` | docker compose: API, migrate, backup, cloudflared (phase 2) |

## Develop
Node 24.
```bash
npm install
npm run check   # strict type check, every package
npm test        # every package's tests
```

## Deployment secrets (phase 2)
Never in the repo: they go into GitHub → Settings → Secrets and variables → Actions, and from there onto the VPS.
Planned names: `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, `DATABASE_URL`, `RESEND_API_KEY`, `FIREBASE_SERVICE_ACCOUNT`,
`CLOUDFLARE_TUNNEL_TOKEN`, `BACKUP_R2_ACCESS_KEY`, `BACKUP_R2_SECRET`, `BACKUP_R2_BUCKET`, `BACKUP_PASSPHRASE`.
