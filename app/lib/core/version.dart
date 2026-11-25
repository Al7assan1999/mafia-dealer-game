
// This build's version (CI passes them: --dart-define=VERSION=0.2.0 --dart-define=BUILD=100003). Local builds are 0.
const appVersion = String.fromEnvironment('VERSION', defaultValue: '0.0.0');
const appBuild = int.fromEnvironment('BUILD');

/// The first build (1.0.0): an older phone can't be dealt into any game (packages/protocol MODES_BUILD).
const modesBuild = 100017;

/// The build a phone tells its room. Released builds are 100000 + the release run; anything lower is a local, test or
/// CI build of this code, so it reports the 1.0.0 build rather than look like an old app.
const roomBuild = appBuild >= 100000 ? appBuild : modesBuild;

/// Updates itself from GitHub Releases (S8-4). The Play build turns it off (--dart-define=SELF_UPDATE=false): Google Play
/// doesn't allow an app to update itself.
const selfUpdate = bool.fromEnvironment('SELF_UPDATE', defaultValue: true);
