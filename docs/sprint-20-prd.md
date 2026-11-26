# Sprint 20 PRD: new roles and modes (1.3.0), plus the profile photo

His request (2026-11-26):
1. Opening a player's profile and tapping the photo should open it.
2. A list of new roles; Brad to review them and come back with plans for the modes.
3. "Make sure the roles don't crash the game, and give me the suggestions."

Where things stand:
- **Item 1 is built and tested.** It is not committed.
- **Item 2 is this PRD.** No role code is written yet. It waits for his sign-off on the questions at the end.

---

## S20-0 · The profile photo opens (built)
- **What it does:** on a player's page, tapping their photo opens it full screen on black, and you can pinch to zoom.
- **Preset pictures** (the 10 icons) don't open anything, because there's nothing bigger to show.
- **If the photo fails to load**, the full screen shows a broken-picture icon instead of crashing.
- **Code:**
  - `app/lib/features/stats/player_screen.dart` (the header);
  - the test is `app/test/profile_photo_test.dart`: it passes, and analyze is clean.
- **AC:** tapping a real photo opens it full screen with pinch-zoom, and tapping a preset does nothing. Status: done.

---

## [Brad · Market] what the research says
Brad's full report includes its sources. These are the parts that shape the plan.

**How other apps package roles**
- Apps sort roles into packs by difficulty, then by player count.
  - The WOLF party game has Classic (4–20), Advanced (6–12, adds the Hunter), Tactical, Chaos, and Expert (12–20, adds Cupid).
  - Ultimate Werewolf's app builds the deck from player count and a "moderator difficulty" setting.
- The Hunter and the Mayor are treated as safe for any table.

**Roles players rate badly**
- The Transporter is rated one of the worst roles: it's hard to pull off, and it confuses every result.
- The Witch is called overpowered.
- The Framer is called boring unless the Mafia sees it work.
- The Plaguebearer's "transform" (Pestilence in Town of Salem) takes many nights of hidden spread. It fits a long online game, not a party.

**Roles that need care at a real table**
- **Silencer:** a phone can't stop someone talking. The only version an app can enforce is **"can't vote"**, because the app collects the votes.
- **Hunter:** hosts ask for a quiet moment during the shot. The phone should own that moment.
- **Cupid:** mixed lovers (one Mafia, one Town) is the hardest rule for new players. It needs its own explanation screen.

**Arabic names:** Brad found no Arab Mafia app that lists these roles. His suggestions, still to be checked with players:
| Role | Suggested Arabic name |
|---|---|
| Hunter | **الصياد** (his choice; never in the same game as القناص, so they can't be mixed up) |
| Mayor | العمدة / المختار |
| Watcher | المراقب |
| Framer | الملفّق |
| Silencer | المُسكِت |
| Serial Killer | القاتل المتسلسل |
| Cupid | كيوبيد |
| Arsonist | الحارق |
| Veteran | المحارب |

### Brad's ranking (fun for the complexity)
| Wave | Roles | Why |
|---|---|---|
| **1 · ship first** | Hunter, Mayor, Framer, Watcher | Simple and dramatic. The Framer and the Watcher are the information/deception pair he asked for |
| **2** | Serial Killer (9+), Cupid / Lovers, Silencer ("can't vote" version) | Fun, but each one needs win-rule and chain-death rules |
| **3 · later** | Arsonist, Veteran, Tracker | Slow solo, or kills its own side by accident (Veteran shooting the Doctor), or weak next to the Watcher |
| **drop or redesign** | Transporter, Witch, Baker / Plaguebearer | Rated badly, has too many exceptions, or is too long for a party |

---

## [David · Dev] crash check: what each role would break today
I checked the engine (TypeScript and Dart), the server and the 1.2.1 app.

**C1 and C2 would hurt players today if a new role shipped without them.**

| # | Where | What breaks | What we do |
|---|---|---|---|
| **C1** | **1.2.1 phones** | History, a game's page, a Wi-Fi bell note and a player's page read the role with `Role.values.byName`. That **throws** on a name the phone doesn't know. A 1.2.1 phone would show a broken screen for any game with a Hunter in it | Live rooms are already safe: S17-4 shows "Update to play". For the history screens, the server sends old phones a role they know (`role`, as it already does with `best` / `best1`) and the real one next to it (`role2`). 1.3.0 reads every role through a safe reader |
| **C2** | **Database** | `game_players.role` and `games.winner` have a CHECK list. Saving a game with `hunter`, or a Serial Killer win, **fails**, and the game's result is lost | Migration 0014 widens both lists, the same table rebuild as 0010/0011, with a rollback |
| **C3** | **Engine, who wins** | Who wins is only "Mafia gone → town wins", and "Mafia ≥ the rest → Mafia wins". A living Serial Killer with no Mafia left would hand the **town** a win. Lovers and the Arsonist have no win at all | The win check is per side. A living neutral killer blocks the town's win, and the parity rule counts him. Covered by a random-game test (thousands of seeded games, every one must end) |
| **C4** | **Engine, stuck games** | Every new "someone must pick" moment can hang the game if that player is offline (the Hunter's shot, Cupid's night-1 pick) | Every new pick goes through "Continue anyway", the night timer and the host's remove, like night turns do now. A skipped Hunter shot is simply no shot |
| **C5** | **Engine, chain deaths** | Lovers, the Hunter shooting a lover, and two Hunters shooting each other could loop or double-count deaths | Deaths go through one queue. Each seat dies once, in a fixed order, and the win check runs after the queue empties |
| **C6** | **More than two deaths a night** | The morning holds `dead` and `dead2` only (the Mafia + the Sniper). The Mafia, a Serial Killer, a lover and the Sniper can make four | A `deaths` list. Old phones can't join these modes anyway (C1) |
| **C7** | **Day vote** | The Silencer's "can't vote" target: the vote waits until everyone alive votes, so the game would wait forever | The silenced player is counted as abstaining from the start, and their phone says why |
| **C8** | **Stats and titles** | Best Mafia, mates and the side counts check `role === 'mafia'`. A Framer or a Silencer would count as town | Proposal Q2 below avoids this entirely |
| **C9** | **Replays** | Every rule must play the same in TypeScript (server) and Dart (the phone host). Old records must replay unchanged | Rule version `rv: 3`, new fixtures, the Dart port in the same sprint. CI already fails on any mismatch |
| **C10** | **The Watcher's "visits"** | Citizens tap someone at night as a decoy (the `decoy` rule). If that counted as a visit, the Watcher would see fake visitors | Only real powers visit. **Q5** asks which Mafia "visits" the target |

**What it costs:** each role touches the TS engine, the Dart engine, the fixtures, the server (stats, migration) and the app.
- In the app that means the role card, the night screen, pass-and-play, the guide, and EN/AR text.
- **Four roles is a full sprint.** All 13 in one go would be three or four sprints, with a lot of risk.

---

## Proposed plan
| Sprint | Version | Roles | New modes |
|---|---|---|---|
| **20 (this)** | 1.3.0 | Hunter, Mayor, Framer, Watcher, plus all of C1–C10 that they need | **Avenger** (6+) and **Shadows** (8+) |
| 21 | 1.4.0 | Serial Killer, Cupid / Lovers, Silencer ("can't vote") | **Lovers** (8+) and **Lone Wolves** (9+) |
| 22 | 1.5.0 | Arsonist, Veteran, (Tracker?) | **Chaos Night** (10+) |
| — | — | Transporter, Witch, Baker | dropped unless he wants a redesign |

### The ratio
His rule is about 25% Mafia, 65% Town and 10% Neutral.
- **Mafia:** stays `recMafia` (about one in four, as today).
- **Neutral:** none under 9 players. Under 9, 10% would be less than one player. The Jester already fills the neutral slot.
- **Town:** everyone else.

### The new modes this sprint (fixed by player count, like Sniper / Jester / Bodyguard today)
| Mode | Min | 6–8 | 9–12 | 13–16 | 17–20 |
|---|---|---|---|---|---|
| **Avenger** · beginner (Hunter, no Sniper) | 6 | Mafia, Doctor, Detective, **Hunter**; **Mayor** from 7 | + Jester | + Bodyguard | same |
| **Shadows** · info vs deception (Sniper, no Hunter) | 8 | Mafia (one is the **Framer**), Doctor, Detective, **Watcher**, **Sniper** | + Jester; **Mayor** from 11 | + Bodyguard | same |

- Classic, Sniper, Jester, Bodyguard and All stay as they are this sprint.
- All gets the new roles once a wave is finished (Q7).
- **No mode ever deals both the Sniper and the Hunter** (his rule, 2026-11-26). The engine refuses such a deck.
- Full bands per player count: `docs/sprint-20-roles.md` §5–6.

### The rules for the wave-1 roles (Ben's draft; his questions are marked)
- **Hunter** (town):
  - When he dies, his phone asks him to shoot one living player, or to hold fire.
  - If he dies at night, he shoots during the morning, before the day starts.
  - If he is voted out, he shoots right after the verdict.
  - His shot can't be stopped (like the Sniper's).
  - The shot comes before the win check, so shooting the last Mafia wins it for the town.
  - The host's screen shows "the Hunter is aiming…".
  - If he is offline, "Continue anyway" skips his shot.
  - If he is removed by the host, he gets no shot.
- **Mayor** (town):
  - On any day, before the vote, he can tap **Reveal**. Everyone's screen then says he is the Mayor.
  - From the next vote on, his vote counts as two, open or secret.
  - The tally shows the totals only.
  - Whether the Doctor can still protect him is **Q4**.
- **Framer** (Mafia), **Q2**:
  - On top of the Mafia's kill vote, he picks one player to frame.
  - If the Detective checks that player the same night, the Detective reads "Mafia".
  - The Mafia's screen in the morning says whether the frame "hit" the Detective's check, so the role isn't boring (Brad).
  - **Interaction with the Sheikh:** the Sheikh still reads "not Mafia". Framing the Sheikh does nothing.
- **Watcher** (town):
  - Picks one player each night (not himself).
  - In the morning he learns who visited them: the Doctor, the Bodyguard, the Detective, the Framer, the Mafia (**Q5**), the Sniper.
  - Names only. Visitors' roles aren't shown.
  - Decoy taps aren't visits.
  - He can't watch the same player two nights running. **Q6** asks whether this rule should apply.

### Night order (fixed, shown in the guide)
1. Protections: the Doctor and the Bodyguard.
2. Kills: the Mafia and the Sniper, with the Bodyguard's cover.
3. Frames.
4. Reads: the Detective and the Watcher see the night as it ended.
5. Deaths are applied, then the morning, then the Hunter's shot.

---

## Acceptance criteria
**S20-1 · Crash-safety first (before any role is dealt)**
- AC1: a 1.2.1 phone opens History, a game's page, a bell note and a player's page for a game that has every new role. Nothing throws. Evidence: a widget test with a 1.2.1-shaped app against the new payload, and a server test that `role` is always one of the seven old roles.
- AC2: migration 0014 accepts the new roles and winners; the rollback restores the old tables; every old row is kept. Evidence: a server test that applies it the way CI does.
- AC3: 5,000 seeded random games across every mode and player count, 4–20, all end. None waits forever with everyone acted, and each has one winner. Evidence: a random-game test in TS and in Dart, with the same results.
- AC4: every old fixture (`records*.json`) replays unchanged in TS and Dart.

**S20-2 · Hunter**
- AC1: killed at night, he shoots in the morning. Voted out, he shoots after the verdict.
- AC2: the shot, holding fire, "Continue anyway" and a removal each work, and none of them hangs the game.
- AC3: shooting the last Mafia ends the game as a town win, with the Hunter's shot leading the announcement.

**S20-3 · Mayor**
- AC1: Reveal shows on every phone and on the host screen.
- AC2: his vote counts twice in secret and open votes, and the tie rules use the doubled count.
- AC3: once revealed, he stays revealed, and Reveal is gone from his screen.

**S20-4 · Framer**
- AC1: a framed player reads "Mafia" to that night's Detective only.
- AC2: framing the Sheikh changes nothing.
- AC3: in the morning the Mafia sees whether it hit.

**S20-5 · Watcher**
- AC1: he sees every real visitor. He never sees a decoy tap or himself.

**S20-6 · Modes**
- AC1: Avenger (6+) and Shadows (8+) are in setup for online, Wi-Fi and pass-and-play, and each deals the table above.
- AC2: below their minimum player count, setup says so, as with the current modes.

**S20-7 · Screens and text**
- AC1: each role has a role card, a guide entry and night/day screens in EN and AR, on a small phone at large text.
- AC2: stats, titles and the MVP count the new roles on the right side.
- AC3: 1.3.0+7.

---

## [BA] proposals (Ben)
1. **A one-screen "this mode's roles" card before the deal**, so the table knows what's in play. Brad notes Werewolf apps do this for their packs.
2. **A Custom mode later:** the host ticks which roles are in, and the app keeps the ratio and the pairing rule. It's not in this sprint.
3. **Ben's own find:** the guide lists every role (`Role.values`), so new roles appear there automatically. Each needs a short "how it ends" line too (the Hunter's shot, the Mayor's double vote), not just its night power.

---

## His decisions (sign-off)
| # | Question | Ben / David's suggestion |
|---|---|---|
| **Q1** | Scope: wave 1 (Hunter, Mayor, Framer, Watcher) this sprint, the rest in later sprints? | Yes |
| **Q2** | Framer (and later the Silencer): **a Mafia with a power**, like the Sheikh, instead of a separate role? He stays `mafia` for teammates, stats, titles and old phones, and gets one extra pick at night | Yes. It avoids C8 and half of C1 |
| **Q3** | Hunter: may he hold fire? | Yes |
| **Q4** | Mayor: can the Doctor protect him once revealed? | No, as he wrote ("usually cannot be healed") |
| **Q5** | Who counts as "visiting" for the Mafia's kill: every Mafia who voted for the target, or one? | Every Mafia who voted for it, which gives the Watcher real evidence |
| **Q6** | Watcher: no watching the same player two nights running? | No such limit. It only matters with "no repeat" |
| **Q7** | Add the new roles to **All** once each wave is done? | Yes, from 1.4.0 |
| **Q8** | Drop Transporter, Witch and Baker/Plaguebearer? | Drop. Revisit if the group asks |
| **Q9** | Arabic names: Brad's list, or yours? | His list |

Nothing is committed. His sign-off comes first, then David builds S20-1 before any role.
