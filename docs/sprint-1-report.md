# Sprint 1 Release Report: a game you can trust

2026-11-22. Built against `docs/sprint-1-prd.md` (signed off the same day). **Not committed, not deployed.** On the next
push to `main`, CI applies migration `0003` to the live D1 and deploys the Worker.

## Result: green
- Engine: **34/34** (`node --test`; was 32: the record tests are new, and the 1,000 random games now also replay).
- Server: **38/38** (vitest in the Workers runtime, real Durable Objects, D1 and sockets; was 30), run 3 times with no flakes.
- `npm run check` (strict types, all workspaces): clean. `wrangler deploy --dry-run`: builds (942 KiB, 165 KiB gzip).
- **Checking the tests catch the bug:** with the S1-1 fix switched off, both join-race tests fail (a member is lost).
  With it on, they pass.

## Against the acceptance criteria

| AC | Status | Evidence / how |
| --- | --- | --- |
| S1-1 AC1 simultaneous joins | ✅ | 10 sockets join at once, 20 rounds: always 10 members with distinct chat numbers. Every entry point of the room (join, message, close, alarm) now runs one at a time. |
| S1-1 AC2 one saved game | ✅ | A game-ending vote sent twice by everyone, with chat and `mark` at the same moment: exactly 1 row in `games`. ⚠ This test also passes with the fix off: it guards the case but didn't reproduce a double save. |
| S1-1 AC3 nothing lost | ✅ (narrowed) | 5 joins + 25 chats + 5 setup changes at once: 10 members, all 25 messages stored. It checks "nothing lost" rather than "equals the sequential result", because parallel sends have no defined order. |
| S1-1 AC4 old tests | ✅ | 30 old tests pass. One was changed: the night-timer test now moves the timer into the past, because the alarm no longer skips turns before the timer really ends (the alarm now also runs for the liveness check). |
| S1-2 AC1 silent phone offline | ✅ | Sockets are stamped on every message and by Cloudflare's automatic pong; an alarm runs at the earliest moment a socket could reach 30 s of silence. A test makes a socket look 30 s silent and runs the alarm: closed (4001), shown offline. The 40 s worst case comes from the alarm timing; the test doesn't wait real seconds. |
| S1-2 AC2 host controls move | ✅ | Same test: the next player in join order becomes host in the same update. |
| S1-2 AC3 Continue skips it | ✅ | Same test: after the 3 others play, Continue ends the night. |
| S1-2 AC4 comes back < 2 s | ✅ | Reconnects into the same seat, online, host again, measured < 2 s. Live sockets are never closed by the check (own test). |
| S1-3 AC1 growing `rev` | ✅ | Every `room` / `view` / `events` carries `rev`; tests check it never goes back on any socket. |
| S1-3 AC2 catch-up | ✅ | `?rev=N` sends the missed events (last 200 kept); behind that, `missed`, then the current view. |
| S1-3 AC3 once only | ✅ | No event at or before N is resent; the morning phase event arrives exactly once. |
| S1-3 AC4 drop during the night | ✅ | A player drops in the night, the others play and Continue; reconnecting with its rev gets the morning events once. The private night summary is never sent. |
| S1-4 AC1 repeats harmless | ✅ | The same night choice or vote sent twice: no error, counted once. |
| S1-4 AC2 stale | ✅ | An old `day` / vote `id` answers `stale` (pinned by tests). |
| S1-5 AC1 pings don't wake | ✅ | After a ping: `pong` received, Cloudflare's auto-reply time set, the room's handler never ran. |
| S1-5 AC2 liveness uses it | ✅ | The silence check reads the auto-reply time. |
| S1-5 AC3 estimate | ✅ | In `server/README.md`: ~350–400 requests per 10-player, 30-minute game ≈ 250 games a day on the free tier. ⚠ Whether Cloudflare counts its automatic pongs as requests can't be seen locally: check the dashboard once real games run. |
| S1-6 AC1 record | ✅ | `startRecord` / `step`: setup, dealt roles, every action with its time and random draws. |
| S1-6 AC2 replay exact | ✅ (random games) | All 1,000 random games replay to an identical state. ⚠ The hand-written scenario tests build their states directly and aren't recorded; the random games cover all the rules. |
| S1-6 AC3 edits refused | ✅ | Refused: a changed winner or history, a cut or illegal action, time going backwards, an extra Doctor, extra random draws, an unknown format, malformed input. ⚠ A role swap that keeps every action legal and the same history can't be detected: it's indistinguishable from a real deal (in the engine README). |
| S1-6 AC4 shared games | ✅ | `packages/engine/fixtures/records.json` (60 games, 315 KB); a rule change fails the test until regenerated. |
| S1-6 AC5 saved with online games | ✅ | Migration `0003` (+ rollback) adds `games.record`; online games save it; the test replays it from D1. |

## What changed
- `packages/engine`: `src/record.ts` (new), `index.ts` exports, `test/play.ts` (the random-game player, now recording),
  `test/record.test.ts` (new), `fixtures/records.json` (new), README.
- `packages/protocol/src/live.ts`: `rev` on `room` / `view` / `events`, new `missed`.
- `server/src/room.ts`: the one-at-a-time queue, auto-pong, liveness stamps + stale sweep in the alarm, `rev` + kept
  events + catch-up, ignoring repeats, the game record. `server/migrations/0003_records.sql` + rollback.
- `server/test`: 8 new tests, the night-timer test adjusted, `live.ts` counts pongs.
- Docs: server and engine READMEs, `CONTEXT.md` (the decisions of 2026-11-22 and the sprint).

## Caveats for your manual check
1. **Nothing to play by hand yet:** there's no app until Sprint 2, and the live server still has no sign-in (Resend /
   Google). These changes can only be checked by the automated tests for now.
2. **New cost:** while phones are connected, each room wakes every 20–30 s for the liveness check.
3. **The app must:** send `"ping"` every 10 s, remember the last `rev` and reconnect with `?rev=`, handle `missed`, and
   ignore messages with an older `rev`. These are written in the server README and are Sprint 4's job.
4. G7 (the two old-rule oddities) is unchanged, still waiting for your decision.
