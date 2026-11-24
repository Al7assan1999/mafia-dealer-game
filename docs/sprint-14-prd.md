# Sprint 14 PRD: the old app's look, everywhere (Noir and Neon)

2026-11-24. From Alhassan's six points after 0.4.6 ("Start now": signed off in the same message).
Reference: the old app rendered at 393 × 873 in both themes (`docs/qa/old-look/`, `docs/qa/old-look-neon/`, not committed).

## [BA] Audit (old vs 0.4.6, read from the screenshots)
| Area | Old app | 0.4.6 | Gap |
| --- | --- | --- | --- |
| Home top row | round avatar (50) + bell box at the start; flag, theme, gear boxes (42) at the end | avatar + @handle text, friends, bell, gear icons | different |
| Home logo | the hat-and-moustache mark: tilted red square (Noir), gradient tile with a glow (Neon) | theatre masks | different |
| Home under Online | three tiles: Game History (count), Player Stats, How to Play; trophy line "Best player: X · 83%"; "v… · Check for updates   What's new" | How to play link, two tiles (Stats / History), footer | different |
| What's new | a sheet: every release with its date and points, "Available" / "Installed" badges, Update + OK; opens by itself once after an update; the update card shows the first three points + See all | one version's points; a toast after an update | different |
| Room chat | next to the drawer tab | top bar icon | his #1 |
| Page change | a short fade / slide | Android's zoom, reads as a jump cut on his phone | his #4 |
| Game screens | one central card per step: a boxed tag ("Morning of Day 1"), an icon in a dashed box, the title, then the buttons inside the card; "Round 1 · 6/6 alive" at the bottom | free-floating column, bottom button bar | different |
| Neon | Readex, round 18–20 px cards, pink top-left and blue top-right glows, gradient primary, glassy cards | partly (one pink glow, radius 16) | his #6 |

## Items and acceptance criteria
- **S14-1 Room chat by the drawer (his #1).** The chat button is a side tab under the friends tab, at the drawer's height, in
  the lobby and during the game, online and Wi-Fi. Not in the top bar. AC: test finds `chatTab` in lobby and game, no `chat`
  in the app bar.
- **S14-2 Home icon stays in the room (his #2).** The top bar keeps the Home (minimize) icon. AC: test.
- **S14-3 Home as the old app (his #3).** Top row, logo, the three tiles (History shows the game count when known), the best
  player line (from the one board, signed in), version row with What's new. AC: widget test on every element; emulator shot.
- **S14-4 What's new as the old app (his #3).** The Release workflow keeps the last 10 releases on the server; What's new lists
  them (date, points, Available / Installed), Update + OK; opens by itself once after an update (no toast). The update card
  shows three points + See all. AC: server test, app test.
- **S14-5 Gentle transitions (his #4).** Every page fades and slides in a little (≈ 280 ms), both directions. AC: a page is half
  visible mid-transition (test).
- **S14-6 Game screens in the old central card.** Deal, night, morning, day, vote, verdict, end, offline and online. AC:
  screens render; whole-game tests pass at 360 × 640 × 1.3.
- **S14-7 Neon in every detail (his #6).** Two glows, radius 18 cards, glassy cards, gradient logo tile, Readex. AC: Neon shots
  next to the old ones.

## [BA] Proposals (his #5: the BA may improve on the old app)
- **P1** Game history tile also says how many games are waiting for approval (old: "· group"). *Deferred: needs a count the
  server doesn't give yet.*
- **P2** The best player line opens Player Stats (old: not tappable).
- **P3** Reduced motion respected: no slide when Android's "Remove animations" is on.

## Out of scope
New roles; the Play Store build.
