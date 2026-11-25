# Sprint 17 PRD: 1.0.0, new roles as MODES

2026-11-25. **Draft for his sign-off. No application code before it.**

> **[Ben · BA] Read this first.** His requirements came as rulings in chat (2026-11-25, all in `docs/decisions.md`):
> شيخ المافيا in every game (wins Mafia ties, reads "not Mafia" to the Detective, never passed on; with no Sheikh's
> pick the lowest seat decides), Sniper whose shot nothing stops, الجوكر, the "All roles / كل الأدوار" mode, and
> everything in 1.0.0. What is still marked **[BA] proposal** waits for his sign-off with the rest of this PRD.

**What a mode is (his rule):** a fixed set of roles and rules, chosen with one tap, not roles picked one by one.

## Audit: where we stand

### Current code
- Four roles, a closed set in **both engines**: TS `packages/engine/src/types.ts` (online, server) and Dart
  `packages/engine_dart/lib/src/types.dart` (offline, Wi-Fi). `engine_test.dart` replays the shared games through
  both; every new role must go into those games.
- `Counts {mafia, doctor, detective}`: Doctor always 1, Detective 0–1 and only with 2+ Mafia
  (`setup.ts` `fixCounts`). `PRESETS` (Classic, Beginner) are rule bundles only; `presetOf()` shows "Custom" when the
  rules match neither. Modes are the natural next step above presets.
- The game rules are hard-wired to the four roles: `winnerOf()` counts `'mafia'`; `nightOptions()` and the night
  record have one slot each for mafia/doctor/detective; the morning holds **one** death (`morning.dead`);
  `Winner = 'mafia' | 'citizens'`.
- The protocol is strict: `counts` is `{mafia 1–10, detective 0–1}` with `.strict()` (`packages/protocol`), and the
  app's `Role` enum has four values. **An old app that receives an unknown role name breaks.**
- Room members already report their app build (`v` online, `build` on Wi-Fi), and the lobby shows "old version".
- Stats and leaderboard (`server/src/stats.ts`): side = Mafia vs everyone else; titles Best player / Best Mafia / Best
  Detective / Best Doctor / Most killed first; the profile has a per-role table over the four roles.
- Saved games (`GameRecord format: 1`), the old-app import (`fromOld`) and the leaderboard must stay readable.
- About 20 files name the roles (app setup, lobby, play, role card, recap, guide, profile, colours/icons in
  `core/ui.dart`, l10n EN/AR, server room/stats/users/legacy, protocol).

### As a player (screenshots `docs/qa/journey15/j03_setup.png`, `j19_lobby_4.png`)
- Offline setup: Players, then **Roles** (Mafia −/+, Doctor "always one", Detective −/+), then the rules card
  (Classic / Beginner / Custom chips), then Deal. The online lobby has the same Roles card and a summary line
  ("4 players · 1 Mafia · Doctor · Classic").
- Friction today: a new group has to know how many Mafia to pick; the summary line says "Classic" for the *rules*
  only, which will read wrong once "Classic" is also a mode. The Roles card already takes most of a screen; adding
  steppers per new role would make it worse. One tap on a mode fixes both.

### Old app (`../mafia-dealer`)
- The same four roles and the same Classic / Beginner presets; **no modes, no other roles.** Nothing to lose on
  parity; the parity duty here is that **today's game stays exactly as it is** (Classic, steppers, Beginner, the
  guide's suggested setup) and old saved games, old-app imports and stats still read.

### Market ([Brad · Market], 2026-11-25; sources thin, mostly store listings and role pages)
- **Modes are normal in the genre:** Town of Salem leads with preset modes (Classic, Ranked, Rapid, themed) plus a
  Custom mode ([wiki](https://town-of-salem.fandom.com/wiki/Town_of_Salem_Wiki:Custom_Setups_(Coven))). Wolvesville,
  Mafia42 and Mafia Mystery carry 20–30+ roles, often paid; Godfather and Sniper are common.
- **The main Arabic app, جمعة مافيا** ([roles](https://jm3tmafia.com/roles)), has as its *core* set Mafia, Citizen,
  Detective, Doctor and **Sniper** (one bullet; a wrong shot kills only the Citizen hit, the Sniper stays in).
  Joker (wins if voted out), Witch, Spy and others are paid extras.
- **Arabic names in use:** مافيا, مواطن, محقق, طبيب, قناص, جوكر (Jester), ساحرة, جاسوس. **العرّاب is used there for the
  narrator**, not the Mafia boss (another source uses it for the boss): a clash for us. مهرّج had no app hits.
- **What players dislike:** weak roles bore people, complicated roles slow the table, too many strong roles break the
  balance (forum games, not app reviews); games under about 7 players feel thin. Mafia Mystery reviewers complain
  about paid roles.
- About a quarter of players as Mafia (1 for 5–6, 2 for 7–9, 3 for 10+), one source: matches our suggestion.
- **Not found:** regional differences (Gulf, Levant, Egypt, North Africa), Ramadan play, الذيب. Not used as facts
  here; a few real Arabic groups would be the next source.

## Part A: groundwork (holds for any modes)

### S17-1 Mode in the setup, one tap
- AC: setup (offline, Wi-Fi lobby, online lobby) shows a **Mode** card above Roles: one chip/tile per mode, with its
  name and one line. One tap picks it; the Roles card then shows the mode's deck for the current player count, read
  only (except Classic, below). Widget test per screen, EN and AR.
- AC: a mode that needs more players than are seated is shown but disabled with "from N players". Test.
- AC: the summary line names the mode ("9 players · All roles · …"), not the rules preset. Test.
- AC: the chosen mode is saved with the setup (prefs and account) like the counts today; a saved setup without a
  mode opens as Classic. Test.

### S17-2 Classic is today's game plus the Sheikh
- AC: Classic keeps the Mafia/Detective steppers, Doctor 1, Beginner/Classic rule chips and every existing limit.
  The one change is S17-8: one of the Mafia is شيخ المافيا. Every existing saved game and shared test game replays
  to the same result in both engines (they keep their own tie rule).

### S17-8 شيخ المافيا in every game, and the Mafia's vote (his ruling, 2026-11-25)
- AC: every game deals one Mafia as **شيخ المافيا / the Sheikh** (with one Mafia, he is the Sheikh). His role card and
  the Mafia's night screen say who he is; the other Mafia see him as their Sheikh. Test.
- AC: the Mafia's kill is the choice with the **most votes**; on **any tie the Sheikh's pick wins, even if nobody
  else picked it** (5 Mafia: 2 on P1, 2 on P2, Sheikh on P3 → P3). The Mafia beat him only with a clear majority
  without a tie (3 Mafia: 2 on P1, Sheikh on P2 → P1). A tie never kills nobody. Engine test per example, TS and Dart.
- AC: if the Sheikh picks "skip" and it decides the tie, the night is skipped and the one-time skip is spent. Test.
- AC (his ruling): **the Sheikh role is never passed on.** Once he is killed or voted out, the game has no Sheikh.
- AC: a tie with no Sheikh's pick (he is out, or alive but didn't vote: night timer ran out, offline and skipped by
  the host) is settled by **one fixed rule with no randomness**; the same rule covers both cases. **His ruling (2026-11-25):
  lowest seat decides.** Among the Mafia who voted for one of the tied picks, the one in the lowest seat wins. No
  extra step; offline it is also "who voted first" (the phone goes round in seat order), so offline, Wi-Fi and online
  share one rule. Not a successor: nothing on his role card, no Detective cover. (Brad's research: no app publishes
  a night-tie rule; Town of Salem always names one decider. Re-vote and earliest-vote were rejected.)
  Test per case, TS and Dart.
- AC (his ruling): **the Detective's check always reads "not Mafia" on the Sheikh**, in every game. The Detective's
  "caught" stat doesn't count him. Test.
- AC: non-Mafia never see that a tie happened or who settled it (Brad). Test.
- AC: the night screen shows each Mafia how the votes stand and marks the Sheikh's pick, so they know a tie goes to
  him. Widget test, EN and AR.
- AC: games saved before 1.0.0 replay with their own tie rule (random, or no kill since Sprint 7). Test on both
  fixture sets.

### S17-3 Both engines in step
- AC: every new role has at least one shared test game where it acts and one where it decides the end; each replays
  to the same `winner` and `log` in TS and Dart (`engine_test.dart`).
- AC: the mode is frozen into the game when dealt (like the rules), so a replay never depends on today's mode table.
  A record without it replays as Classic (every existing saved record: test with a pre-1.0 record).

### S17-4 Old apps can't break a 1.0.0 game
- **His ruling (2026-11-25, Quin Q4): every table needs 1.0.0, Classic too.** The deal waits until every seated
  phone is on 1.0.0; the lobby names the ones that need updating.
- Since every game now has a Sheikh, **every** game is new to an old app, not only the new modes.
- AC online: an old app (build below 100017 or unknown) in a room either plays correctly (the server shows it the
  Sheikh as plain Mafia, if that works) or the server refuses to deal while it is seated; the host sees who must
  update (the existing "old version" tag) and the deal button explains why. Never a crash or a wrong screen. [Dev]
  picks which in the build; Danial checks it. Server test + lobby widget test.
- AC Wi-Fi: the host phone does the same for guests. Test.
- AC: a 1.0.0 phone that receives a role it doesn't know (a later version) shows "Update the app" instead of
  crashing. Test.

### S17-5 Stats, history and leaderboard stay right
- AC: history, recap and the profile's role table show the new roles with their names, colours (4.5:1 on the paper
  recap, as S16-5) and icons. Test.
- AC: winning side is computed per role (see each role's side), not by `role === 'mafia'`. Existing stats unchanged
  for old games (test on the current fixtures).
- AC: old-app imports still import (four roles only). Test.

### S17-6 How to Play
- AC: the guide has a Modes section: each mode, its roles by player count, and each role's power, side and how it
  wins, from the same table the setup uses (no second copy to drift). EN and AR. Test.

### S17-7 1.0.0
- AC: `app/pubspec.yaml` `version: 1.0.0+1` with build 100017 or higher; the About/version line shows 1.0.0.

## Part B: [BA] proposals for the modes (for him to replace)

Picked from the genre (Mafia/Werewolf party games) for **one rule each that a table can explain in a sentence**, and
ordered by cost in our engine.

### Proposed roles
| Role | Arabic | Side | Power | Wins | Engine cost |
|---|---|---|---|---|---|
| Sheikh (Godfather) | شيخ المافيا | Mafia | **In every game.** His pick wins any tie in the Mafia's vote; **the Detective always reads him "not Mafia"** (S17-8, his rulings) | with the Mafia | small: one rule in the tally, one in the check |
| Jester | الجوكر | alone | No night power (picks a decoy like a Citizen) | **alone, if voted out by day**: the game ends at once | medium: a third winner |
| Sniper | القنّاص | Citizens | **One bullet per game**, fired at night; **nothing stops it, the Doctor can't save** (his ruling) | with the Citizens | large: two deaths in one morning |

- The Sheikh counts as Mafia for the win (`Mafia ≥ everyone else`) and sees/is seen by the Mafia. His tie rule is
  S17-8.
- **Hiding from the Detective: his ruling, kept in every game** (2026-11-25; Ben had recommended dropping it). The
  Detective can find every Mafia but the Sheikh; the day vote is the only way to catch him. For the playtest: watch
  whether games where the Sheikh is the last Mafia feel too hard for the Citizens.
- **Arabic names:** **شيخ المافيا** (his ruling, 2026-11-25; not العرّاب, which the main Arabic app uses for the
  narrator); الجوكر, not المهرّج, because جوكر is the name Arabic players know.
- Jester counts as "everyone else" in that count; killed at night or removed by the host = just out, no win.
- **Sniper (his ruling, 2026-11-25): the target dies and nothing stops it; the Doctor can't save it.** The rest are
  [BA] proposals:
  - he may shoot on any night, night 1 included, or keep the bullet; never himself;
  - a wrong shot kills that player and the Sniper stays in the game (the familiar rule);
  - if the Mafia and the Sniper pick the same player, one death; if the Doctor saved the Mafia's target and the
    Sniper shot the same player, the player still dies;
  - the morning can name two dead and **doesn't say which death was the Sniper's** (keeps the guessing);
  - shooting the Jester at night: the Jester is just out, no win; the win check runs after both deaths.

### Proposed modes (counts by players; Mafia = today's suggestion, about one in four)
| Mode | Arabic | Roles | Players |
|---|---|---|---|
| Classic | كلاسيك | today's game with the Sheikh, adjustable as now | 4–20 |
| Sniper | القنّاص | Classic + Sniper (the Sniper is core in the main Arabic app) | 6–20 |
| Jester | الجوكر | Classic + Jester | 6–20 |
| All roles | كل الأدوار | every role: Mafia with the Sheikh, Doctor, Detective always in, Jester, Sniper | 9–20 |

- The Sheikh (with his Detective cover) is in every mode, so there is no separate Godfather mode.
- Each mode shows its minimum on its tile (S17-1 "from N players").
- In every mode except Classic the roles are fixed by the player count; **the rules (skip, reveal, timers…) stay
  adjustable** (they change the pace, not the balance) — proposal.
- All modes in offline, Wi-Fi and online.
- Later than 1.0.0: Witch, Bodyguard, Spy (common, often paid, in other apps). No role that keeps the Detective's
  result unclear for more than one night.
- **Never paid:** every mode and role is free (reviews of Mafia Mystery complain about paid roles) — proposal.

### Other [BA] proposals
- **P1** "Suggested" badge: the setup marks the best mode for the seated count (e.g. Classic under 6, Sniper 6–8,
  Showdown 9+).
- **P2** Role card shows the side and the win condition in one line, not only the power (new roles need it).
- **P3** Leaderboard: no new titles in 1.0.0; the Sheikh counts toward Best Mafia, Jester wins toward Best player.
  New titles (Best Jester…) later if he wants them.
- ~~P4 Sniper in 1.0.1~~: dropped, his ruling: **the Sniper ships in 1.0.0**.

### Challenge log (PRD)
| Who | Whom | About | Outcome |
|---|---|---|---|
| Brad | Ben | العرّاب clashes with the narrator in the main Arabic app | accepted; his ruling: شيخ المافيا |
| Brad | Ben | المهرّج unknown to players; جوكر is the name in use | accepted: الجوكر |
| Brad | Ben | Sniper is a core role for Arab players, not an extra | accepted: Sniper mode added; P4 left to him |
| Brad | Ben | games under 7 feel thin | accepted: Godfather 7+, minimum on every tile |
| Ben | Brad | no evidence on regional variants or الذيب | accepted by Brad: nothing regional stated as fact |
| Alhassan | Ben | "a tie never kills nobody" | accepted. Ben's miss: he described the current tie rule without saying it came from Sprint 7 ("any tie implies skip", 2026-11-23) or what it costs players. His new rule replaces it (S17-8) |
| Ben | Brad | re-vote (Brad's first pick) costs a second full pass of the phone offline | Brad had already ranked lowest seat first for Arabic groups; both now recommend (1) |

## Part C: what he decides
1. **His modes** (names, roles, counts by players) and his roles (power, side, win, Arabic name) — or accept Part B.
2. Classic kept as a mode with its steppers? (BA: yes.)
3. Anything adjustable inside a non-Classic mode? (BA: rules yes, roles no.)
4. Which modes in offline / Wi-Fi / online? (BA: all.)
5. Stats/awards for new roles (BA: P3).
6. Decided: everything ships in 1.0.0, the Sniper included.
7. Decided: nothing stops the Sniper's shot, the Doctor can't save; the Sheikh is in every game and wins every tie.
8. Decided: شيخ المافيا and الجوكر.
9. Decided: the Detective always reads the Sheikh "not Mafia"; no Godfather mode.
10. Decided: no successor; with no Sheikh's pick, the lowest-seat Mafia among those who voted for a tied pick decides.
11. Decided: "All roles / كل الأدوار".

## Out of scope
Group history, the Play Store build, the history-tile count, `docs/old-app-parity.md` tidy-up (open items in the
handoff).
