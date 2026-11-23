# Sprint 10 Release Report: the intro, and the playtest fixes N1–N8

2026-11-23. Built against `docs/sprint-10-prd.md` (signed off). Committed as a835b23 and released as **v0.3.0**
(build 100002). This report adds the emulator QA session and the BA acceptance review, which ran after the release
together with Sprint 11 (`docs/sprint-11-report.md`).

## [QA] The failed CI emulator job after v0.3.0
- **The guess was wrong.** The integration tests never call `firstLaunch()`, so the intro can't play in them.
- **The real cause, from the CI log:**
  - in `integration_test/online_test.dart` a scripted friend sends a friend request;
  - since N5 that pops the in-app banner at the top;
  - the test then closed the Invite sheet with a tap at y = 60, which landed on the banner;
  - so the sheet stayed open over "Shuffle & Deal", and the Deal tap hit the sheet.
- **Fix:** the test taps the dimmed area lower down (y = 200).
- **What it means for players:** nothing is wrong in the app. The banner sits above sheets on purpose: an invite
  shouldn't hide behind one.
- **Not proven yet:** the emulator job runs only on GitHub, so it goes green once this is pushed.

## [QA] Results
- **Server:** 70/70 (69 + 1 for R4). Typecheck clean.
- **App:** analyzer clean.
  - **128 widget tests pass**: 113 before, 8 in `sprint10_fixes_test.dart`, 7 in `sprint11_test.dart`.
  - One earlier test was updated for R1: the room chat button moved from the red bar to under the friends tab.

### Emulator session (AVD `qa34`, Pixel 6, Android 14)
**Setup:**
- a **profile build** (compiled like the release build; the debug build can't judge smoothness) against the local
  worker;
- the profile build gets the debug build's local-network rule, so it can reach `10.0.2.2`. Profile builds are never
  shipped.

| Check | Result |
| --- | --- |
| Fresh install: the intro plays first, with no Skip | ✓ dawn, the Doctor scene and the title all render |
| Captions type out; the progress bar fills | ✓ |
| "Tap to start" goes to Home with How to play highlighted (P4) | ✓ |
| The "hard edge" under the title's mark seen in the test screenshots | **Not on the device.** A zoomed screenshot shows a clean mark, so the edge came from the test renderer. |
| Smoothness | No stutter in the sampled frames of the profile build. An emulator on a PC isn't a phone, though: **your phone with the new release APK decides** (Sprint 11, R9). |
| Sound | The emulator has no speaker I can hear. Whether the scene sounds play and fade **needs your ears**. |
| The live banner (N5): a friend request while the app is open | ✓ "Dareer… wants to be your friend · Accept" at the top |
| A friend's row opens their profile (N2) | ✓ (now a full page, R3) |
| Kick, then invite back (N5b) | ✓ The removed player's own rejoin by code was refused (`kicked`); after the host's invite the same player walked back in. |
| Buzz limit 3 | ✓ the fourth buzz shows them "(muted)" |
| A real test notification (P5) | **Not proven locally.** The phone registered, but the local worker has no Firebase key, so nothing went out. It now says so (Sprint 11, R6). A real push needs the deployed server. |

**Found in the session and fixed:**
- The kick dialog still said *"they can't come back"*, which stopped being true with N5. It now reads: *"They can't
  come back in with the code; inviting them again lets them back into the lobby."*
- **"1 players"** on the room bar and the lobby summary is now a proper plural, in English and in Arabic.

## [BA] Acceptance review
| AC | Verdict |
| --- | --- |
| S10-1 AC1–AC4 (scenes, sounds, captions, themes / languages) | Accepted on screens. **Sound needs your ears.** |
| S10-1 AC5 reduced motion | Accepted on widget tests only (not tried on the emulator) |
| S10-1 AC6 smoothness | **Open:** for your phone with the release APK |
| S10-2 AC1–AC5 (when it plays) | Accepted (emulator: first launch; tests: the rest) |
| S10-3 AC1 N2 profile | Accepted; extended by R3 |
| S10-3 AC2 N3 swipe | Accepted; R5 made the message move like Telegram |
| S10-3 AC3 N4 / P5 test notification | **Sent back as R6:** with the app open, Android hid the push, so the button looked dead |
| S10-3 AC4 N5a banner | Accepted (emulator) |
| S10-3 AC5 N5b invite after a kick | Accepted (emulator) |
| S10-3 AC6 N6 Invite, not Ask to join | Accepted (tests) |
| S10-3 AC7 N7 chat while minimized | **Changed by R1:** it moved under the friends tab, at your request |
| S10-3 AC8 N8 bell | Accepted (tests) |
| S10-3 AC9 N1 readable messages | Accepted (emulator: the toasts read light on dark) |

## For your playtest
- The intro's **sound and smoothness** on your phone, with the release APK.
- A real **test notification** with the app open (it should say "Arrived on this phone ✓") and with the app closed
  (it should land in the notification bar). This needs the deployed server.
