# @mafia/server

The Cloudflare Worker: REST API under `/v1` on a D1 (SQLite) database. Live rooms (Durable Objects) come in phase 3.

```bash
npm run check   # types
npm test        # vitest inside the Workers runtime, with a real local D1 (the real migrations applied)
npm run dev     # local Worker + local D1 (apply migrations first: npx wrangler d1 migrations apply DB --local)
```

## API
Bearer token in `Authorization: Bearer <token>`. Errors are `{ "error": "<code>" }` (codes in `@mafia/protocol`).
Request bodies are checked with the zod schemas in `packages/protocol`.

| Method & path | Auth | What |
| --- | --- | --- |
| `POST /v1/auth/email/start {email}` | | Sends a 6-digit code (Resend). Same answer whether or not the email has an account. 1 a minute and 5 an hour per email, 20 an hour per IP → `slow_down` |
| `POST /v1/auth/email/verify {email, code, device}` | | → `{token, user, needsHandle}`. 10 minutes, 5 tries → `code` |
| `POST /v1/auth/google {idToken, device}` | | Google sign-in token checked against Google's keys, issuer, audience (`GOOGLE_CLIENT_IDS`), expiry, verified email |
| `POST /v1/auth/logout` | ✓ | ends this session |
| `GET /v1/sessions`, `DELETE /v1/sessions/:id` | ✓ | devices signed in; sign one out |
| `GET /v1/me`, `PATCH /v1/me {handle?, display?, fav?, showOnline?}` | ✓ | `handle_taken` on a clash (ignoring case) |
| `PUT /v1/me/avatar {preset} or {image: data URL}` | ✓ | photo ≤ 150 KB, JPEG / PNG / WebP |
| `DELETE /v1/me {confirm: "delete"}` | ✓ | deletes the account and everything it owns |
| `GET /v1/avatars/:userId` | | the photo (public, cached a day; the URL carries the version) |
| `GET /v1/users/:handle` | ✓ | a public card with the relationship |
| `GET /v1/friends` | ✓ | `{friends, incoming, outgoing}` |
| `POST /v1/friend-requests {handle}` | ✓ (needs a handle) | if they already asked me (or ask at the same moment), it becomes `friends` |
| `POST /v1/friend-requests/:userId/accept`, `DELETE /v1/friend-requests/:userId` | ✓ | accept; decline or take back |
| `DELETE /v1/friends/:userId` | ✓ | unfriend |

Sign-in by Google and by email code reach the same account when the verified email is the same. Sessions last 180 days
and renew with use (at most one write a day). Nobody else ever sees an account's email.

## Database
`migrations/NNNN_*.sql` are applied by CI (`wrangler d1 migrations apply DB --remote`) before each deploy; each has a
hand-run rollback in `rollbacks/`. Tables use `STRICT`, foreign keys with `ON DELETE CASCADE`, and CHECK constraints.

## Deploy (GitHub Actions, `.github/workflows/ci.yml`)
On `main`, after the tests: migrations, `wrangler deploy`, the `RESEND_API_KEY` Worker secret, a health check. It
skips itself until these exist: the `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` repo secrets and the D1
`database_id` in `wrangler.jsonc` (`npx wrangler d1 create mafia-dealer-game`). `backup.yml` exports the live database
weekly, encrypted with `BACKUP_PASSPHRASE`.
