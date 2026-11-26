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
- **2026-11-25 · Sprint 18 (1.1.0) scope.** His request: the Detective never checks the same player twice and sees his
  earlier results for the rest of the game; the Sniper can't shoot on night 1; a new role, the Bodyguard (his rules
  B1-B5 in `docs/sprint-18-prd.md`); one release.
- **2026-11-25 · Bodyguard's Arabic name.** His ruling: الحارس الشخصي.
- **2026-11-25 · Doctor saves the guarded player (B8).** His ruling: the Bodyguard still dies (he steps in first; the
  Doctor's save is then looked at for the Bodyguard).
- **2026-11-25 · Sniper shoots the guarded player (B10).** His ruling: the Bodyguard dies, even if the Doctor saved him.
- **2026-11-25 · B6/B7.** His OK: no guarding himself; not the same player two nights in a row (Brad's challenge).
- **2026-11-25 · Where the Bodyguard is dealt.** His OK: a Bodyguard mode (6+) and All roles; and (his answer to P3)
  the Sniper and Jester modes get an optional "Add a Bodyguard" switch instead of a suggested-mode badge.
- **2026-11-25 · 1.1.0 at every table.** His OK (as his S17 Q4 ruling): build 100019 (release run 19) or later.
- **2026-11-25 · Proposals.** P1 (the Detective's results shown to him) and P2 (whom the Bodyguard guarded, in the
  history) accepted; P3 replaced by the switch above. P1 lands on his night screen (offline and online) and his own day
  screen (online): the role card isn't shown during a game, and a passed phone's day screen is everyone's.
- **2026-11-25 · B13 vs B15 (Quin Q2).** [Ben · BA] default, for his review: with "Reveal saves" on, the morning names
  the Mafia's own target when the Doctor's save on the Bodyguard kept everyone alive, never the Bodyguard. Why: B15,
  the Mafia mustn't learn a Bodyguard was involved.
- **2026-11-25 · Old app History (Quin Q6).** A 1.0.x phone can't open a History entry with a Bodyguard (it reads
  every role by name; the API doesn't know the caller's version). Release notes ask players to update every phone.
- **2026-11-25 · Test migration 0011 on a copy of production.** His OK ("Yes"). Done: applied cleanly with every row
  kept; the rollback removed only the test game with a Bodyguard seat; the export and the copy were deleted.
- **2026-11-26 · 1.1.1 hotfix (his list of 11).** `docs/hotfix-1.1.1-report.md`. Item 5 (Sami's blocks): his ruling, not a
  bug (Sami reported to test; "Also block" stays ticked by default). Items 7, 11: data only (one Sami account; his old
  games wait for the Old players link Sami → @sami).
- **2026-11-26 · Out players see every vote (item 3).** As he asked: open or secret, live, for out seats (the host
  too), not only with Ghost view (Quin Q8). The living still see a secret vote's count only.
- **2026-11-26 · Side tabs float again (his note).** Reverses S16-1: the lobby cards use the full width and the tabs
  float over the content and drag up and down (the chat tab too, in a game); a tab over a menu is dragged away.
- **2026-11-26 · A taken username is an alert (his note).** On first sign-in and on the profile.
