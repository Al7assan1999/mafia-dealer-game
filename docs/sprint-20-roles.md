# Sprint 20: the wave-1 roles and modes in detail, with the edge cases ([Ben · BA])

His note (2026-11-26): "keep discussing with me each role description and each mode with details", and "someone
from the team checks the edge cases, so we make sure nothing will break".

**How each role section works:**
- **Description:** what the role card says.
- **Rules:** what the engine does.
- **Edge cases:** each one is settled by a rule or is a question for him (**R#**).
- Every settled edge case becomes a test in S20 (engine TS + Dart, plus a screen test where it shows).

**Edge cases checked against:**
- the 1.1.0+ rules: the Sheikh, the Sniper, the Bodyguard, "never check twice";
- the table rules: reveal, ghost, decoy, saverev, skipVote, tieSkip, night timer, norep / rep / self;
- the three ways to play: online, Wi-Fi, pass-and-play (ballot or "the table decides");
- "Continue anyway", the host's Remove, and older phones.

---

## 1 · Hunter (الصياد, his name), town
**Card:** "You have no night power. When you die, by night or by the vote, you take one player with you."

**Rules**
- He is a Citizen at night (a decoy tap if the decoy rule is on).
- **Dies at night:**
  1. The morning names the dead as today.
  2. Then his phone asks him to shoot one living player, or hold fire.
  3. Everyone else's phone and the host screen show "Hunter is taking aim…".
  4. The shot is announced, and the day starts after it.
- **Voted out:** the same, right after the verdict, before the night.
- Nothing stops the shot: there is no Doctor by day, and no Bodyguard by day.

**Edge cases**
| # | Case | Ruling |
|---|---|---|
| E-H1 | His death gives the Mafia parity (e.g. 2 Mafia vs 3 town, the Mafia kill him → 2 vs 2) | **He shoots first**, then the win check. Shooting a Mafia (2 → 1) saves the game |
| E-H2 | The same night already removed the last Mafia (the Sniper shot him) | Town has won: **no shot** (it can't change anything) |
| E-H3 | He shoots the last Mafia | Town wins at once. The announcement leads with his shot |
| E-H4 | He shoots the Jester | The Jester dies and **does not win** (his win is the day vote only) |
| E-H5 | He is voted out and his shot gives the Mafia parity | The win check after the shot decides: Mafia win |
| E-H6 | He goes offline, leaves the room, or never picks | Online / Wi-Fi: the host's "Go on without his shot" (asked first if he is still here) = holds fire; leaving the room = holds fire at once (Quin Q1, Q4). Pass-and-play: the phone waits for him, with no clock (Quin Q2) |
| E-H7 | The host removes him | No shot (a removal is someone leaving, not a death in the game) |
| E-H8 | **Ghost rule on** (dead players see every role) | He is dead while he aims, so he'd see every role and never miss. **The ghost view starts only after his shot** |
| E-H9 | **Reveal rule off** | "Hunter is taking aim" tells everyone he was the Hunter. It can't be hidden, since a dead player killing someone gives it away. **R1** |
| E-H10 | He dies the same night as two others (the Mafia + the Sniper) | He still shoots. The morning names up to 3 dead (C6's `deaths` list) |
| E-H11 | Stats | The shot is not a "kill" for Most killed first. The MVP gets a new reason: "shot a Mafia" |
| E-H12 | Record replay | His shot is a recorded action (`hunt {seat, choice}`), so old records are unaffected |

---

## 2 · Mayor (العمدة), town
**Card:** "Once a day you may reveal yourself as the Mayor. From then on your vote counts twice, but the Doctor can no
longer protect you."

**Rules**
- He is a Citizen at night.
- **By day** his phone has **Reveal**. Everyone's screen and the host screen then say "X is the Mayor".
- It can't be undone. From the next vote on, his vote counts as two.

**Edge cases**
| # | Case | Ruling |
|---|---|---|
| E-M1 | Can a Mafia "fake" being the Mayor? | No: only the real Mayor's phone has Reveal, so the reveal is proof. The card says so |
| E-M2 | Tally | The secret and open tallies show totals. The open board marks his vote "×2". Ties use the doubled count |
| E-M3 | skipVote off ("no one" doesn't count) | His "no one" is ignored like anyone's |
| E-M4 | Revealed, at night | The Doctor sees him greyed out with "Mayor". **The Bodyguard can still guard him: R2** |
| E-M5 | **Pass-and-play, "the table decides"** (one phone, no ballot) | There's no vote to double. Reveal still works (he is public), but it gives nothing. **R3** |
| E-M6 | **Pass-and-play, ballot** | Reveal is a button on the shared day screen, and anyone could tap it. So in pass-and-play he chooses on his own night turn: "Reveal me in the morning". **R3** |
| E-M7 | He reveals during the vote | Not allowed: Reveal is only before the vote starts |
| E-M8 | Detective checks him | "Not Mafia", as usual |

---

## 3 · Framer (الملفّق), a Mafia with a power (like the Sheikh)
**Card:** "You are Mafia. Each night, besides the kill, frame one player: if the Detective checks them tonight, they
read Mafia."

**Rules**
- He is one of the Mafia seats, never the Sheikh, so he exists only with 2+ Mafia.
- At night he has two picks: the kill vote, then the frame.
- His teammates know he is the Framer (as they know the Sheikh).
- He stays `mafia` for the team chat, stats, titles and older phones.

**Edge cases**
| # | Case | Ruling |
|---|---|---|
| E-F1 | Framing a teammate | Not offered (Mafia already reads Mafia, and the Sheikh is meant to read clean) |
| E-F2 | **The Detective sees his result straight after his pick** (online and pass-and-play). The frame may not be in yet | **When a Framer is in the game, the Detective's result comes in the morning.** Other modes are unchanged |
| E-F3 | **The Detective's list of past results** is recomputed from the roles | A framed "Mafia" would turn "not Mafia" the next day. **Each result is stored the night it is read** (in the log), so the list never changes |
| E-F4 | The Framer is killed the same night | The night is simultaneous: the frame still counts. If the host **removed** him mid-night, it doesn't count (like the kill vote) |
| E-F5 | He runs out of time | His kill vote and his frame are one turn, so neither counts (corrected after Quin Q12). On his screen he must choose a frame or "No frame" before he can confirm (Quin Q5) |
| E-F6 | The Framer dies | Nobody takes over the frames (the Sheikh's power never passes either) |
| E-F7 | Best Detective | A framed Citizen read as Mafia is **not** a catch |
| E-F8 | **"Tell the Mafia whether it hit"** (Brad's idea, so the role isn't boring) | It also tells the Mafia **whom the Detective checked**, which is strong. **R4** |
| E-F9 | Framing the Mafia's own kill target | Allowed, but useless if they die |

---

## 4 · Watcher (المراقب), town
**Card:** "Each night, watch one player. In the morning you learn who visited them."

**Rules**
- He picks one living player, not himself.
- In the morning his phone lists the names of the visitors (not their roles), or "Nobody".
- His past results stay on his role card, like the Detective's.

**What counts as a visit** (the pick is what counts, not where the kill ended up):
- the Doctor's protection;
- the Bodyguard's guard;
- the Detective's check;
- the Framer's frame;
- the Sniper's shot (not a kept bullet);
- the Mafia (E-W1).

**Edge cases**
| # | Case | Ruling |
|---|---|---|
| E-W1 | **Ben owns this one: our Q5 suggestion was too strong.** "Every Mafia who voted for the target visits" means watching the victim names **every Mafia** at once. With 3 Mafia agreeing, one night solves the game | **R5**: one Mafia visits. That is the Sheikh if he voted for the target, else the lowest seat that did. ToS does the same (one Mafia goes) |
| E-W2 | A decoy tap (Citizen, Jester, Hunter, Mayor at night) | Not a visit |
| E-W3 | Tied Mafia vote, or skip | No kill means no Mafia visit |
| E-W4 | The Bodyguard takes the kill meant for X | The Mafia and the Bodyguard visited X. Nobody visited the Bodyguard |
| E-W5 | His target dies that night | He still gets the list |
| E-W6 | The Watcher dies that night | He still sees his result (like the Detective today, a kept quirk) |
| E-W7 | The Sniper on night 1 (can't shoot) or keeping his bullet | No visit |
| E-W8 | Pass-and-play | His result shows at the start of his next night turn, and on his role card |
| E-W9 | Two Watchers | One per game (every mode deals at most one) |

---

## 5 · Avenger mode (beginner), 6+ · the Hunter's mode, never a Sniper
The Mafia count is the current one (about one in four), so Brad's "3 Mafia at 9" is really 2 at 9, as in every mode today.

**His notes (2026-11-26):**
- The Sniper at 17 was too late, and groups of 7–8 never got the Mayor. The Mayor now comes in at 7.
- No mode deals both the Sniper and the Hunter, so the Sniper is gone from this mode.

| Players | Mafia | Town | Neutral |
|---|---|---|---|
| 6 | 2 (Sheikh) | Doctor, Detective, Hunter, 1 Citizen | – |
| 7–8 | 2 | Doctor, Detective, Hunter, **Mayor**, 1–2 Citizens | – |
| 9 | 2 | Doctor, Detective, Hunter, Mayor, 2 Citizens | Jester |
| 10–12 | 3 | Doctor, Detective, Hunter, Mayor, 2–4 Citizens | Jester |
| 13–20 | 3–5 | + Bodyguard, Citizens | Jester |

**Edge cases**
- E-A1: at 6, the 2 Mafia face a Hunter, so a night kill can cost them a teammate. That's the point, and playtests will tell.
- E-A2: at 7, four of the five town players have a power and one is a plain Citizen. The Mayor is the weakest of them (public, and no Doctor once revealed), so the Mafia still have targets.
- E-A3: the Jester comes in at 9. Neutral is 1 in 9 (11%), inside his 10%.
- E-A4: the Bodyguard switch (the Sniper and Jester modes' optional Bodyguard) doesn't apply here: this mode's deck is fixed.

## 6 · Shadows mode (information vs deception), 8+ · the Sniper's mode, never a Hunter
- The Sniper comes in at 8 (it was 17). He is the town's way to act on what the Watcher and the Detective find.
- He also balances R6: at 8, both Mafia have a power.

| Players | Mafia | Town | Neutral |
|---|---|---|---|
| 8 | 2: Sheikh + Framer | Doctor, Detective, Watcher, **Sniper**, 2 Citizens | – |
| 9 | **3**: Sheikh + Framer + Mafia (or 2, §8) | Doctor, Detective, Watcher, Sniper, 2 Citizens | none with 3 Mafia; Jester with 2 |
| 10 | 2–3 | Doctor, Detective, Watcher, Sniper, Citizens | Jester |
| 11–12 | 3 | + **Mayor** | Jester |
| 13–20 | 3–5 | + Bodyguard | Jester |

**Edge cases**
- E-S1: at 8, both Mafia have a power. The Sheikh reads clean and the Framer makes town read dirty, so the Detective alone can be wrong every night. The Watcher and the Sniper are the town's answer. **R6: kept (his ruling).**
- E-S2: the Detective's result moves to the morning in this mode (E-F2). The mode card says so.
- E-S3: the Sniper keeps his 1.1.0 rules: one bullet, none on night 1.

## 7 · Every mode, every role (S20-1, nothing may break)
| # | Case | Ruling |
|---|---|---|
| E-X1 | 1.2.1 phones in an online room or as a Wi-Fi guest with these modes | Both use the room screen, which already says "Update to play" on an unknown role |
| E-X2 | 1.2.1 phones opening History, a game's page, the bell or a player's page | The server sends them a role they know (`role`, with Hunter / Mayor / Watcher → Citizen) and the real one in `role2` |
| E-X3 | A 1.2.1 Wi-Fi host | It can't pick the new modes, so nothing changes |
| E-X4 | Every pick can be skipped (Hunter's shot, Framer's frame, Watcher's watch) | Through "Continue anyway", the night timer and Remove. The random-game test plays thousands of games where players randomly stop answering |
| E-X6 | **The Sniper and the Hunter are never in the same game (his rule)** | No mode deals both. `validateSetup` also refuses such a deck (error `sniperHunter`), so a later Custom or All mode can't either |
| E-X5 | The host removes a player mid-shot (e.g. removes the Hunter while he aims) | Counts as holding fire, and the game goes on |

---

## 8 · What a table can change, and what it can't (decided, nothing left to chance)
His note (2026-11-26): make the modes adjustable within limits if possible, count the table rules in, and decide
everything.

### What our own games say (David, read-only production query, 60 valid games)
- **59 of the 60 games were played with "reveal roles" off**, with the Doctor allowed to protect himself, the Mafia's
  skip on, and the decoy on. So the counts below are tuned for **reveal off**, the way the group really plays.
- The leans so far (small samples, a hint and not proof):
  | Mode and size | Town won | Mafia won | Jester won |
  |---|---|---|---|
  | Classic, 4 players, 1 Mafia | 21 | 5 | – |
  | Sniper mode, 6–7 players | 14 | 4 | – |
  | Jester mode, 7 players | 2 | 6 | 2 |

  The Sniper mode leans town and the Jester mode leans Mafia. That's for 1.4.0, when All and the old modes get the same
  limits as below.

### A. Who can change what
| Mode | Roles | Number of Mafia | Table rules |
|---|---|---|---|
| Classic | The table picks (as today) | 1 to the engine's limit (as today) | All free. The setup shows the lean line (C) as information |
| Sniper, Jester, Bodyguard, All | Fixed (the Bodyguard switch stays) | Fixed (as today) | All free, and the setup shows the lean line |
| **Avenger, Shadows** | Fixed by the player count (tables above) | **A choice of two where the table below says so** | All free, and counted (C) |

The old modes stay fixed this sprint: a 1.2.1 phone in the lobby works their deck out itself, and a changed count
would show it the wrong deck. They get ranges in 1.4.0, with All.

### B. Number of Mafia in the new modes (**bold** = the default)
| Players | Avenger | Shadows |
|---|---|---|
| 6 | 1 or **2** (1 Mafia: no Detective, as in Classic) | – |
| 7–8 | **2** | **2** (at 8) |
| 9 | **2** | 2 or **3** (3: no Jester; 2: + Jester) |
| 10–13 | 2 or **3** | 2 or **3** |
| 14–17 | 3 or **4** | 3 or **4** |
| 18–20 | 4 or **5** | 4 or **5** |

So, his example, 9 players:
- **Avenger:** 2 only.
- **Shadows:** 2 or 3, default 3.
- **Classic:** 1 to 3, the table's choice, as today.

### C. The rules count: the "lean"
Each rule that clearly helps one side counts one or two points against the way the group usually plays (reveal off,
Doctor self on, Mafia skip on, decoy on, Reveal saves off):
| Rule changed | Points |
|---|---|
| Reveal roles **on** | town +2 |
| Reveal saves **on** | town +1 |
| Mafia "no repeat target" **on** | town +1 |
| Doctor may protect himself **off** | Mafia +1 |
| Doctor "not the same player twice" **on** | Mafia +1 |
| Decoy **off** (at a real table, only the power roles tap) | Mafia +1 |
| Mafia skip, ghost, the vote rules, the timers | 0 (no clear lean) |

How the lean is used:
- **Lean = Mafia points − town points.**
- **Lean 2 or more:** the higher number of Mafia isn't offered. The setup says "With these rules, N Mafia is too hard for
  the town".
- **Lean −2 or less:** the lower number isn't offered, and the setup says the same the other way round.
- Where B allows only one number, the count can't change, and the setup just shows "These rules favour the Mafia / the
  town".
- **Example:** Shadows, 9 players, Doctor "not twice" on and decoy off: lean 2, so 2 Mafia (+ Jester) only.

### D. Rules that touch the new roles (decided)
| Rule | Ruling |
|---|---|
| Night timer | Online and Wi-Fi: the **Hunter's shot gets the same time**; when it runs out, he holds fire. With no night timer, the host's "Go on without his shot" ends his wait. Pass-and-play: no clock on his shot (the phone waits for him; Quin Q2) |
| Ghost | E-H8: the Hunter sees no roles until he has shot |
| Reveal off | E-H9 (R1) |
| Doctor self / not twice | They apply to the Doctor as today. A revealed Mayor can't be picked by the Doctor at all (R2: the Bodyguard can) |
| "The table decides" (pass-and-play) | No vote to double (R3) |
| Vote rules (skipVote, tieSkip) | The Mayor's double vote goes into the same count, then the same tie rules |

### E. How we make sure everything fits
- `validateSetup` refuses any count outside B or C, so neither the server nor a Wi-Fi host can deal one.
- **One test plays every combination:**
  - every mode × every player count, 4–20;
  - × every Mafia count the setup offers;
  - × all 64 on/off combinations of the six counted rules.

  Each combination must deal a valid deck with no Sniper next to a Hunter, and 50 seeded random games of each must all
  end with one winner.
- Every release, David reruns the production query above (read-only) and the report shows the town / Mafia win rates
  per mode. If a mode leans past 65 / 35 over 30+ games, Ben brings a change to him.
