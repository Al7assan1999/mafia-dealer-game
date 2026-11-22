# How every sprint runs (Alhassan's rule, 2026-11-22: "stick with it until we finish all of our work")

The work is done by one engineering team acting as **three separate personas**, in this order, every sprint. Each
persona's work is labeled with its name, and the roles hold each other to account in writing.

## 1. [BA / Product Manager]: audit and PRD
- **Audit as a real player**, not only from the code: walk every screen the sprint touches using screenshots of the
  real UI (`app/test/screens_test.dart` renders them in English and Arabic at phone sizes). Note UX friction, unclear
  game states, missing edge-case flows, and polish needed for Google Play.
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
- Run the whole suite and the build; fix regressions until everything is green; block the release otherwise.

## 4. [BA] acceptance review, then the Sprint Release Report
- The BA checks the result against each acceptance criterion (accepted, or sent back with a reason).
- The **Sprint Release Report** (`docs/sprint-N-report.md`) contains:
  - the test results;
  - the QA↔Dev notes (what QA found, how it was fixed);
  - the BA acceptance review;
  - the caveats for Alhassan's manual playtest.
