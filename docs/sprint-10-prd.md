# Sprint 10 PRD: the intro, same as before

Status: **signed off 2026-11-23** (all notes answered).

His answers to the notes:
1. N1: his screenshot. "Profile saved" shows at the bottom as **dark text on a dark bar**, nearly invisible.
2. P2: ship the intro now, and take the voice **as it is from the old app**.
3. N5: inviting the kicked player again didn't let him in; it must.
4. N8: keep 30 days, with a cap I choose (**200 items per account**: the oldest answered ones go first).
5. P5: in.

His answers:
1. A faithful port.
2. Sounds rendered from the old recipes.
3. Off after the first launch, with a switch.
4. Keep the blood.
5. All four [BA] proposals, **including P2, the narrator voicing the captions** (see decision 2 below).

His instruction: "plan adding the intro same as previous" (the Sprint 9 note); `docs/old-app-parity.md` Sprint 10.

## [BA] Audit

### A. The new app opens straight onto Home
*Screenshot `en_03_home_guide_offer`:* the first launch shows Home with "New to Mafia? Learn it in a minute · How to
play". There's no welcome, no mood, nothing that says what kind of game this is. The old app opened with its intro;
your friends know it.

### B. The old intro, exactly (read from `../mafia-dealer`, v2.14–v2.16: `app/src/welcome.ts`, `audio/welcomeSfx.ts`, the CONTEXT notes)
Six scenes and a title, drawn in vector art (silhouettes, no pictures). The scenes advance on their own; a tap moves on:

| # | Scene | Caption (EN / AR) | Time | Sound (his picks on the sound board) |
| --- | --- | --- | --- | --- |
| 1 | Dawn: a town skyline, houses with lit windows, two people walking (one waves), the sun | "A quiet town. Everyone knows everyone." / «بلدة هادئة. الجميع يعرف الجميع.» | 3.6 s | 1A birdsong + a warm chord |
| 2 | Night: stars, the moon; sound rings over a house, the screen shakes, a flash, **"CRACK!"** («طَخ!») | "Then one night… something sounded wrong." | 4.0 s | 2A crickets + owl + a low bell, then the crack |
| 3 | Morning, red sky: a chalk outline, the crowd gathers; **blood** splashes across the top and runs down in streams with drops | "Someone is dead." / «أحدهم مات.» | 4.4 s | 3K1 a blade drawn from its sheath (a scrape, a loud SHING), then the hit |
| 4 | **The Doctor** rises, glowing, with a pulse ring and the Doctor badge | "It could happen to anyone. I'll keep you safe tonight." | 3.4 s | 4C a healing glow |
| 5 | **The Detective** in a hat, a magnifying-glass light | "I swear I'll find them." | 3.0 s | 5C a mystery theme (celesta over low strings) |
| 6 | **The Mafia**, hat, glowing red eyes, **"HA HA HA"** | "You… I'll get you all." | 3.8 s | 6A a horror drone + swell + our recorded laugh |
| — | The title: the logo, "Mafia Dealer", "Who can you trust?", "Tap to start" | | stays until a tap | — |

**The rules:**
- Captions type out letter by letter; a progress bar shows the six scenes; "Tap to move on".
- **The first launch plays it once with no Skip and Back disabled** (taps still move on); after that it counts as seen.
- Afterwards it plays at start only if **Settings → Show the intro at start** is on (off by default). **Watch the intro**
  is in Settings and at the top of How to play.
- A **mute button** on the intro, remembered. Its volume follows Settings → Sound effects.
- It doesn't play when the app opens into a room or from an invite.
- It follows the theme (Neon / Noir) and the language, and respects reduced motion.
- The sounds are synthesized in code (Web Audio); only the laugh is a recording.

### C. What changes in Flutter
- The drawings and motion are rebuilt with Flutter's own vector painting, from the old SVG shapes, so it looks the same.
- **Sounds:** Flutter has no Web Audio. The six scene sounds are **rendered once from the old recipes** (the old sound
  board `design/sound-kit.js`, run in a headless browser, read only) into audio files, exactly as Sprint 2 rendered the
  game's sound effects. The laugh is the clip the app already has.

## Scope

### S10-1 The intro
- AC1: Six scenes and the title as in the table above:
  - same pictures, captions (EN/AR), order and timings;
  - "CRACK!" with the shake and flash;
  - the blood in scene 3;
  - the role badges;
  - "HA HA HA".
- AC2: Each scene's sound as picked: the previous one fades as the next begins. Volume = Settings → Sound effects; the
  mute button is remembered.
- AC3: Captions type out; the progress bar fills per scene; a tap moves to the next scene; the title stays until a tap
  and then opens Home.
- AC4: Both themes (Noir / Neon colours, as the old app) and both languages (Arabic captions right-to-left).
- AC5: **Reduced motion** (Android's "Remove animations"): scenes fade without movement, no shake or flash, and the blood
  shows as still drops.
- AC6: Smooth on a mid-range phone: no stutter in the blood or the shake (measured on the emulator; your phone decides).

### S10-2 When it plays
- AC1: **First launch:** plays once with no Skip; Back does nothing; a tap moves on. Then Home with the "How to play"
  offer.
- AC2: **Later:** only when Settings → **Show the intro at start** is on (off by default), with **Skip**.
- AC3: **Watch the intro** in Settings and at the top of How to play (with Skip).
- AC4: Never when the app opens into a room (resumed or minimized), from a notification, or from an invite. Those go
  straight where they lead.
- AC5: Phones that already have the app (updating from 0.2.0) count as having seen it. It doesn't suddenly play for
  them; they can watch it from Settings.

## [BA] proposals (all accepted; P5 added from his notes, see decision 5)
- **P1. The intro sets the theme's tone:** in Neon the glows and gradients of Neon; in Noir an old-film grain over the
  scenes (the old Noir backdrop had a faint scan-line texture). Small, and it makes Noir feel like Noir.
- **P2. The narrator in the intro: as in the old app (his answer).** The old intro has **no spoken captions**: its only
  voice is the narrator's recorded **laugh** in the Mafia scene (`v_laugh`), which the new app already has. So the intro
  ships with exactly that, and nothing new is recorded. *(The old voices were made with Chatterbox for the game's
  narration; the intro itself never used it.)*
- **P3. A haptic beat** on "CRACK!" and on each "HA" (phones without sound on still feel it).
- **P4. A "first night" hand-off:** the title's "Tap to start" leads to the "How to play" offer highlighted, so a new
  player goes from the mood straight to the rules.

## His playtest notes (2026-11-23): discussion, cause, who does what

Each note was traced in the code by [Developer] before this draft.

| # | His note | What we found | Roles |
| --- | --- | --- | --- |
| N1 | "The save profile alert still not valid" | **His screenshot:** the message bar has our dark card colour but keeps Flutter's default **dark text**, so "Profile saved" is nearly invisible. It hits **every** such message in the app (saved, errors, Invited, Asked...). | [Dev] one theme rule for all of them; [QA] screenshots in Noir and Neon, EN and AR |
| N2 | "The friends list icon doesn't go to the profile" | Only the name opened anything, and it opened **stats**: a friend with no verified games gets an empty "not found" page. The avatar does nothing. | [Dev] the whole row opens the friend's **profile**; [QA] tests |
| N3 | Swipe to reply needs the bubble itself, not the whole row like Telegram | The swipe is attached to the bubble only. The old app (v2.19.1) took it **anywhere on the message's line, either direction**. | [Dev] the whole row; [QA] gesture tests in EN/AR |
| N4 | A friend request to an **offline** friend: no alert | **Two causes.** (1) A server bug: it pushes only when it believes the friend's app is closed, and it takes **any open connection** as proof the app is open, but a phone swiped away or out of signal leaves its connection "open" for a while. Online rooms already ignore connections silent for 30 s; the friends connection didn't. (2) A friend on a build before 0.2.0 (or who never allowed notifications) has no push registration at all. | [Dev] ignore connections silent for 30 s, as rooms do; [BA] P5 a "Send me a test notification" button; [QA] a real push on the emulator |
| N5 | Dareer **online**: no alert, only the bell (the old app showed a banner); and "it says I kicked him, so he'll never join unless I change the room" | (a) With the app open the server sends no push, only the live bell, so nothing pops up. The old app showed an **in-app banner** (Join / Let in). (b) A kick is **permanent** for that room. The old app changed that in v2.8: **kicked players may rejoin.** | [Dev] the in-app banner; the kick no longer locks the room (decision 3); [QA] tests |
| N6 | "Why does the host see Ask to join? It should only be Invite" | A real bug: right after creating a room, the app hasn't yet learned it's in that room, so the drawer thinks you're in no room and offers **Ask to join** for friends in a lobby, even your own. | [Dev] the drawer and Friends use the room on screen (or the minimized one) directly; a friend in my room is always "In your room"; [QA] tests |
| N7 | "Why can't I open the chat directly when minimized?" | The room bar only goes back to the room. The old app kept the **chat button** while minimized (v2.12). | [Dev] a chat button on the room bar with the unread count; [QA] tests |
| N8 | Notifications should have **mark as read** (and mark read on their own) and **shouldn't disappear** | The bell marks everything read when opened, has no per-item read state you control, and items vanish: invites after 30 min, answered items after 24 h, friend notes after 7 days. | [Dev] per-item read, "Mark all as read", read when seen; **items stay for 30 days** (decision 4) until you Clear them; [QA] tests |

### S10-3 Fixes from his playtest
- AC1 (N2): Tapping **a friend's row or avatar** (Friends, the drawer, the lobby) opens **their profile**:
  - avatar, @handle, favourite role, status;
  - Invite / Ask to join / Remove;
  - their stats when they have verified games, otherwise "No games yet".
- AC2 (N3): **Swipe anywhere on a message's line** replies, in either direction (both languages), like the old v2.19.1.
- AC3 (N4):
  - the server treats a friend as away when their app's connection has been **silent for 30 s** (as online rooms do), so the push goes out;
  - **P5:** Settings → Notifications gains "Send me a test notification", which shows whether this phone is registered and receiving.
- AC4 (N5a): **In-app banner** while the app is open: an invite ("Dareer invites you · Join"), a join request ("Let in"), "X let you in", or a friend request ("Accept"). It slides from the top, disappears after a few seconds, and stays in the bell.
- AC5 (N5b): **The host's invite lets a kicked player back in** (his answer): inviting them clears the kick for that
  room, and they join normally. A kicked player who wasn't invited back still can't walk in.
- AC6 (N6):
  - the drawer and Friends decide Invite / In your room / Ask to join from the room actually on screen (or minimized);
  - in my own room I see **Invite** or **In your room**, never Ask to join;
  - Ask to join only when I'm in no room.
- AC7 (N7): The room bar gets a **chat button** with the unread count that opens the room chat directly, without leaving Home.
- AC8 (N8): The bell:
  - **unread items marked** (bold + dot);
  - tapping an item marks it read;
  - **"Mark all as read"**;
  - opening the bell marks what you saw as read;
  - items stay **30 days, at most 200 per account** (oldest answered first), an expired invite reads "Expired" and an answered one shows its result;
  - **Clear** is the only thing that removes them.
- AC9 (N1): every in-app message (saved, errors, Invited, Asked, Roles are being dealt...) is **readable**: light text
  on the card colour with a border, floating above the bottom edge, in Noir and Neon. Successes read in the accent,
  errors in red.

## Not in Sprint 10
- Groups (your prompt).
- The old history import (waits for your friends' sign-ups and names).
- Google Play (last).

## How [QA] will verify
- **Widget tests:**
  - the scene order and timings with a fake clock;
  - tap advances; the title waits;
  - first launch: no Skip, Back ignored, seen afterwards;
  - later: off by default, on → plays with Skip;
  - Watch from Settings and How to play;
  - not when opening into a room or from a notification;
  - mute remembered;
  - reduced motion;
  - EN/AR;
  - updating users count as seen.
- **Screens:** each scene at its key moment, Noir and Neon, EN and AR.
- **Sounds:** each rendered file checked for length and level against the old board, and listened to in the emulator.
- **Emulator session:** watch it end to end on Android 14, with frame timing on the blood and the shake, and the
  sound on.
- **What only you can judge:** that it looks and sounds like the old one on your phone.

## Decisions
1. N1: the unreadable message bar. **Answered** (his screenshot).
2. P2: the intro's voice as in the old app (the laugh), nothing new recorded. **Answered.**
3. N5: the host's invite lets a kicked player back in. **Answered.**
4. N8: 30 days, at most 200 items. **Answered.**
5. P5: "Send me a test notification". **In.**
