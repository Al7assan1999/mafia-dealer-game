# @mafia/server

The Cloudflare Worker: REST API under `/v1` on a D1 (SQLite) database, and two kinds of Durable Objects:
- **`Room`** (one per online room code): the lobby and the game, run by the shared engine. The server is the judge,
  each phone gets only `viewFor(its seat)`, the night timer is an alarm, the chat lives in the room's storage, and
  everything is deleted when the room ends (closed, everyone left, or 12 hours empty).
- **`Hub`** (one per account): the open app's socket. Online status, friends' presence and bell notes are pushed
  through it.

## Sockets
`new WebSocket(url, ['mafia.v1', <session token>])`: browsers can't send headers on a socket, so the token rides as
the second subprotocol, never in the URL. Messages are JSON; their schemas are in `packages/protocol/src/live.ts`.

**Keep-alive:** send `"ping"` every 10 s. Cloudflare answers `"pong"` itself, without waking the room. A socket that
sends nothing for 30 s is closed by the room (code 4001 `stale`): it's shown offline within about 40 s, the host's
controls move on, and "Continue" can skip that player. A phone that's still there simply reconnects.

**Reconnecting:** `room`, `view` and `events` carry `rev`, which only grows within a room (ignore anything older than
what you have). Reconnect with `/v1/rooms/:code/ws?rev=<the last rev seen>` to get the `events` missed meanwhile, in
order and once each (the room keeps the last 200). Further behind than that, you get `missed`: just show the current
view. Repeating a night choice, vote or `ready` that was already applied is ignored silently; an outdated one (`day`,
vote `id`) answers `stale`.

**Free-tier budget** (Durable Object requests, 100,000 a day): a 10-player, 30-minute game makes about 10 joins,
~250 messages (night choices, votes, host actions, chat) and ~60–90 liveness alarms (one every 20–30 s while
phones are connected): **about 350–400 requests, so roughly 250 games a day.** Keep-alives don't wake the room; whether
Cloudflare counts its own automatic replies as requests isn't something the local tests can show (check the dashboard
once real games run).

**`/v1/rooms/:code/ws`** (create the room first with `POST /v1/rooms`). In: `RoomIn` (host: `setup`, `deal` (also
Play again), `start`, `startDay`, `timer`, `startVote`, `nextNight`, `continue` (skip offline players' turns), `kick`,
`unmute`, `ping`, `mark`, `lobby`, `close`; everyone: `ready`, `night`, `vote`, `buzz`, `leave`, `chat`, `react`,
`edit`). Out: `room` (members, host, rules; after every change), `view` (my seat's view), `events` (for narration;
the private night summary only appears in the saved history), `chatAll` on joining, `chat`, `mention`, `buzz`,
`ping`, `err`, `bye`.
- The host's controls belong to the room's host while connected, otherwise to the first connected player in join
  order; `leave` hands them over for good.
- Late joiners are refused once roles are dealt (`started`); a seat holder who drops comes back into the same seat.
  A kick mid-game is an elimination, and kicked players can't come back.
- Chat: Everyone (`to: -1`) and 1:1 by chat handle (`cn`), out players reach only out players, 30 reactions,
  replies, mentions, edits for 15 minutes, 200 characters, 8 per 10 s, the last 50 per conversation.

**`/v1/hub/ws`**: pushes `presence` (a friend online / in a lobby / in a game; "show me as online" respected),
`note` (a new bell note) and `unread` on connecting.

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
| `POST /v1/rooms` | ✓ | a new online room → `{code}` (10 an hour) |
| `GET /v1/rooms/:code` | ✓ | `{open, status, host}` or `no_room` |
| `POST /v1/invites {userId, code}` | ✓ | a friend into my room; answering their join request makes it `let_in`. 30 an hour with join requests |
| `POST /v1/join-requests {userId}` | ✓ | ask a friend who is online in an open lobby (`not_open` otherwise) |
| `GET /v1/notifications`, `POST /v1/notifications/read {ids?}`, `DELETE /v1/notifications[/:id]` | ✓ | the bell (invites 30 min, friend notes 7 days) |
| `GET /v1/games`, `GET /v1/games/:id`, `PATCH /v1/games/:id {valid}` | ✓ | my finished online games; the full history; only the host marks valid |

Friends' cards also carry presence (`on`, `st`, `op`). Sign-in by Google and by email code reach the same account when the verified email is the same. Sessions last 180 days
and renew with use (at most one write a day). Nobody else ever sees an account's email.

## Database
`migrations/NNNN_*.sql` are applied by CI (`wrangler d1 migrations apply DB --remote`) before each deploy; each has a
hand-run rollback in `rollbacks/`. Tables use `STRICT`, foreign keys with `ON DELETE CASCADE`, and CHECK constraints.
Migrations only **add** (columns, tables): nothing that holds data is dropped or renamed, so plans can change later
without losing data. Online games keep their engine record in `games.record` (`0003`; older games have none).

## Deploy (GitHub Actions, `.github/workflows/ci.yml`)
On `main`, after the tests: migrations, `wrangler deploy`, the `RESEND_API_KEY` Worker secret, a health check. It
skips itself until these exist: the `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` repo secrets and the D1
`database_id` in `wrangler.jsonc` (`npx wrangler d1 create mafia-dealer-game`). `backup.yml` exports the live database
weekly, encrypted with `BACKUP_PASSPHRASE`.
