# Sprint 18 PRD: 1.1.0, the Bodyguard and two rule fixes

**[Ben · BA]**, 2026-11-25. His request: "the Detective can investigate again, which is wrong"; "the Sniper cannot use
his shot in the first night"; a new role, the Bodyguard; "accomplish the above in one release".

## Audit: where we stand

### Current code
- **Detective:** `nightOptions` (both engines) lets him pick any living player but himself, every night. His result is
  shown only until the next night (`view.check`); nothing remembers it. The night log already keeps every check
  (`log[].checked`), so past results can be worked out from the record without a new field.
- **Sniper:** his bullet is live from night 1 (`key: 'sniper'` while `!shotUsed`).
- **Night order today:** the Mafia's pick → the Doctor's saves → the Sniper's bullet (nothing stops it) → the morning
  names the dead in seat order.
- **Modes:** Classic (4+), Sniper (6+), Jester (6+), All roles (9+). Classic's deck editor has Mafia, Doctor, Detective.
- **D1:** `game_players.role` has a CHECK listing the six roles; a seventh needs a table rebuild (as 0010 did).
- **Old apps:** 1.0.0 phones show "Update the app to play" for a role they don't know (S17-4).

### As a player
- A Detective who checked someone on night 1 has to remember the answer himself; on a passed phone there's nobody to
  ask. Checking the same player twice wastes a night and looks like a bug (his report).
- A Sniper shooting on night 1 fires blind: nobody has said a word yet, so it's a coin toss that can end a 6-player
  game's town early.

### Old app (`../mafia-dealer`)
- The old app had no Detective memory and no Sniper or Bodyguard; nothing to keep.

### Market ([Brad · Market])
Sources were thin, mostly role guides; nothing at all was found on Arabic names, Detective re-checks or table sizes.
- **Bodyguard:** Town of Salem 2 lets him guard himself, but then he doesn't step in, since the role exists to die in
  someone's place. Wolfy's Guard can't protect the same player two nights running. Another Mafia rule set bars
  self-guarding. Guides call Doctor + Bodyguard "almost unbreakable" when the Doctor keeps saving the Bodyguard.
- **No shot on night 1:** a common convention for vigilante/sniper roles (chess.com Mafia role list, forum games). No
  source gives the reason; ours is above (a blind shot).
- **Detective memory:** no source either way, no complaints found. His rule stands on its own.
- **Arabic name:** nothing found; Brad asks that a player confirm it before it's locked.

## Part A: rule fixes (every 1.1.0 game, all modes)

### S18-1 The Detective never checks the same player twice
- **AC1** On the Detective's night screen, every player he already checked this game shows a tag with the result he
  got: "Mafia" (red) or "Not Mafia" (green). The Godfather keeps showing "Not Mafia" (his S17 ruling).
- **AC2** Those players can't be picked again (greyed, like the Detective's own seat).
- **AC3** The same on all three ways to play: offline (passed phone), online and Wi-Fi; English and Arabic.
- **AC4** If every living player other than him has been checked, his turn says so ("Everyone has been checked") and he
  confirms with no pick, like a Citizen without the decoy.
- **AC5** Games recorded before 1.1.0 replay exactly as they were played (a record without the 1.1 flag keeps the old
  rule).

### S18-2 The Sniper can't shoot on night 1
- **AC1** On night 1 the Sniper picks like a Citizen (so his turn looks like everyone else's), with a line under the
  title: "Your bullet is ready from night 2".
- **AC2** From night 2 he has his bullet as today (one per game, nothing stops it except the Bodyguard, S18-3).
- **AC3** The engine refuses a shot on night 1 even if a client sends one (online and Wi-Fi are server/host checked).
- **AC4** Old records replay unchanged (AC5 of S18-1).

## Part B: the Bodyguard (his rules, numbered so he can correct any line)

### S18-3 How the Bodyguard plays
His rules, as written:
- **B1** Each night the Bodyguard guards one player.
- **B2** If the Mafia target the player he guards, the kill goes to the Bodyguard instead.
- **B3** If the Doctor saved the Bodyguard and the Bodyguard guarded the Mafia's target, nobody dies.
- **B4** The Bodyguard doesn't affect the Detective at all (a guarded player is checked as usual).
- **B5** The Bodyguard can take the Sniper's shot aimed at the player he guards, even when that player is Mafia.

What his rules leave open, with the BA's default (he can change any):
- **B6** He can't guard himself. *(Default. In his rules the kill "goes to the Bodyguard", so guarding himself would do
  nothing.)*
- **B7** He can't guard the same player two nights in a row (that player is greyed with "Guarded last night").
  *(Default, changed after Brad's challenge: without it, a Doctor who always saves the Bodyguard while he always guards
  the same player makes both unkillable by the Mafia.)*
- **B8** The Mafia target the guarded player **and the Doctor saves that same player** (not the Bodyguard): the kill
  has already gone to the Bodyguard, so **the Bodyguard dies**. *(Default, following B2 then B3: the Bodyguard steps in
  first, then the Doctor's save is checked on whoever is now being killed. Alternative: nobody dies.)*
- **B9** The Mafia target the Bodyguard himself: a normal kill; the Doctor can save him.
- **B10** The Sniper shoots the guarded player: the Bodyguard dies instead, **even if the Doctor saved the Bodyguard**
  (his S17 rule: the Doctor can't stop a bullet).
- **B11** The Mafia and the Sniper both aim at the guarded player: the Bodyguard dies once; the guarded player lives.
- **B12** The Sniper shoots the Bodyguard himself: he dies.
- **B13** The morning says only who died, as today (seat order, no cause). Nobody is told who the Bodyguard guarded.
  "Reveal saves" (if on) names a player only for a Doctor save that kept someone alive, as today.
- **B14** The Bodyguard is on the town's side and wins with the Citizens.
- **B15** The Mafia see their target survived, like a Doctor save; they aren't told a Bodyguard was involved.

### S18-4 Where the Bodyguard is dealt
- **AC1** A new mode **Bodyguard**: Mafia (about one in four), Doctor, Detective with 2+ Mafia, Bodyguard. 6+ players.
- **AC2** **All roles** adds the Bodyguard (still 9+: at 9 players, 2 Mafia + Doctor + Detective + Sniper + Jester +
  Bodyguard + 2 Citizens).
- **AC3** Classic stays as it is (no Bodyguard row in its deck editor).
- **AC4** The mode picker, the setup summary, the lobby, How to Play and the role card all name and explain him, in
  English and Arabic (Arabic name: his call, Part C).

### S18-5 The Bodyguard on every screen
- **AC1** Role card: name, icon, colour, what he does, "Town · wins with the Citizens".
- **AC2** Night: "Who do you guard tonight?", his own seat greyed.
- **AC3** Morning, verdict, end recap, history, game detail, profile and leaderboard handle the role; the recap marks a
  Bodyguard who died protecting someone ("Took the hit") only at the end, when everything is revealed.
- **AC4** Stats: "times he took the hit" is counted; the Player of the game can be a Bodyguard who saved a life.

## Part C: release and safety

### S18-6 Both engines in step
- TypeScript and Dart give the same result for every rule above; new shared fixtures (scripted games covering B1–B15,
  the Detective memory and night 1 for the Sniper) are replayed by both, and all old fixtures still replay.

### S18-7 Old apps and the database
- **AC1** Every table needs 1.1.0 (as his S17 Q4 ruling): the server and the Wi-Fi host refuse to deal with an older
  phone, which is named "needs 1.1.0".
- **AC2** D1 migration 0011 widens the role CHECK for `bodyguard`, with a rollback; tested on a copy of production first.
- **AC3** A 1.0.x phone that somehow sees a Bodyguard shows "Update the app to play", never crashes (S17-4 already).

### S18-8 1.1.0
- Version 1.1.0; player release notes; no mention of his own code changes.

## Part D: [BA] proposals (for him to accept or drop)
- **P1** The Detective's past results also show on his role card ("Checked: Sami · Not Mafia") so he can look during
  the day without waiting for night. *(Day-time peeking on a passed phone is a risk offline; online it's his own phone.)*
- **P2** At the end, the recap says who the Bodyguard guarded each night, in the game's history ("Night 2: guarded
  Sami"), like the Doctor's saves today.
- **P3** The Bodyguard mode is suggested (the "suggested" badge) at 7–8 players, where the town needs help most.

### Challenge log (PRD)
- **Brad → Ben, B6/B7:** Brad's sources mostly allow guarding yourself and block guarding the same player twice
  running; Ben's draft did the opposite on both. Ben kept B6 (in his rules the Bodyguard *takes* the kill, so guarding
  himself does nothing) and took B7 from Brad: the Doctor + Bodyguard lock is real in our rules. Settled in one round.
- **Brad → Ben, Arabic name:** no evidence for any name; it stays his call (Part E 1), not a BA default.
- **Ben → his rules, B8:** his B2 and B3 together say the Bodyguard steps in *before* the Doctor's save is looked at,
  so a save on the guarded player is wasted. That's the default, but it's the least obvious line, so it's question 2.

## His answers (2026-11-25)
1. الحارس الشخصي. 2. The Bodyguard dies. 3. The Bodyguard dies. 4. Yes. 5. Yes. 6. Yes. 7. P1 yes, P2 yes, P3 no:
"make it applicable in the Sniper and Jester (optional)", built as an "Add a Bodyguard" switch in those two modes.

## Part E: what he decides
1. **Arabic name** of the Bodyguard.
2. **B8:** Doctor saves the guarded player while the Bodyguard guards him: Bodyguard dies (default) or nobody dies?
3. **B10:** a Sniper's shot on a guarded player when the Doctor saved the Bodyguard: Bodyguard dies (default) or lives?
4. **B6 / B7:** no self-guard (default)? Not the same player two nights in a row (default)?
5. **S18-4:** a new Bodyguard mode plus All roles (default)? Or only All roles?
6. **S18-7:** require 1.1.0 at every table (default, like Q4)?
7. Proposals P1–P3.

## Out of scope
- Bodyguard voice clips (he has the "killed" lines, like the Sniper).
- Any change to Classic's deck editor.
