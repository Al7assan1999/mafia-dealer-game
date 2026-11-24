# Sprint 16 PRD: the Sprint 15 [BA] proposals

2026-11-24. His message after 0.4.11: "do the ba proposals and keep them ready if we find we need to rollback some of
them after the release". Signed off as listed in `docs/sprint-15-report.md` → "[BA] Proposals".

**Rollback rule:** each proposal is one change of its own (its own commit when committed), so any one of them can be
undone with a single `git revert` and a release, without touching the others.

## S16-1 (P1) The side tabs never cover the lobby's controls
The friends and chat tabs (36 dp, draggable up and down) sat over the ⋮ menus on player rows and could sit over the
role steppers.
- AC: in a lobby, every player's ⋮ menu and the Mafia + stepper end before the tab's edge, at any height. Test.

## S16-2 (P2) Wi-Fi: the old "Your name" card
- AC: the name is in a card titled "Your name". Signed out: "Tip: sign in and your name fills in by itself." under it.
  Signed in: the account's name is filled in and there is no tip. Tests (guest, signed in).

## S16-3 (P3) How to Play: the game options
The old guide had "Options in this app". Writing the options out again would repeat the setup screen and drift from it.
- AC: How to Play shows the setup's own rules card, read only, with Classic; a tap lists every option with its
  explanation; nothing can be changed from the guide. Test.

## S16-4 (P4) Done after signing in or choosing a @username
- AC: straight after sign-in (or the @username screen) the profile has a Done at the bottom that goes back to where
  sign-in started. The profile opened from Home has no Done. Test.

## S16-5 (P5) Readable role colours on the paper recap
Noir's role colours are made for a dark page: on the recap's paper they read at 1.9-2.9:1 (the Doctor's green 1.9).
- AC: in Noir, every role's colour on the paper and on the player-of-the-game box is 4.5:1 or more. Neon unchanged.
  Test (computes the contrast).

## Out of scope
Anything else; the device-list cause on his phone (waits for what the screen now shows).
