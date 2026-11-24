# Sprint 15 Report: the QA journey, the rest of the old look

2026-11-24. Built against `docs/sprint-15-prd.md`. Part 1 (S15-1, S15-2, S15-4, S15-6 and the history search) shipped in
0.4.9; the sign-in fix shipped in 0.4.10. This report covers part 2: the full QA journey (S15-3), the Arabic and Neon
pass (S15-7), the remaining old-look screens (S15-5) and the fixes they brought. **Not committed, not released.**
Version in `pubspec.yaml`: 0.4.11.

Emulator shots of the journey: `docs/qa/journey15/` (j01-j47). Old-app reference: `docs/qa/old-look*/`.

## [QA] The journey
A profile build (compiled, not debug) on the Pixel emulator, against the local Worker, with three scripted players on
real sockets (`bots.mjs`, the same rules as `integration_test/online_test.dart`'s Bot).

| Step | Noir · English | Neon · Arabic |
| --- | --- | --- |
| First launch → Home | ✅ j01-j02 | ✅ j36 |
| Offline game: setup, deal, night, morning, day, vote, recap | ✅ j03-j09 (Doctor save shown) | ✅ j39-j41 (3 rounds, Mafia win) |
| Sign-in with an email code, new @username, profile | ✅ j11-j15 | – |
| Online: create, 4 players, deal, night, day, secret vote, recap | ✅ j17-j30 | – |
| Friend request in the bell, accept, Friends list | ✅ j22-j23 | ✅ j37, j42 |
| Room chat both ways (bot → app, app → room) | ✅ j24 | – |
| Room bar on Home, Back to room | ✅ j21 | ✅ j44 |
| Game History, game detail, Player Stats | ✅ j31-j33 | – |
| Settings, language and theme switch | ✅ j34 | ✅ j35 |
| Wi-Fi screen, Online screen, How to Play | ✅ j10, j17 | ✅ j38, j43, j45-j47 |

## [Developer] What changed
- **Devices in the profile (his report).** On his phone "Signed-in devices" was empty. It lists the device on the
  emulator, so the call failed on his phone. A 401 would have signed him out, which didn't happen, so it was a timeout
  or a server error, and the screen hid it (`catch (_) {}`). The section now shows the reason with **Try again**.
  The cause on his phone isn't known yet; the next time it fails, the reason will be on screen.
- **TalkBack couldn't reach the red room bar.** The page under it dropped it from the accessibility tree. The pages now
  get their own semantics container, and so does the bar: the first fix made the bar's node cover the whole screen
  (QA caught it on the emulator, `[0,0][1080,2337]`); now it is the bar only (`[0,0][1080,257]`).
- **The chat's Send button had no label** for TalkBack: it says "Send" (or "Save" while editing).
- **Arabic back buttons pointed the wrong way.** `chevron_left` and `arrow_forward` already flip themselves in a
  right-to-left layout; the code flipped them again. The back chevron now points right in Arabic, and "Back to room"'s
  arrow points left.
- **Friends search hint** fits: "Name or @username" (it was cut off in both languages).
- **Online: join with a code** in its own card as the old app, with a dim `000000` hint. The spaced-out "6-digit code"
  read badly. The unused string is removed.
- **Dates in Arabic** (recap card, What's new) use 0-9 like every other number in the app (they came as ٢٤ … ٢٠٢٦).
  Same pattern as the bell.
- **How to Play** gets the old guide's **Table rules** and **Suggested setup** (EN + AR). The setup numbers follow the
  engine's own suggestion (`recMafia`). Tips no longer repeats "out players stay quiet".

## [QA] How it was tested
| Check | Result |
| --- | --- |
| App tests | **174 / 174** (4 new: devices error and retry; room bar and Send labels; Arabic back icons; guide sections. Plus the Arabic date in the S15-4 recap test) |
| Server tests | **73 / 73** (no server change) |
| Analyzer | clean |
| Emulator | the journey above, Noir/English and Neon/Arabic, on a profile build |

Each new test was run against the old code first and failed there: the room bar (no label, then a node of 851 px), the
Arabic date (no "24 … 2026"), the devices (no reason shown).

### [QA] Break attempts
- **Username with an empty display name:** "Every player needs a name" under the field; Continue stays. This was the
  handoff's suspect (the 'kalimqa' case). Not a bug: the reason is shown.
- **Deal:** "Got it" stays off until the role has been held (tried in Arabic: it didn't move on without a peek).
- **Online:** a vote that put the app's player (the Mafia) out; Citizens win and the recap matches the roles.
- **Leave the room from the recap:** confirm dialog, then Home without the bar; the game is in History.
- **Devices offline:** the reason and Try again appear; back online, Try again lists the device (test).
- **Room bar with TalkBack's tree:** read with `uiautomator dump` on the emulator before and after each fix.

### [QA] Found during the sprint
| # | Finding | Where | Status |
| --- | --- | --- | --- |
| 1 | Device list silently empty | his phone | Fixed (reason shown); cause unknown |
| 2 | Room bar invisible to TalkBack | emulator | Fixed |
| 3 | Room bar node then covered the whole screen (from fix 2) | emulator | Fixed |
| 4 | Chat Send without a label | emulator | Fixed |
| 5 | Back chevron and "Back to room" arrow wrong in Arabic | emulator | Fixed |
| 6 | Friends search hint cut off (EN and AR) | emulator | Fixed |
| 7 | Online join: unclear "6-digit code" hint (old look) | old-look compare | Fixed |
| 8 | The new `000000` hint looked like a typed code in Neon (from fix 7) | emulator | Fixed |
| 9 | Arabic-Indic digits in dates | emulator | Fixed |
| 10 | How to Play missing the old table rules and suggested setup | old-look compare | Fixed |

10 findings; **1 reached him before QA caught it** (#1). Two (#3, #8) were Dev's own regressions this sprint, caught
by QA on the emulator before they left the machine.

### [QA] What was tried for real, and what only against fakes
- **For real:** email sign-in, the username screen, an online game with three players on real sockets, a friend
  request through the bell, the room chat both ways, the history and stats from the server. All against the **local**
  Worker, not the deployed one.
- **Only against fakes:** the devices error path (the emulator never fails that call).
- **Not tried:** push, Google sign-in, a Wi-Fi game between two devices, the deployed server, TalkBack itself (only
  its tree, read with `uiautomator`).

### [QA] What only a human playtest can show
- **Why the device list failed on his phone.** Next time the screen says why (or it works).
- **Presence with real phones.** A scripted player has no hub socket, so Friends showed "Dareer15 · Offline · In your
  room". A real phone in a room is online; worth a look on two phones.
- **TalkBack by ear:** the labels are in the tree; how it reads them aloud wasn't heard.
- **His phone's fonts and "Bold text"** against the new card and hints.

## [BA] Old-look comparison (S15-5)
| Screen | Old app | Verdict |
| --- | --- | --- |
| History | search, Winner and Record filters, count | ✅ matches (j31) |
| Player Stats | (old shot is empty) | ✅ new has more |
| Settings | account, look, sound, host | ✅ matches (j34) |
| Online | join in a card, `000000` | ✅ after fix #7 |
| How to Play | idea, roles, night, day, table rules, setup, options, tips | ✅ after fix #10; "Options in this app" → proposal |
| Wi-Fi | name card with a sign-in tip, Host / Join cards | ⚠️ new finds rooms by itself (clearer); name card → proposal |
| Friends, Profile | old shots are signed out only | – nothing to compare |
| Lobby, chat, bell | no old shots | – checked as a player instead |

## [BA] Acceptance review
| Item | Verdict |
| --- | --- |
| S15-3 full QA journey | ✅ emulator, both themes and languages (online and sign-in in English only) |
| S15-5 old look, the rest | ✅ History, Stats, Settings, Online, guide; ⚠️ Wi-Fi kept new (see proposals) |
| S15-7 Arabic and Neon pass | ✅ Home, Settings, Friends, Online, offline game to the recap, guide, room bar |
| His device list | ✅ shows the reason now; ❌ the cause on his phone is not known yet |

**Found by the BA alone:** the guide had lost the old table rules and suggested setup (#10). Neither Dev nor QA raised
it; it came from reading the old guide line by line.

## [BA] Proposals (his call)
1. **Side tabs over the ⋮ menus in the lobby.** With several players the chat tab sits on the right edge of the
   player rows. Move the tabs below the list, or inset the rows.
2. **Wi-Fi: the old "Your name" card** with "Tip: sign in and your name fills in".
3. **How to Play: "Options in this app"** (skip a kill, no repeat target, reveal on elimination…). Each option is
   already explained on the setup screen, so this would repeat it; a link from the guide to the setup could do.
4. **After choosing a @username** the app lands on My profile with only a back arrow. A "Done" (or straight to Home)
   would end sign-up clearly.
5. **The Doctor's green on the paper recap** is light; a darker green would read better.

## Challenge log
- **His report against QA:** the empty device list reached him first. Every test passed because no test let that call
  fail. *Change:* a list that loads from the server shows its error; the devices test fails the network on purpose.
- **QA against Dev:** the first room bar fix passed the widget test but the emulator showed a node the size of the
  screen. The test now checks the node's height too.
- **QA against Dev:** the `000000` hint (Dev's fix for the old look) looked like a filled-in code in Neon. Dimmed.
- **Dev against the handoff:** the username screen "not continuing" was suspected as a bug. The break attempt shows
  the reason on screen; closed as not a bug.
- **BA against Dev:** the new guide was shorter than the old one; two sections came back. Dev pushed back on
  "Options in this app" (it repeats the setup screen); BA agreed to make it a proposal.
- **QA against QA:** the scripted players showed "Offline" while in the room. That's the script (no hub socket), not
  the app; left to the two-phone playtest instead of being filed as a bug.

## Notes
- The local test server ran on port **8790**: port 8787 is held by old local `workerd` processes from earlier
  sessions that never answer. They can be closed in Task Manager (`workerd.exe`).

## Before release (his call)
Nothing to run on the database. Version 0.4.11, then commit → push → CI → release.
