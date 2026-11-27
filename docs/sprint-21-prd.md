# Sprint 21 PRD: wave 2 (1.4.0): the Serial Killer, Cupid and the Lovers, the Silencer

**Sources and status**
- His order (2026-11-26): "Start sprint 21". Wave 2 was signed off in Sprint 20 (Q1).
- Brad's research: `docs/sprint-21-brad.md`. Wave 1's rules and edge cases: `docs/sprint-20-roles.md`.
- No role code is written. This PRD and the questions at the end wait for his sign-off.

## The data so far (read-only production query)
- There are 60 valid games, all from before 1.3.0. Avenger and Shadows have not been played yet.
- The leans are the same as before:
  | Mode | Town won | Mafia won | Jester won |
  |---|---|---|---|
  | Sniper | 14 | 4 | – |
  | Jester | 2 | 6 | 2 |
  | Classic | 22 | 8 | – |
- The win-rate recheck in §8 E needs real games with the new modes.

## Scope (proposed)
| Item | In 1.4.0 |
|---|---|
| **Serial Killer** (neutral) | yes |
| **Cupid and the Lovers** | yes |
| **Silencer** (a Mafia with a power, "can't vote") | yes |
| **Lovers** mode (8+) and **Lone Wolves** mode (9+) | yes |
| Mafia ranges and the rules lean for **Sniper, Jester, Bodyguard** | yes (small) |
| **All** gets every role | **Sprint 22** (Q1): it needs its own tables, and the Sniper-or-Hunter choice |

---

## [David · Dev] What wave 2 breaks today
| # | Where | What breaks | What we do |
|---|---|---|---|
| **D1** | **Who wins** | Only town, Mafia and Jester can win. With a living Serial Killer, "Mafia gone" would hand the town a win, and "Mafia ≥ the rest" would hand the Mafia one | A win check per side: the Serial Killer blocks both; the Lovers' and the Serial Killer's own wins; a **draw** (R3) |
| **D2** | **Database** | `games.winner` takes only mafia/citizens/jester, so a Serial Killer, Lovers or draw game **can't be saved**. `game_players.role` lacks `killer` and `cupid` | Migration 0015 widens both. `games` is rebuilt the way 0010 did it (copies first, because `game_players` and `wifi_requests` point at it), with a rollback |
| **D3** | **1.2.1 phones** | A 1.2.1 phone **crashes** opening a game with an unknown winner (`Winner.values.byName`). 1.3.x phones read it safely | The server sends `winner` as one they know and the real one as `winner2`, like `role` and `role2` |
| **D4** | **Chains of deaths** | A lover dies and the partner follows; the Hunter shoots a lover; a lover is the Hunter | One queue: each seat dies once, in a fixed order, and the win check runs at the end. The Hunter aims after the queue is empty |
| **D5** | **More deaths a night** | The Mafia, the Serial Killer, the Sniper and a broken heart can make four deaths; the morning holds only two | A `deaths` list. Old phones can't join these modes (D6) |
| **D6** | **The gate** | Lovers and Lone Wolves deal roles 1.3.x doesn't know | `ROLES14_BUILD = 100025` (if 1.4.0 is release run 25), as `ROLES13_BUILD` |
| **D7** | **The vote** | A silenced player would hold up the vote forever | He counts as abstaining from the start, and his phone says why |
| **D8** | **Stats** | `won()` uses the role's side: a Mafia lover winning with the Lovers would count as lost, and the Serial Killer has no side | Each seat wins by its own result. The Lovers are kept in the game's stats |
| **D9** | **Hunter + new wins** | The Hunter's "shoot first" only delays a Mafia win | It delays any win but the town's, so a Serial Killer win waits for his shot too |

---

## The roles (Ben's draft; open points are R#)

### Serial Killer (القاتل المتسلسل), neutral
**Card:** "You are alone. Each night you kill one player. You win when you are the last one standing."

**Rules**
- He picks a living player each night, from night 1. He is not offered himself.
- The Doctor's save and the Bodyguard's guard work on his kill, as on the Mafia's.
- He and the Mafia picking the same player is one death.
- No immunity: the Mafia can kill him (R2).
- The Detective reads him **"not Mafia"** (R2).
- He shows up to the Watcher as a visitor.
- **Endings with him alive (R3):**
  - The town can't win while he lives, and neither can the Mafia.
  - He wins when he is alone, or one of two with a non-Mafia.
  - **He and one Mafia left is a draw.**
- He comes only from 9 players.

**Edge cases**
| # | Case | Ruling |
|---|---|---|
| E-K1 | He kills the Hunter | The Hunter aims (wave 1 rules) |
| E-K2 | He kills a lover | The partner dies of a broken heart in the same morning |
| E-K3 | He targets the player the Bodyguard guards | The Bodyguard dies in their place (as for the Mafia's kill); the Doctor can save him |
| E-K4 | He is voted out | The game goes on by the normal rules |
| E-K5 | The host removes him | As any removal; the win check runs |
| E-K6 | He and 2 Mafia, nobody else | Play on: the Mafia can vote him out by day |
| E-K7 | Reveal off / the ghost rule | As any role |

### Cupid (كيوبيد) and the Lovers (العاشقان)
**Card (Cupid):** "On the first night, link two players. If one dies, so does the other."

**Rules**
- Cupid is town. On night 1 he picks two different living players; he may pick himself (R5).
- After night 1 he is a Citizen.
- **The lovers learn their partner in the morning of day 1:** name only, or name and side (R4).
- **The link:** when one lover dies, by night, by vote or by the Hunter, the other dies at the same moment, "of a broken heart", announced (R6). Nothing stops it: not the Doctor, not the Bodyguard.
- **How lovers win:**
  - A couple on the same side wins with that side.
  - **A mixed couple** (one Mafia, one not) wins **only as the last two alive**, ahead of every other count.
  - A Mafia lover still sees his team and votes with them at night.

**Edge cases**
| # | Case | Ruling |
|---|---|---|
| E-C1 | The lover voted out is the Jester | The Jester wins at once (his own win comes first); the partner's death doesn't matter |
| E-C2 | A lover is the Hunter | When his partner dies, he dies of a broken heart and then aims. Brad proposed "the Hunter can't be a lover", **but that would tell Cupid who the Hunter is** (his option greyed out). Ben's finding: allow it; the death queue (D4) handles it |
| E-C3 | The Hunter shoots a lover | The partner dies too, then the win check |
| E-C4 | The host removes a lover | **The partner lives** (R7): a removal is someone leaving, as the Hunter gets no shot when removed |
| E-C5 | Cupid times out, or picks only one | No link this game |
| E-C6 | Cupid dies on night 1 | The link still holds (one moment, as the Framer) |
| E-C7 | Both lovers die the same night | Both are named once each; no second broken heart |
| E-C8 | The Mayor is a lover | No special rule |
| E-C9 | The Watcher | Cupid visits both lovers on night 1 |
| E-C10 | Old phones | Gated (D6); in History the lovers are plain roles |

### Silencer (المُسكِت), a Mafia with a power (like the Framer)
**Card:** "You are Mafia. Each night, besides the kill, pick one player: they can't vote tomorrow."

**Rules**
- He is one Mafia seat, never the Sheikh or the Framer.
- His pick goes with his kill vote, in one turn, like the Framer's frame.
- The morning tells everyone **"X can't vote today"** (R8).
- In the vote, X counts as abstaining from the start (D7), and X's phone says "You can't vote today".
- He can't pick the same player two nights running, nor himself. He may pick a teammate (R8).
- **"The table decides" (one phone, pass-and-play):** there's no vote to block, so the morning line is only information (as the Mayor's ×2).

**Edge cases**
| # | Case | Ruling |
|---|---|---|
| E-S1 | The silenced player is the revealed Mayor | He has no vote at all that day |
| E-S2 | The Silencer is killed or removed that night | Killed: his pick still counts. Removed: it doesn't (as the Framer) |
| E-S3 | The silenced player dies that night | Nothing to announce for him |
| E-S4 | The vote with every living player silenced but one | Impossible: he picks one player a night |
| E-S5 | Timeout | No kill vote and no silence (one turn, as the Framer) |

---

## The modes (never the Sniper with the Hunter; the Mafia count is a range where shown, **bold** = default; the lean applies as in §8)

### Lovers (8+): Cupid's mode
| Players | Mafia | Town | Neutral |
|---|---|---|---|
| 8 | **2** | Doctor, Detective, Cupid, 3 Citizens | – |
| 9–10 | 2 or **3** | + Hunter | Jester |
| 11–12 | **3** | + Mayor, Bodyguard | Jester |
| 13–16 | 3 or **4** | + Watcher | Jester |
| 17–20 | 4 or **5** | the Sniper instead of the Hunter | Jester |

### Lone Wolves (9+): the Serial Killer's mode
| Players | Mafia | Town | Neutral |
|---|---|---|---|
| 9–10 | **2** | Doctor, Detective, Bodyguard, Citizens | Serial Killer |
| 11–12 | **3**: one is the **Silencer** | + Watcher | Serial Killer, Jester |
| 13–16 | 3 or **4**: the Silencer and the **Framer** | + Mayor | Serial Killer, Jester |
| 17–20 | 4 or **5** | + Hunter | Serial Killer (one or two: R9), Jester |

Ben placed the Silencer in Lone Wolves (Brad hadn't placed him), because a mode for a thinking table suits the vote ban.

### The old modes get Mafia ranges (R10)
**Sniper, Jester and Bodyguard:**
| Players | Mafia (**default**) |
|---|---|
| 6 | 1 or **2** |
| 7–9 | **2** |
| 10–13 | 2 or **3** |
| 14–17 | 3 or **4** |
| 18–20 | 4 or **5** |

- These are the same bands as Avenger, and the lean applies.
- **A 1.3.x phone** in such a lobby sees the default deck instead of the chosen count, but the server deals right. It doesn't crash, so there's no gate.

---

## Acceptance criteria
**S21-1 · Nothing breaks (before any role)**
- AC1: migration 0015 keeps every row, saves the new winners and roles, and has a rollback. Evidence: a server test.
- AC2: a 1.2.1 phone gets `winner`/`role` it knows on every History, game page and Wi-Fi note path. Evidence: a server test.
- AC3: the every-combination test with the new modes and the old modes' ranges ends every game with one result (a draw included). 50 per combination before the release.
- AC4: every old record replays unchanged in both engines.

**S21-2 · Serial Killer:** E-K1–K7 as engine tests; the endings of R3; online, Wi-Fi and pass-and-play screens.
**S21-3 · Cupid and the Lovers:** E-C1–C10; the broken heart announced on every screen; the Lovers' win.
**S21-4 · Silencer:** E-S1–S5; the morning line; the silenced phone's vote screen.
**S21-5 · Modes:** Lovers and Lone Wolves deal their tables, and the old modes' ranges work, in the setup, the lobby and Wi-Fi; the gate (D6).
**S21-6 · Screens, stats, text:**
- EN/AR on a small phone at large text.
- The guide: new entries, and the endings.
- Stats per seat (D8); MVP for the Serial Killer and the Lovers.
- Version 1.4.0+9.

---

## His decisions (sign-off)
| # | Question | Suggestion |
|---|---|---|
| **R1** | Scope: three roles, two modes and the old modes' ranges now; All in Sprint 22? | Yes |
| **R2** | Serial Killer: no immunity; the Doctor and Bodyguard stop him; the Detective reads "not Mafia"? | Yes |
| **R3** | Endings with a Serial Killer: he wins alone or with one non-Mafia; **he and one Mafia = a draw**; nobody else wins while he lives? | Yes |
| **R4** | The lovers learn their partner's **name only** (Brad), or **name and side** (Ben: a Mafia lover sees his team anyway, so a town lover would be the only one who can't tell they're mixed)? | Name and side |
| **R5** | Cupid may pick himself? | Yes |
| **R6** | Announce "X died of a broken heart" (it shows a link existed)? | Yes |
| **R7** | The host removes a lover: the partner lives? | Yes |
| **R8** | Silencer: announced each morning; never the same player two nights running; not himself, teammates allowed? | Yes |
| **R9** | Lone Wolves at 17–20: **one** Serial Killer (Ben: two lone killers who must also kill each other make long games) or **two** (Brad: one isn't enough threat at 20)? | One, and judge it in a playtest |
| **R10** | The old modes get the ranges above? | Yes |
| **R11** | Arabic names: Serial Killer **القاتل المتسلسل** or **السفّاح**; Cupid **كيوبيد**; Lovers **العاشقان**; Silencer **المُسكِت**? | القاتل المتسلسل, كيوبيد, العاشقان, المُسكِت |
| **R12** | Phones before 1.4.0 see a Serial Killer, Lovers or draw game as "Citizens win" rather than crash (1.4.0 reads the real result from `winner2`)? | Yes |
