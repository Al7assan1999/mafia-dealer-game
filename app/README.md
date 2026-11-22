# Mafia Dealer: Party Game (Flutter app)

Android app `com.mafiadealer.game`. Offline play on one phone (no account, nothing logged), judged by the Dart engine
in `../packages/engine_dart`; accounts, friends and the bell against the Cloudflare server (Sprint 3).

Build settings (`--dart-define`): `API_BASE` (default: the live Worker; the emulator test uses `http://10.0.2.2:8787`),
`GOOGLE_SERVER_CLIENT_ID` (the Google OAuth Web client; empty = the Google button says it isn't set up). Every build is
signed with the upload key (local: `android/key.properties`, git-ignored; CI: the `ANDROID_KEYSTORE_B64` /
`ANDROID_KEYSTORE_PASSWORD` secrets), so Google sign-in sees one SHA-1 everywhere. `lib/api.dart`, `lib/account.dart`
and `lib/account_screens.dart` are the account side.

```bash
flutter pub get        # also generates the strings (lib/l10n/*.arb -> app_localizations.dart)
flutter analyze
flutter test           # widget tests: whole games at 3 phone sizes, English + Arabic, 1.3x text, adversarial cases
flutter test integration_test   # on a connected phone or emulator (CI runs it on an emulator)
flutter build apk --debug
```

- `lib/game.dart`: the offline game (which screen, who holds the phone, narration, saving the game in progress as
  its engine record so it survives the app being killed). `lib/game_screen.dart`: its screens. `lib/setup.dart`,
  `lib/main.dart` (home, settings), `lib/ui.dart` (the Noir look), `lib/audio.dart`, `lib/prefs.dart`.
- Strings: `lib/l10n/app_en.arb` and `app_ar.arb` (no hard-coded UI text). Arabic mirrors the whole layout.
- `assets/voice/`: the old app's 84 narrator clips (English only) and `names.json` (names the narrator can say).
  `assets/sfx/`: the old app's procedural sound effects, rendered once from its Web Audio code to WAV.
  `assets/fonts/`: IBM Plex Sans Arabic, Special Elite, El Messiri (licenses next to them).
- Tools on this laptop (2026-11-22): `C:\Users\WGN\sdk\` (Flutter 3.47.9, Temurin JDK 21, Android SDK + NDK).
