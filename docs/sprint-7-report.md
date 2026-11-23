# Sprint 7 Release Report: push notifications, Wi-Fi games into online history, the tie rule

2026-11-23. Built against `docs/sprint-7-prd.md`, signed off with the recommended answers:
- push and the approval process together;
- approved Wi-Fi games in History → Wi-Fi with a mark;
- a tie keeps the one-time skip;
- the starting limits;
- no push for chat.

Run as the three personas. Committed together with Sprint 8.

## [Developer] What changed, per AC
- **S7-3 tie rule (engines):**
  - `rules.tieSkip` is set when roles are dealt. A tied Mafia vote kills nobody and logs `{ k: 'none' }`; no random draw, and the skip isn't spent.
  - Records without the key (made before this sprint) replay with the old random pick (`recordRules` in both engines). That covers online history, Wi-Fi history and a Wi-Fi room resumed across the update.
  - The protocol accepts `tieSkip: true` only, so a phone can't switch it off.
  - The 60 shared test games were regenerated. The old ones are kept as `fixtures/records-before-tie.json`, and both engines must still replay them.
- **S7-1 push (server):**
  - `PUT/DELETE /v1/me/push` store the token per session. It's dropped by cascade on sign-out, device removal and account deletion; a token that moves to another account on the same phone moves with it.
  - The hub now reports whether the app is open. `notify()` sends a push only when it isn't.
  - FCM HTTP v1 runs through a Google service account (`FCM_SERVICE_ACCOUNT` secret, a no-op without it).
  - Texts in EN/AR (an RLM keeps Arabic lines right-to-left); channels `invites` / `friends` / `approvals`; a `tag` per sender and kind, so a newer push replaces an older one. FCM's "unregistered" deletes the token.
- **S7-1 push (app):**
  - `firebase_messaging`. The Google services Gradle plugin applies only when `google-services.json` exists, so without it the app builds with push off.
  - Android is asked once, after sign-in. The token is registered with the app language, and again when the language or the token changes.
  - A tapped notification opens the room (or says "This invite has expired" and opens the bell), Friends, or the bell. One tapped at launch waits for Home.
  - The three channels are created natively with EN/AR names. Settings → Notifications opens Android's per-channel switches.
- **S7-2 approval (server):** migration `0006_push_wifi.sql` (+ rollback) only adds tables and one column.
  - `settings.wifi_rules` holds the limits, with a version.
  - `wifi_requests` keeps the raw record, its hash, the phones' game key, the rules version and the status.
  - `wifi_seats` holds the answers.
  - `games.source`.
  
  The checks: replay, seats (names, distinct real accounts, sender among them), player count, at least N s per round, age (also from the future), daily limit (before storing), duplicates. Then confirmations from the bell (live or push). The last "yes" approves it inside one transaction, so two simultaneous confirmations make one game. Any "Not me" declines. Expiry runs on reads and on an hourly cron. Online history (`GET /v1/games`) stays online-only.
- **S7-2 approval (app):**
  - The Wi-Fi room tells every phone each seat's account and who hosted.
  - The host's end screen and History → Wi-Fi show "Add to online history", the guest line, or the status: Waiting for n of m / In online history / Not added + reason.
  - History merges the server's view (others' answers) and shows games approved on another phone of mine.
- **S7-4:**
  - History is open signed out (the Wi-Fi games alone, plus "Sign in to see your online games here too").
  - The bell has Accept on friend requests and Confirm / Not me on Wi-Fi requests.
  - The screens tool renders the new screens.
- **CI:**
  - the app job writes `google-services.json` from the `GOOGLE_SERVICES_JSON` secret if set;
  - deploy puts `FCM_SERVICE_ACCOUNT` on the Worker;
  - the emulator job's local D1 allows short games for the scripted approval test.

## [QA] Results: green
- **Engines:** TypeScript 35/35, including:
  - the tie rule;
  - the skip kept on a skip/target tie;
  - old records replaying with their random tie-breaks.
  
  Dart: all groups pass, byte-identical with the regenerated fixtures, and the old records replay.
- **Server:** 55/55 (46 earlier + 9 new):
  - **push:**
    - closed app vs open app;
    - Arabic text;
    - channels and tags;
    - tokens gone on sign-out, device removal, account deletion and "unregistered";
    - a token moving between accounts;
    - every kind has both languages.
  - **approval, adversarial:**
    - an edited record;
    - an unfinished game;
    - a wrong name;
    - a duplicated account;
    - an unknown account;
    - a sender who didn't play;
    - too short;
    - too old;
    - from the future;
    - a duplicate;
    - a guest seat and too few seats (400, not kept);
    - over the daily limit (429);
    - the settings row changed (new version recorded);
    - "Not me";
    - an answer after the decision;
    - an outsider answering;
    - expiry (on read and by cron);
    - two final confirmations racing (one approval, one game, one push).
- **App:** analyzer clean. **80/80 widget tests:** 67 earlier (one updated: History signed out has no tabs now) plus 13 new:
  - push: registration, language, refresh, asked once, nothing signed out, taps;
  - the request: payload, progress, guest line, non-host, rejection reason, the daily limit in Arabic, the server's view, a game approved elsewhere;
  - the bell: Confirm, Not me (RTL), result, Accept;
  - Settings.
- **Android:** the debug APK builds with the Firebase plugins and no config file (push off).
- **New emulator test** (`integration_test/approval_test.dart`, CI only):
  - a signed-in host plays a whole Wi-Fi game with three signed-in scripted phones;
  - the host taps "Add to online history" on the end screen;
  - the three confirm, and the host gets the result live in the bell;
  - the game is approved and kept out of online history.
  
  **It runs on the next push.** I couldn't run an emulator here.

## [QA] → [Developer]: what QA found, and the fixes
| # | Found by | Finding | Fix |
| --- | --- | --- | --- |
| 1 | UX pass (screens tool, 360×640) | **Settings overflowed** by 19 px once the Notifications row was added | The sheet scrolls |
| 2 | UX pass (Arabic bell) | The request's date came in Arabic-Indic digits (٢٣ نوفمبر ٢٠٢٦) next to Western ones (4 لاعبين), and the parenthesis beside "4" broke the right-to-left line | Day and year in Western digits like the rest of the app; the details follow a colon, no parentheses |
| 3 | Review | A notification with `click_action` needs an intent filter, or the tap does nothing | Removed; the plugin's default tap handling opens the app |
| 4 | Server tests | My own expectations used the display name where the test accounts have the email's name | Tests fixed; the behavior was right |
| 5 | Review | **A host can't be proven.** The record doesn't say who hosted, so any signed-in player of the game may send the request (the app shows the button only to the host). | Accepted. The other players' confirmations are the real guard, and duplicates are refused. Noted for the BA. |

## [BA] Acceptance review
| AC | Verdict | Evidence |
| --- | --- | --- |
| S7-1 AC1 register; prompt once after sign-in | ✅ | Widget test: asked once, ever; token + language sent; nothing signed out. Tokens die with the session (server test). |
| S7-1 AC2 push only when the app is closed | ✅ | Server tests: closed app → push; open hub socket → live note, no push. The app closes its hub socket when it goes to the background, so a backgrounded app gets pushes too. |
| S7-1 AC3 a tap opens the right place | ✅ | Test: expired invite → "This invite has expired" + bell; friend request → Friends; a tap that launched the app waits for Home |
| S7-1 AC4 channels + Settings row | ✅ (compiled) | Three channels created natively (EN/AR names); the row opens Android's settings. **Seeing the channels needs your phone.** |
| S7-1 AC5 language, one per sender and kind | ✅ | Arabic text test; `tag` = kind + sender (the request id for Wi-Fi) |
| S7-1 AC6 secret-based, harmless without it | ✅ | No key → nothing sent. No `google-services.json` → the APK builds with push off. |
| S7-2 AC1 who may ask; the guest line | ✅ (see QA #5) | Screenshot History → Wi-Fi: the button, "Waiting for 2 of 4", the guest line |
| S7-2 AC2 kept raw and versioned | ✅ | `wifi_requests.record` as sent, `rules_version`, rejected requests kept with their reason |
| S7-2 AC3 the automatic checks | ✅ | Every check has its own adversarial server test; the host sees the reason ("Not added: the game was too short to be real") |
| S7-2 AC4 each player confirms | ✅ | Bell screenshot (EN/AR): who asks, date, players, winner, my role, Confirm / Not me; push to closed apps; declined / expired / approved reach the host |
| S7-2 AC5 kept apart, synced | ✅ | Approved games show in History → Wi-Fi ("In online history"), also on another phone (from the server's copy); online history unchanged |
| S7-2 AC6 changeable later | ✅ | Limits in `settings.wifi_rules` (v1); migration only adds; a changed row is the version later requests record (test) |
| S7-2 AC7 the host sees the status | ✅ | Waiting n of m (from the server, so others' answers show), approved, declined, expired, rejected + reason |
| S7-3 AC1–AC2 a tie kills nobody, keeps the skip | ✅ | Engine tests (TS + Dart) |
| S7-3 AC3 the day vote | ✅ | Unchanged (already "nobody is out") |
| S7-3 AC4 old games replay | ✅ | 60 pre-sprint records with random tie-breaks replay in both engines; a resumed Wi-Fi room uses the same rule |
| S7-3 AC5 dead Detective kept; QUIRKS updated | ✅ | `QUIRKS.md`: fixed #2 (ties), "kept, decided" #1 |
| S7-4 AC1 History signed out | ✅ | Screenshot `*_54_history_signed_out`; test |
| S7-4 AC2 bell actions | ✅ | Tests: Accept, Confirm, Not me |
| S7-4 AC3 screens tool | ✅ | New: `51_bell_wifi`, `52_history_wifi`, `53_settings`, `54_history_signed_out` (EN/AR) |

**[BA] notes for the next audit:**
- "1 rounds" on history cards: the plural was already wrong before this sprint. Polish item.
- The host can't be proven (QA #5). Acceptable while every player must confirm. A future rule could require the request to come from the seat that dealt the game, if the room ever signs its records.
- The emulator approval test is new and unproven until CI runs it.

## Before real pushes work (your steps)
1. Firebase: the Android app is registered. Add the SHA-1 `CA:44:FD:43:46:80:A8:17:63:58:38:83:30:C8:1E:6F:0A:8C:FA:AB`, then re-download `google-services.json`.
2. GitHub secret **`GOOGLE_SERVICES_JSON`**: the file's whole contents.
3. Firebase → Project settings → Service accounts → **Generate new private key**. GitHub secret **`FCM_SERVICE_ACCOUNT`**: the file's whole contents. Delete the downloaded copy.

The next push's CI then builds the APK with push and gives the Worker its key.

## Caveats for your playtest
1. **A push with the app closed** (swiped away) and with the screen off: an invite, a friend request, a Wi-Fi confirmation. Tap each one: invite → the room, friend → Friends, approval → the bell.
2. **Android 13+:** the "Allow notifications" prompt appears once, right after signing in.
3. **Settings → Notifications** opens Android's page with three channels (Invites, Friends, Game approvals) in your phone's language. Switching one off stops only that kind.
4. **A real Wi-Fi game with all players signed in,** at least a few minutes long. "Add to online history" on the host's end screen; everyone confirms from their bell; the host's History → Wi-Fi shows "In online history".
5. **A Mafia tie at night:** nobody dies, and the one-time skip is still offered the next night.
