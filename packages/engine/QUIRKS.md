# Quirks and differences from the old app

The rules were ported 1:1. This lists what is odd in the old rules (kept as is, waiting for a decision) and what
behaves differently by design.

## Odd, kept as is (decide later)
1. **Removing a player never checks for a win.** If the host removes the last Mafia, or removes someone so the Mafia
   reach parity, the game goes on until the next night or verdict decides it. On the way a player can be left with
   nothing to pick: for example the Doctor, with self-protection off and "no repeat" on, when only one other player is
   alive. That night then waits for "Continue anyway" or the night timer. Found by the random-game test (seed 230).
   *Suggested fix:* check for a win after a removal.
2. **A dead Detective still sees their last result** until the next night (the old `mpPriv` built it before the
   "dead" screen).
3. **A tied Mafia vote between a target and "skip"** is broken at random like any tie, so the one-time skip can be
   spent by chance.

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
