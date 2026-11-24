
// This build's version (CI passes them: --dart-define=VERSION=0.2.0 --dart-define=BUILD=100003). Local builds are 0.
const appVersion = String.fromEnvironment('VERSION', defaultValue: '0.0.0');
const appBuild = int.fromEnvironment('BUILD');

/// Updates itself from GitHub Releases (S8-4). The Play build turns it off (--dart-define=SELF_UPDATE=false): Google Play
/// doesn't allow an app to update itself.
const selfUpdate = bool.fromEnvironment('SELF_UPDATE', defaultValue: true);
