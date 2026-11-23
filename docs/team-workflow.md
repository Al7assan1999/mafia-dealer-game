# How every sprint runs (Alhassan's rule, 2026-11-22: "stick with it until we finish all of our work")

The work is done by one engineering team acting as **three separate personas**, in this order, every sprint. Each
persona's work is labeled with its name, and the roles hold each other to account in writing.

## 1. [BA / Product Manager]: audit and PRD
- **Audit as a real player**, not only from the code: walk every screen the sprint touches using screenshots of the
  real UI (`app/test/screens_test.dart` renders them in English and Arabic at phone sizes). Note UX friction, unclear
  game states, missing edge-case flows, and polish needed for Google Play.
- **Cover the old app, not only the instructions** (added 2026-11-23 after his note that the BA added no value of its
  own): check every screen the sprint touches against the old app (`docs/old-app-parity.md`, `../mafia-dealer`), and
  list what the old app did there that the new one doesn't.
- **Bring proposals of its own:** each PRD has a "[BA] proposals" section with at least the improvements a player would
  expect from the genre (other party / social-deduction games) or that the sprint's own flows make obvious. Each one is
  marked as a proposal, for him to accept or drop.
- Write a concise **Sprint PRD** (`docs/sprint-N-prd.md`): target issues and **concrete acceptance criteria** for each.
- **STOP and ask Alhassan to sign off.** No application code before he approves or adjusts the scope.

## 2. [Senior Full-Stack Developer]: implementation
- Implement cleanly across the stack: error boundaries, loading states, responsive layouts, network drops, state sync,
  without breaking existing behavior.
- Summarize the changes against each acceptance criterion.

## 3. [Lead QA & Release Engineer]: adversarial verification
- Automated tests: happy paths, concurrent actions, abrupt disconnects, rapid state transitions, phone sizes.
- **A hands-on UX pass:** look at the rendered screens (English and Arabic, small phone, large text) as a player
  would. File what's confusing, cramped, unreadable or inconsistent, and send it back to the Developer.
- **Say what each layer proves and what it doesn't** (added 2026-11-23):
  - unit / server tests prove the rules;
  - widget tests prove screens and flows against fakes;
  - emulator tests prove the real app on Android with scripted players;
  - **none of them replaces people on real phones and networks.**
  
  Every report lists what only a human playtest can show.
- **Exploratory session** on the emulator when one is available: drive the real app like a tester (taps, back,
  rotation off, airplane mode, app killed), with screenshots, beyond the scripted paths.
- Run the whole suite and the build; fix regressions until everything is green; block the release otherwise.
- **The QA checklist** (added 2026-11-23 after his two-phone playtest found R2, R4, R6, R7 that every test had passed):
  - **Anything that talks to the outside world is tried for real at least once**, not only against a fake: a real push
    on the emulator (app open *and* closed), the old-relay import against the deployed Worker, sign-in. A fake proves
    our code; it can't prove Cloudflare, Firebase or Android behave the way the fake does.
  - **Every sheet and screen at real phone insets** (status bar, notch, gesture bar), not only the test's bare
    rectangle; the emulator screenshot is the judge.
  - **Old-app parity per screen:** before passing a screen, list what the old app had on it (`../mafia-dealer`) and
    check each item is there and reachable where the old app had it (buzz in the lobby, not hidden in a game bar).
  - **Two phones:** every social feature (friends, invites, chat, buzz, push) is tried app-to-app on the emulator with a
    scripted second player, from both sides.
  - **Feel is tested on a compiled build** (profile or release), never judged on a debug build.
  - The report says plainly which items were tried for real and which only against fakes.

## 4. [BA] acceptance review, then the Sprint Release Report
- The BA checks the result against each acceptance criterion (accepted, or sent back with a reason).
- The **Sprint Release Report** (`docs/sprint-N-report.md`) contains:
  - the test results;
  - the QA↔Dev notes (what QA found, how it was fixed);
  - the BA acceptance review;
  - the caveats for Alhassan's manual playtest.
