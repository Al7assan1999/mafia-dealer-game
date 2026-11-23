# Sprint 6 Release Report: Wi-Fi / Hotspot play

2026-11-23. Built against `docs/sprint-6-prd.md` (signed off with the recommended answers: Wi-Fi play now and the
approval process in Sprint 7; our own keep-alive plugin; no host takeover yet; 🖕 replaced). Run as the three personas.
**Not committed yet.** On the next push CI runs the new emulator Wi-Fi test.

## [QA] Results: green
- **App:** analyzer clean. **67/67 widget tests:** 53 earlier, plus 10 for the Wi-Fi room's rules and the real
  server on a socket, plus 4 Wi-Fi UI tests.
- **Server:** 46/46, unchanged. **Engines:** 34 TypeScript + 5 Dart, unchanged.
- **Android build:** the APK builds. The Kotlin keep-alive service compiles and the manifest declares it
  (`connectedDevice` type, with its permissions).
- **New emulator test** (`integration_test/wifi_test.dart`, CI only):
  - the app hosts a real Wi-Fi room on the emulator: its server on port 8765, the keep-alive service running;
  - three scripted phones join over sockets and play;
  - mid-night the host's room is stopped and resumed from its snapshot;
  - everyone reconnects into the same seats, and the game is played to the end and kept in History → Wi-Fi.

## [QA] → [Developer]: what QA found, and the fixes
| # | Found by | Finding | Fix |
| --- | --- | --- | --- |
| 1 | UI test | **Joining an address that answers nothing** repeated the scan's "No rooms found." (two identical lines) | A specific message: "Nothing answered at 127.0.0.1. Check the address on the host's screen." |
| 2 | UX pass | **The Wi-Fi screen's title read "Wi Fi / Hotspot":** the heading font lacks the non-breaking hyphen | A plain hyphen in the heading |
| 3 | UX pass | **"Players join at …" showed before anyone hosted,** where it means nothing | Moved under the room code in the host's lobby |
| 4 | Room tests | Three of my own test scripts were wrong (an endless all-"nobody" vote, kicking the last Mafia, a rate limit tested with 8 instead of 9 messages) | Tests fixed; the room's rules were right |

## [BA] Acceptance review
| AC | Verdict | Evidence |
| --- | --- | --- |
| S6-1 AC1 the Wi-Fi / Hotspot button | ✅ | Home screenshot: Offline, Wi-Fi / Hotspot, Online |
| S6-1 AC2 same messages as online | ✅ | The online room screen runs unchanged on the Wi-Fi room (UI test: a whole hosted game) |
| S6-1 AC3 the room's rules in Dart | ✅ | 10 tests ported from the server: lobby, whole game + record, host hand-over, kick, silent phone + Continue, catch-up / missed, repeats / stale, late joiners, chat rules |
| S6-1 AC4 no account needed | ✅ | A name is enough. Signed-in players send their account id and handle along, recorded for Sprint 7. |
| S6-1 AC5 the host narrates | ✅ | Test: guests start with the narrator off; one tap turns it on for that room only, and the online setting is untouched |
| S6-2 AC1 rooms found | ✅ | Screenshot: host name, code, players, waiting / playing. The scan covers this phone's private networks. |
| S6-2 AC2 manual address | ✅ | The address field, and the host's lobby shows its own address |
| S6-2 AC3 clear messages | ✅ | "Not on a Wi-Fi network", "No rooms found" with tips, "Nothing answered at …"; refusals (full, started, kicked) come from the room |
| S6-3 AC1 keep-alive | ✅ (compiled) | Foreground service (`connectedDevice`, notification), partial wake lock, Wi-Fi lock. **Screen-off behavior can only be proven on your phone.** |
| S6-3 AC2 resume hosting | ✅ | "Resume hosting room …" on Home. The snapshot carries the room, game (as its record), chat and rev. Room test + emulator test. |
| S6-3 AC3 players find the host again | ✅ | They retry the last address; every 3 failures they rescan for the room code and follow it to a new address |
| S6-3 AC4 no host takeover | ✅ (as agreed) | If the host phone is gone for good, that game ends |
| S6-4 AC1 every phone keeps the game | ✅ | The room sends its record at the end; each phone stores it (UI test, emulator test) |
| S6-4 AC2 Online / Wi-Fi tabs | ✅ | Test: the Wi-Fi tab lists the game; the detail page is rebuilt from the record |
| S6-4 AC3 on the phone until Sprint 7 | ✅ | Up to 100 games, newest first |
| S6-5 AC1 one "How to play" | ✅ | The footer link appears only after the first-launch offer is gone |
| S6-5 AC2 no preselected reason | ✅ | Test: "Send report" stays disabled until a reason is chosen |
| S6-5 AC3 🖕 replaced | ✅ | 🤨 in the same slot, so stored reactions keep their place |

**[BA] notes for the next audit:**
- **Two red buttons on Home** ("Offline game" and "Back to the Wi-Fi room") compete. Acceptable for a resume action;
  revisit in Play polish.
- **Block and report are hidden in Wi-Fi rooms** (guests may have no account). Moderation applies to online play.
- **Joining a room that's already playing** is offered in the list, then refused unless you hold a seat. Fine, but the
  list could grey such rooms out.

## Caveats for your playtest (the part no emulator proves)
1. **Real phones** on your phone's hotspot, on a home router, and on a third phone's hotspot: host, join from the
   list, join by address.
2. **The host's screen off for a few minutes** mid-game: the notification "Hosting a Mafia Dealer room" should show,
   and the game keeps going. On Android 13+, allow notifications when asked, or the notification stays hidden.
3. **Swipe the host app away mid-game,** reopen it, and tap "Resume hosting": the other phones should come back by
   themselves.
4. **A player walking out of Wi-Fi range and back.**
