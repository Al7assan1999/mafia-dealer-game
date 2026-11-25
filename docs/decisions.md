# Decisions log

Alhassan's sign-offs, deadlock rulings and `/team-meeting` outcomes, newest last. One entry each: date, topic,
outcome (agreed / his ruling / waiting), one line of why. Decisions before 2026-11-25 are in `CONTEXT.md`.

- **2026-11-25 · Team setup.** His ruling: the team grows from three personas to five (Ben BA, Brad market,
  David dev, Quin QA, Danial release), run by `/sprint` and `/team-meeting`. Why: an independent QA review in a fresh
  context, outside research for the BA proposals, and a written release gate.
- **2026-11-25 · Godfather's Arabic name.** His ruling: **شيخ المافيا**. Why: العرّاب means the narrator in the main
  Arabic app (Brad), and he chose the name.
- **2026-11-25 · Godfather's tie-break.** His ruling: the Godfather's vote breaks a tie in the Mafia's night vote.
  Why: he liked it; it gives the Godfather something to do every night, beyond hiding from the Detective.
- **2026-11-25 · Sniper's shot.** His ruling: the target dies and nothing stops it; the Doctor can't save it. Why: the
  rule Arabic players know from the main Arabic Mafia app (Brad).
- **2026-11-25 · The Mafia's tie (replaces the Godfather tie-break above and Sprint 7's "any tie implies skip").**
  His ruling: every game has a شيخ المافيا (with one Mafia, he is it); the most votes win, and on any tie the
  Sheikh's pick wins, even one nobody else chose. A tie never kills nobody. Why: the Mafia always need a way to
  settle a split vote.
- **2026-11-25 · Sniper in 1.0.0; Jester = الجوكر.** His ruling. Why: Arabic players expect the Sniper (Brad).
- **2026-11-25 · The Sheikh and the Detective.** His ruling: the Detective always reads the Sheikh as "not Mafia", in
  every game. Why: his call (Ben had recommended dropping it).
- **2026-11-25 · No Sheikh successor.** His ruling: the role isn't passed on when he dies or is voted out; a tie
  without a Sheikh's pick needs a rule with no randomness. **Waiting:** Brad researches the rule.
- **2026-11-25 · All-roles mode name.** His approval: "All roles / كل الأدوار".
- **2026-11-25 · Mafia tie with no Sheikh's pick.** His ruling: lowest seat decides (among the Mafia who voted for one
  of the tied picks). Why: no randomness, no extra step, the same rule offline and online (Ben and Brad).
- **2026-11-25 · Sprint 17 PRD signed off.** His sign-off ("Signed off, build it"), with the BA answers to Part C 1–5
  and the [BA] proposals (P1 suggested badge, P2 side and win on the role card, P3 stats, never paid).
- **2026-11-25 · Old phones at a 1.0.0 table (Quin Q4).** His ruling: require 1.0.0 at every table, Classic included;
  an older app is named "needs 1.0.0" and the deal waits (online and Wi-Fi). Why: a 0.4 phone doesn't know the
  Godfather or the new tie rule. Local, test and CI builds (below 100000) report themselves as 1.0.0.
- **2026-11-25 · Test migration 0010 on a copy of production.** His OK. Done: live had no online/Wi-Fi games yet; 0010
  and its rollback ran cleanly on the copy, everything else untouched; the export was deleted.
- **2026-11-25 · The Godfather on reveal.** His ruling (BA proposal accepted): with "Roles revealed" on, a dead or
  voted-out Godfather is named "Godfather", not "Mafia". Why: the table then knows ties now go to the lowest seat.
- **2026-11-25 · 1.0.1 hotfix (his playtest: four room bugs, "fix and cpr asap").** [David · Dev] defaults:
  an out player (host included) sees "You are out" only during the night and the vote; the morning, the day and the
  verdict show the table's screen, so an out host runs the timer and sees the night's result. The host's Start now
  is no longer on the role card (it read as "next" and skipped everyone's card); it shows after "I'm ready" and asks
  first. Valid / Invalid: the server marked games correctly in every test, so the fix makes the choice visible (a
  tick, and a note of what it means) and answers before the titles are recalculated; in Wi-Fi rooms, an Invalid game
  isn't offered to online history (before, the buttons had no effect there).
