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
- **2026-11-26 · Sprint 19 (1.2.0) scope: the suggestions box.** His sign-off on `docs/sprint-19-prd.md`: signed-in
  only; 3 a day, 5 waiting, one screenshot ≤ 300 KB, 1000 characters, 300 in the box; admin only; Empty deletes for
  good. Proposals left to the team: P1 (Mark done → a bell note), P2 (report a problem with this game, an online game's
  id attached) and P3 (My messages) all taken.
- **2026-11-26 · S19 P1 is a push, not a bell note.** [Ben · BA] / [David · Dev]: 1.1.x phones show an unknown bell note
  as "wants to join your room" and the API doesn't know the caller's version, so "Mark done" sends a push (old phones
  just open the app) and My messages shows Done.
- **2026-11-26 · S19 box cap.** The box holds 300 items of any status until the admin empties it; "Empty" deletes only
  what he saw (Quin Q12). A small overshoot under parallel sends is accepted.
- **2026-11-26 · 1.2.1 hotfix: a tie keeps the title.** `docs/hotfix-1.2.1-report.md`. His note: Sami "took" Best Doctor
  on a 13-13 tie after the Sami → @sami link. A title moves only when someone has strictly more; migration 0013 gives it
  back. Accepted (Quin Q2): undoing something can move a tied title for good.
- **2026-11-26 · Old players recounts the titles at once, quietly.** [David · Dev] (Quin Q3): it's the admin's
  bookkeeping, so it sends no "took it from you" notes. Titles taken in games still send them.
- **2026-11-26 · One profile everywhere.** A player's page always shows every game, all time (from Stats it followed the
  board's filter without saying so).
- **2026-11-26 · No Old tab (his note).** Every old player is linked: Stats → Online includes the old app's games
  (`source=old` still answers 1.2.0 phones), and History lists my old games in Online, marked "Old app".

### Sprint 20 (1.3.0): new roles
- **2026-11-26 · Sprint 20 PRD signed off "as suggested"** (Q1–Q9 in `docs/sprint-20-prd.md`):
  - Wave 1 only: Hunter, Mayor, Framer, Watcher, with the modes Avenger (6+) and Shadows (8+).
  - The Framer is a Mafia with a power, like the Sheikh.
  - The Hunter may hold fire.
  - A revealed Mayor can't be protected by the Doctor.
  - Every Mafia who voted for the target counts as visiting it (Q5, reopened by Ben in `sprint-20-roles.md`, E-W1).
  - No repeat limit for the Watcher.
  - New roles join All from 1.4.0.
  - The Transporter, the Witch and the Baker are dropped.
  - Brad's Arabic names.
- **2026-11-26 · Each role and mode is discussed with him in detail before any role is built (his note).** Ben checks the
  edge cases (`docs/sprint-20-roles.md`).
- **2026-11-26 · R1–R6 "as suggested"** (`docs/sprint-20-roles.md`):
  - with the reveal rule off, the Hunter's aim still shows his role;
  - the Bodyguard may guard a revealed Mayor;
  - in pass-and-play the Mayor reveals from his night turn, and "the table decides" has no double vote;
  - only the Framer learns whether his frame hit;
  - one Mafia (the Sheikh, else the lowest seat) visits the victim;
  - Shadows keeps both Mafia powers at 8.
- **2026-11-26 · Never the Sniper and the Hunter in the same game (his rule).** The engine refuses the deck.
  - Avenger: the Hunter, the Mayor from 7, and no Sniper.
  - Shadows: the Sniper from 8, the Mayor from 11, and no Hunter.
  - Why: groups of 7–8 never got the Mayor or the Sniper.
- **2026-11-26 · The Hunter is الصياد in Arabic (his choice).**
- **2026-11-26 · The 25% / 65% / 10% ratio is a guide, not a rule (his note).** Brad may suggest other mixes when they
  play better (his example: 9 players with 3 Mafia and a combo of other roles). Each is still a proposal for his sign-off.
- **2026-11-26 · §8 signed off** (`docs/sprint-20-roles.md`):
  - Classic and the old modes stay as they are.
  - Avenger and Shadows offer a choice of two Mafia counts where §8 B says so (Shadows at 9: 3 by default, no Jester; 2 brings the Jester in).
  - The rules count as a "lean": two or more points to one side removes the count that makes it worse.
  - The Hunter's shot uses the night timer.
  - One test plays every mode × size × Mafia count × the 64 combinations of the rules that count.
  - The win rates per mode are rechecked every release.
- **2026-11-26 · After Quin's review (Q1-Q5)** [David · Dev]:
  - A Hunter who leaves the room while aiming holds fire.
  - The host may go on without the Hunter's shot (asked first if he is still in the room).
  - On one phone his shot has no clock.
  - The Framer's news and the Watcher's list are shown only on their own next night screen, never on the table's morning or day. The Detective's result stays in his day list, as in every mode.
  - The Framer must choose a frame or "No frame" before he confirms.
- **2026-11-26 · "Reveal roles" is off by default (his ruling, Quin Q9).**
  - New setups and the Classic preset start with it off, the way the group plays (59 of 60 games). Beginner keeps it on.
  - Saved setups keep their own rules.
  - With it off, the new modes offer their Mafia choice by default. Choosing a mode starts at its default count.

### Sprint 21 (1.4.0): wave 2
- **2026-11-26 · Sprint 21 PRD signed off "as suggested"** (R1–R12 in `docs/sprint-21-prd.md`):
  - Scope: the Serial Killer, Cupid and the Lovers, and the Silencer; the Lovers (8+) and Lone Wolves (9+) modes; Mafia ranges for Sniper, Jester and Bodyguard. All gets every role in Sprint 22.
  - The Serial Killer has no immunity; the Doctor and the Bodyguard stop him; the Detective reads him "not Mafia".
  - While he lives nobody else wins. He wins alone, or as one of the last two with a non-Mafia. He and one Mafia left is a draw.
  - The lovers learn their partner's name and side.
  - Cupid may pick himself.
  - "Died of a broken heart" is announced.
  - A removed lover's partner lives.
  - The Silencer is announced each morning; never the same player two nights running, not himself, teammates allowed.
  - One Serial Killer at 17–20.
  - Arabic: القاتل المتسلسل، كيوبيد، العاشقان، المُسكِت.
  - Phones before 1.4.0 see the new endings as "Citizens win".
- **2026-11-27 · Sprint 22 tests the engine by roles and small tables, not by every setup.** His ruling, for Ben's
  Sprint 22 PRD. The every-combination run takes over an hour and won't scale to more modes, roles and players.
  - Check every deal (cheap); play only a sample of setups (pairwise / 3-wise).
  - Deal arbitrary role mixes directly, not only through the modes (All mode needs this).
  - At 5–7 players, try every possible game.
  - Property-based tests that shrink a failure to the smallest game, on a time budget in CI and nightly.
