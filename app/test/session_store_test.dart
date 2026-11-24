// [hotfix 0.4.10] His phone: Android's secure storage kept an OLD, revoked session (its writes failed), the app read it
// first, the server answered "auth" and the app signed out at every start. The app's own copy wins now.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stale session in secure storage never wins over the one the app saved last', () async {
    FlutterSecureStorage.setMockInitialValues({'session': 'old-revoked'});
    SharedPreferences.setMockInitialValues({'session': 'new-good'});
    expect(await SecureTokens().read(), 'new-good');
  });

  test('a phone that never had the app copy (an update from 0.4.8 or older) still reads secure storage', () async {
    FlutterSecureStorage.setMockInitialValues({'session': 'from-secure'});
    SharedPreferences.setMockInitialValues({});
    expect(await SecureTokens().read(), 'from-secure');
  });

  test('signing in saves both; signing out clears both (nothing stale comes back)', () async {
    FlutterSecureStorage.setMockInitialValues({'session': 'old'});
    SharedPreferences.setMockInitialValues({});
    final t = SecureTokens();
    await t.write('fresh');
    expect(await t.read(), 'fresh');
    expect(await const FlutterSecureStorage().read(key: 'session'), 'fresh');
    await t.write(null);
    expect(await t.read(), isNull);
  });
}
