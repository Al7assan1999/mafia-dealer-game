# @mafia/engine

Every game rule of Mafia Dealer as one pure TypeScript module. The server runs it for online games; the app runs it
for Wi-Fi hosting and pass & play. It touches nothing outside itself: no DOM, no storage, no clock, no `crypto`
(its `tsconfig.json` has no DOM or Node types, so screen code can't creep in).

```bash
npm run check   # strict type check (src, and src + tests)
npm test        # node:test, Node 24 runs the .ts files directly
```

## API
```ts
validateSetup(names, counts)          → { counts, error }      // limits, duplicate names; counts pulled back inside the limits
createGame({ names, counts, rules }, rng, deal?)   → { ok, state } | { ok: false, error }   // phase 'deal'
apply(state, action, { rng, now })    → { ok, state, events } | { ok: false, error }        // never changes `state`
nightOptions(state, seat)             → what that seat may pick tonight
viewFor(state, seat | 'table', now)   → what that seat's phone may show ('table' = public part only)
mvp({ winner, roles, alive, stats })  → { seat, why, n? } | null
```
Helpers: `maxMafia`, `deckOk`, `recMafia`, `normalizeCounts`, `nameKey`, `PRESETS`, `presetOf`, `NIGHT_TIMES`,
`DEFAULT_RULES`, `aliveSeats`, `timerLeft`, `seeded(seed)` (repeatable random source for tests and replays).

The state is plain JSON: save it, send it, snapshot it to Postgres as is. Random numbers come in through `rng`
(real games: a `crypto`-backed one) and time through `now` (ms), so any game can be replayed exactly.

## Phases and actions
`deal` →(begin)→ `night` →(everyone alive acted)→ `morning` →(startDay)→ `day`
→(startVote → `vote` → everyone voted, or decide)→ `verdict` →(nextNight)→ `night` … → `end` (from a night or a verdict).

| Action | When | Notes |
| --- | --- | --- |
| `begin` | deal | |
| `night {seat, choice, day?}` | night | choice: a seat, `'skip'` (Mafia, once) or `null` (nothing to pick). Checked against `nightOptions`. `day` rejects stale messages. The night resolves by itself when the last living player acts. |
| `skipPending {seats?}` | night, vote | No seats: everyone still pending (night timer ran out). With seats: "Continue anyway" for those players. Votes become `'abstain'`. |
| `startDay` | morning | resets the discussion timer |
| `timer {op: start / pause / reset / add, sec}` | day | |
| `startVote {open}` | day | open = live table vote (everyone sees the board) |
| `vote {seat, choice, id?}` | vote | a living other seat or `'none'`; `id` rejects stale votes; tallies by itself when everyone voted |
| `decide {choice}` | day | the table decides together on one phone |
| `nextNight` | verdict | |
| `remove {seat}` | any but deal / end | the host removes a player: an elimination |

Errors: `phase`, `seat`, `dead`, `done`, `choice`, `stale`, `unknown`, plus setup errors `tooFew`, `tooManyPlayers`,
`tooManyRoles`, `mafiaGap`, `badName`, `dupNames`.

## Events → narration and history text
`apply` returns events; the history ones are also kept in `state.log` (the game's history, as data). The app turns
them into narration and text, in the current language. In the old app these were `NARR.*` calls and `t()` strings
inside the rules.

| Event | Narration (old app) | History text (old i18n keys) |
| --- | --- | --- |
| `phase night` | `NARR.night()` | |
| `night {day, mafia, prot, checked}` | | `h_night` + one of `h_kill` / `h_saved` / `h_skip` / `h_nomafia`, then `h_prot` per protection, `h_check` per check |
| `phase morning` | `NARR.morning(dead name, role if rules.reveal, saved name if rules.saverev)`, from `state.morning` | |
| `phase day` | `NARR.day()` | |
| `day {day, out, kind, tally}` | | `h_day` + `h_out` / `h_none` |
| `phase verdict` | `NARR.verdict(name, role if rules.reveal, kind)`, from `state.verdict` | |
| `removed {seat}` | | `kickedH` |
| `win {winner, lead}` | `NARR.mafiaWin(mafia names, lead)` / `NARR.citizensWin(...)`; lead `killed` = monster voice name (`VOX.name(n, 1)`, `v_killed_1`), `votedOut` = `v_vote_out` | |
| (timer reaches 0) | `NARR.timeUp()`: the app sees `timerLeft() === 0` | |

`TallyLine.k` is a seat or `'none'` (old text: `noOne`). `mvp().why`: `mafia` / `mafia2` / `det` / `doc` / `surv`
→ old keys `mvpMafia`, `mvpMafia2`, `mvpDet {n}`, `mvpDoc {n}`, `mvpSurv`.

## Ported from
The old app's `game/roles.ts`, `flow.ts`, `deal.ts`, `night.ts`, `day.ts`, `end.ts` and `mp/hostGame.ts` (including
the host's checks on players' messages, from `mp/host.ts`). The rules are the same; [QUIRKS.md](QUIRKS.md) lists what
behaves differently or oddly.
