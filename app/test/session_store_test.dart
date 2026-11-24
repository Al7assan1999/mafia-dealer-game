// [hotfix 0.4.10] His phone: Android's secure storage kept an OLD, revoked session (its writes failed), the app read it
// first, the server answered "auth" and the app signed out at every start. The app's own copy wins now.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stale session in secure storage never wins over the one the app saved last', () async {
    FlutterSecureStorage.setMockInitialValues({'session': 'o' * 43});
    SharedPreferences.setMockInitialValues({'session': 'n' * 43});
    expect(await SecureTokens().read(), 'n' * 43);
  });

  test('a phone that never had the app copy (an update from 0.4.8 or older) still reads secure storage', () async {
    FlutterSecureStorage.setMockInitialValues({'session': 's' * 43});
    SharedPreferences.setMockInitialValues({});
    expect(await SecureTokens().read(), 's' * 43);
  });

  test('a broken value in either place is ignored', () async {
    FlutterSecureStorage.setMockInitialValues({'session': 'short'});
    SharedPreferences.setMockInitialValues({'session': ''});
    expect(await SecureTokens().read(), isNull);
  });

  test('signing in saves both; signing out clears both (nothing stale comes back)', () async {
    FlutterSecureStorage.setMockInitialValues({'session': 'o' * 43});
    SharedPreferences.setMockInitialValues({});
    final t = SecureTokens();
    await t.write('f' * 43);
    expect(await t.read(), 'f' * 43);
    expect(await const FlutterSecureStorage().read(key: 'session'), 'f' * 43);
    await t.write(null);
    expect(await t.read(), isNull);
  });
}
