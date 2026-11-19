# Mafia Dealer: Party Game

The Google Play version of Mafia Dealer: a Capacitor app, a Cloudflare backend that judges online games, and one
shared rules engine. Package id `com.mafiadealer.game`, domain `mafiadealer.app`. The old sideloaded app
(`com.mafiadealer.app`, repo `../mafia-dealer`) and its relay stay as they are.

## Layout
| Path | What |
| --- | --- |
| `packages/engine/` | Every game rule, pure TypeScript (done, phase 1). See its [README](packages/engine/README.md). |
| `packages/protocol/` | API types + zod schemas, shared by the server and the app |
| `server/` | Cloudflare Worker: REST API on D1 (phase 2, see its [README](server/README.md)); Durable Objects for live rooms (phase 3) |
| `server/migrations/`, `server/rollbacks/` | D1 (SQLite) migrations, each with a hand-run rollback |
| `.github/workflows/` | `ci.yml` (checks, tests, deploy on main), `backup.yml` (weekly encrypted export) |
| `app/` | The web app + Capacitor (`android/`), Kotlin plugin for Wi-Fi hosting (phase 4) |

## Develop
Node 24.
```bash
npm install
npm run check   # strict type check, every package
npm test        # every package's tests
```

## Deployment secrets
Never in the repo: they go into GitHub → Settings → Secrets and variables → Actions.
`CLOUDFLARE_API_TOKEN` (Workers Scripts Edit, D1 Edit, Account Settings Read), `CLOUDFLARE_ACCOUNT_ID`,
`RESEND_API_KEY`, `BACKUP_PASSPHRASE`; later `FIREBASE_SERVICE_ACCOUNT`. The deploy and backup jobs skip themselves
until theirs exist.
