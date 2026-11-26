# Sprint 19 report: 1.2.0, the suggestions box

PRD: `docs/sprint-19-prd.md` (his answers at the end). Rulings: `docs/decisions.md` (2026-11-26, Sprint 19).

## What a player gets
- **Settings → Suggestions & problems** (اقتراحات ومشاكل). Choose Suggestion or Problem, write 10–1000 characters, and
  optionally add **one** screenshot from the gallery (remove or replace it).
  - The app version, the language and the Android version go with it, and the form says so.
  - Signed out, the item says "Sign in to send" and opens sign-in.
- **Limits:** 3 a day, at most 5 waiting, and 300 in the whole box. The form says so **before** you type.
  - The screenshot is shrunk on the phone (Android first, then ≤ 1280 px, a JPEG of ≤ 300 KB).
  - The server accepts only a real JPEG.
- **My messages:** what you sent and how far it got (Sent / Read / Done ✓).
- **When it's done**, the player gets a push ("We read your suggestion. Thank you!" / "We've looked at the problem you
  reported. Thank you!"), and tapping it opens My messages.
- **"Report a problem with this game"**: on an online game's end screen (seated players) and on a game you played in
  History; the game goes with it.
- **For you:** Profile → **Suggestions**, with the unread count.
  - Newest first, with a filter: All / Suggestions / Problems.
  - Each one shows who sent it (tap for their profile), when, the text, the phone details, the screenshot (tap for full
    size) and the game (tap to open it).
  - Opening one marks it read. **Mark done** tells the player. **Delete** one, or **Empty the box** after a confirm.
  - Empty removes only what you saw: anything that came in meanwhile stays.

## Test results (final run)
| Suite | Result |
|---|---|
| Engine, TypeScript / Dart | 72 / 13 passed (unchanged) |
| Server (`server`, vitest) | 95 passed (new: `test/sprint19.test.ts`, 12 tests) |
| App widget tests (`app`) | 231 passed (new: `test/s19_feedback_test.dart`, 13 tests) |
| `flutter analyze` / `tsc` | clean |
| Emulator integration tests (local Worker, real app) | 7 passed |

**Tried for real:** the local Worker with migration 0012 applied as CI applies it.
- A 133 KB picture was sent.
- A 450 KB picture was refused.
- The 4th send in a day got "slow_down", and My messages then said "day".
- A non-admin got 403 on the box.

**Only against fakes:** the admin's screens, the gallery picker and the push. The server side of all three is tested on
the Worker runtime (miniflare).

## [BA] acceptance review (Ben)
| AC | Verdict | Evidence |
|---|---|---|
| S19-1 AC1–2 form, send, keep text on failure | Accepted | s19 "S19-1: a problem with one screenshot", "box filled up while typing" |
| S19-1 AC3 phone details | Accepted after Q4 (the real Android version) | the Android side answers `android`; s19 checks the fields |
| S19-1 AC4 signed-in only | Accepted | sprint19 401; s19 "S19-1 AC4" |
| S19-1 AC5 EN/AR, small phone, large text | Accepted for the form | s19 "AC5" at 320×568 and 360×640 ×1.3 |
| S19-2 AC1 3/day, 5 waiting, said before typing | Accepted | sprint19 "3 a day", "5 waiting"; real Worker |
| S19-2 AC2 ≤ 300 KB JPEG | Accepted after Q1, Q5, Q6 | sprint19 "299 KB goes through…"; s19 shrink test |
| S19-2 AC3 300 in the box | Accepted | sprint19 "the whole box holds 300" |
| S19-2 AC4 banned | Accepted | sprint19 "a banned account cannot send" |
| S19-2 AC5 text only | Accepted | shown with Text / SelectableText |
| S19-3 AC1–5 the box | Accepted after Q2, Q8 | sprint19 "only the admin…", "newest first…"; s19 admin tests |
| S19-4 1.2.0, 0012 + rollback | Accepted | pubspec 1.2.0+5; migration and rollback |
| P1 / P2 / P3 | Accepted (P1 as a push, see below) | sprint19 push test; s19 P2 entry tests; My messages |

**Ben's own finding:** P1 as written ("a bell note") would have reached your 1.1.x phones too. They show an unknown note
as "wants to join your room". So P1 is a push plus the Done status in My messages, and old phones just open the app.

## QA ↔ Dev (Quin: 16 findings, 0 blocks, 0 reached you)
| # | Finding | Dev's answer |
|---|---|---|
| Q1 | The server's 300 KB request cap refused screenshots over ~229 KB | **Fixed**: the box gets 420 KB; test with 299 KB |
| Q2 | Turning 300 KB into and out of base64 cost 20–35 ms of CPU (free plan: 10 ms) | **Fixed**: a plain loop (~1 ms); the screenshot is served as raw bytes |
| Q3 | Tapping the "done" push opened the bell on top | **Fixed** |
| Q4 | "Android version" was the kernel's string | **Fixed**: Android's own version, through the app's Android side |
| Q5 | A 50 MP photo would freeze the phone | **Fixed**: Android shrinks it first; the JPEG pass runs off the UI thread |
| Q6 | A fake WebP was stored; a crafted PNG could crash your box | **Fixed**: JPEG only, checked by its bytes; the box decodes at screen size |
| Q7 | "Report a problem" showed for spectators and in games you didn't play, then failed with a wrong message | **Fixed**; test |
| Q8 | Mark done / Delete / Empty said success even when offline | **Fixed**: they say when it failed |
| Q9 | Phone and server counted characters differently (emoji, vowelled Arabic) | **Fixed**: the phone counts as the server does |
| Q10 | Broken base64 gave a server error | **Fixed**: 400; test |
| Q11 | Push wording "is fixed"; muted with Wi-Fi approvals; nothing while the app is open | Wording now "we've looked at it"; moved to the friends channel; in-app: My messages |
| Q12 | Races can overshoot "5 waiting" or 300 by a few; Empty deleted unseen ones | Empty fixed (only what you saw); the small overshoot is accepted |
| Q13 | A slow upload can time out after the server stored it (a duplicate) | Note |
| Q14 | A wide screenshot preview overflowed a small phone | **Fixed** (a fixed square) |
| Q15 | Two quick taps sent twice | **Fixed** |
| Q16 | Test gaps | Added: P2 entry points, admin badge, banned, 299 KB, fake picture, broken base64, too long |

## Challenge log
- **Ben → his own PRD:** P1 as a bell note would reach old phones as "wants to join your room". P1 became a push plus My
  messages. David agreed.
- **Quin → David:** Q1 (a screenshot limit the app promised but the server refused), Q2 (CPU). Fixed with tests.
- **Quin → David:** Q6 (crafted pictures against your box). Fixed (JPEG only, size-capped decode).
- **Quin → Ben:** Q12, the box cap counts read items too. Ben: yes, the box holds 300 until you empty it, as the PRD's
  "the whole box holds 300".

## [Danial · Release] go / no-go
- **Migration 0012:** adds one table (`feedback`), with no change to existing tables. The rollback
  (`server/rollbacks/0012_feedback.sql`) drops it. CI applies it before the Worker deploys.
- **Old phones:** 1.1.x phones keep playing (no game rule changed). They don't have the form, and a "done" push to one
  only opens its app.
- **Cost:**
  - one D1 row per message, ≤ 300 KB with its screenshot;
  - at most 300 rows (~90 MB worst case, against D1's free 5 GB);
  - ~1 ms of CPU per send;
  - one push per Done;
  - no Durable Object traffic.
- Version 1.2.0+5; release build 100021. Git email is the noreply address. No secrets in the diff.
- Release notes (players): "Suggestions & problems: send us an idea or report a problem, with a screenshot; See what
  you sent and when it's done; Report a problem with a game from its end screen or History".

## Only a human playtest can show
- The Android gallery for real: the Photo Picker, HEIC photos, photos only in Google Photos, portrait rotation, and how
  long a big photo takes to shrink.
- The "done" push with the app closed, in the background and open, and the Arabic text in the notification shade.
- A 220–300 KB screenshot sent and opened by you on the real Cloudflare Worker.
- The end screen with the extra "Report a problem" line on a small phone.
