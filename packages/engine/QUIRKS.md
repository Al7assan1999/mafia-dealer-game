# Quirks and differences from the old app

The rules were ported 1:1. This lists what is odd in the old rules (kept as is, waiting for a decision) and what
behaves differently by design.

## Fixed (decided by Alhassan)
1. **Removing a player now checks for a win** (2026-11-19). The old app didn't: removing the last Mafia, or removing
   someone so the Mafia reached parity, let the game go on until the next night or verdict. On the way a player could
   be left with nothing to pick (the Doctor, with self-protection off and "no repeat" on, when only one other player
   was alive), so the night waited for "Continue anyway" or the night timer. Found by the random-game test (seed 230).
   Now the game ends at once; the `win` event's `lead` is `null`.
2. **Any tie means no kill** (2026-11-23, "any tie imply skip"). A tied Mafia vote (two players, or a player and
   "skip") kills nobody; the morning says nobody died and the log says `{ k: 'none' }`. A tie doesn't spend the one-time
   skip. The day vote already treated a tie as nobody out. Stored as `rules.tieSkip` when roles are dealt; records made
   before it have no `tieSkip` and replay with the old random tie-break (`recordRules`, fixtures
   `records-before-tie.json`).

## Odd, kept as is (decided 2026-11-23: keep)
1. **A dead Detective still sees their last result** until the next night (the old `mpPriv` built it before the
   "dead" screen).

## Different by design
1. **Removing the last player still pending finishes the night or vote.** In the old app it got stuck: that player
   was dead, so "Continue anyway" (offline players only) didn't show.
2. **Rules are frozen when the roles are dealt.** The old app read the live settings, so changing a rule mid-game
   took effect at once.
3. **Results are in the views straight away.** The old host held the morning / verdict result back from phones until
   the narrator said the name; with the server judging, each phone holds back its own reveal (phase 3/4 decides how).
4. **Inputs are checked at the boundary.** 4–20 players and names of 1–18 characters (the old setup screen's limits),
   discussion timer "+" between 1 s and 1 hour, night / vote choices checked like the old host checked players'
   messages, and the same checks for the host's own actions.
5. **The game history is data, not sentences** (`state.log`), so it shows in the current language and the server can
   query it. The Detective's finds are `[detective, mafia]` pairs, not `"p:q"` strings.
6. A doctor choice of `null` used to count as protecting seat 0 (`Number(null)`); unreachable before, refused now.
