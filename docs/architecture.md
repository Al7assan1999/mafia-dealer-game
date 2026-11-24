# The app's architecture and state management

Written in Sprint 13 (2026-11-23), at his request: *"organize the code in a clean code structure and define state
management, so we don't face issues like before (a couple of files with thousands of lines)."* Before this sprint,
`online.dart` alone was 1,203 lines with eleven screens and the room state in it. The guard test
`app/test/architecture_test.dart` enforces the rules below on every CI run.

## Layers (`app/lib/`)
| Folder | Holds | May import |
| --- | --- | --- |
| `core/` | What every part needs and that knows no screen: `api` (HTTP), `prefs` (on-phone settings), `audio`, `push`, `auth` (session store, Google), `ui` (palette, theme, shared widgets), `feedback` (toasts, error texts), `version` | `core/` only |
| `state/` | The app's live state: `Account` (who I am, friends, bell, saved names), `RoomConn` (one room's socket), `ActiveRoom` (the room kept while minimized), the data `models` | `core/`, `state/` |
| `features/<area>/` | Screens and their widgets, one area per folder: `home`, `settings`, `account`, `friends`, `notifications`, `online`, `room`, `chat`, `offline`, `wifi`, `stats`, `history`, `old_history`, `intro`, `guide`, `safety`, `update` | everything |
| `app.dart`, `main.dart` | Start-up: builds the services and the `MaterialApp` | everything |

**State never imports a screen.** When state must cause something visible (the room re-opening, a buzz alert), the
screen hands it a function (`ActiveRoom.hold(reopen:, alert:)`).

## State management: controllers, listened to
- **Every piece of shared state lives in one `ChangeNotifier` controller** in `state/` (or `core/prefs.dart` for the
  on-phone settings). A controller owns its data, talks to the server, and calls `notifyListeners()` when its data
  changes. Nothing else changes that data.
- **Screens read controllers and rebuild with `ListenableBuilder`.** A screen never keeps its own copy of shared data
  (no "friends list" in a screen's state): it reads the controller every build.
- **A screen's own `State` holds only what belongs to that screen:** a text field, a selected option, a busy flag.
- **Controllers are passed in explicitly** (constructor parameters: `account`, `prefs`, `audio`), so every screen can
  be built in a test with fakes. There are no hidden globals, except `ActiveRoom.instance` and the navigator / message
  keys, which the whole app shares by nature.
- **One-off events** (a buzz, a chat message for the bell) travel as streams or callbacks from the controller, not as
  fields screens poll.

## File rules (enforced)
- **No file over 500 lines** in `lib/` (the generated `l10n/` excepted). A screen that grows past that is split: its
  views become `part` files of the same library (as `features/room/`: `room_screen.dart` + `room_lobby.dart`,
  `room_play.dart`, `room_end.dart`), or its widgets get their own files.
- **One screen (or one controller) per file**, named after it.
- **Imports are `package:mafia_dealer/...`**, never relative, so a file can move without breaking others.
- **Texts go through `l10n`** (English + Arabic, ICU plurals for counts: the plural guard test).
