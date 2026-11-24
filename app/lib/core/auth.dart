import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mafia_dealer/core/api.dart';

/// The Google OAuth "Web" client id (the audience the server checks). Empty until Google Cloud is set up:
/// --dart-define=GOOGLE_SERVER_CLIENT_ID=...
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// Where the session token lives: Android's encrypted storage on a phone, memory in tests.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class SecureTokens implements TokenStore {
  static const _s = FlutterSecureStorage();
  // [hotfix 0.4.9] On some phones Android's secure storage fails quietly (his: signed out at every start, a new "device"
  // per sign-in). The session is also kept in the app's private storage and read from there when secure storage fails.
  // ponytail: app-private, not encrypted; drop the copy once secure storage is proven on his phone.
  @override
  Future<String?> read() async {
    String? t;
    try {
      t = await _s.read(key: 'session');
    } catch (_) {}
    if (t != null && t.length == 43) return t;

    final fallback = (await SharedPreferences.getInstance()).getString('session');
    return (fallback != null && fallback.length == 43) ? fallback : null;
  }
  @override
  Future<void> write(String? t) async {
    try { t == null ? await _s.delete(key: 'session') : await _s.write(key: 'session', value: t); } catch (_) {}
    final p = await SharedPreferences.getInstance();
    t == null ? await p.remove('session') : await p.setString('session', t);
  }
}

class MemoryTokens implements TokenStore {
  String? t;
  @override
  Future<String?> read() async => t;
  @override
  Future<void> write(String? v) async => t = v;
}

/// Google sign-in through Android's Credential Manager; returns an ID token, or throws ApiError ('cancel', 'google').
abstract class GoogleAuth {
  bool get available;
  Future<String> idToken();
}

class CredentialManagerGoogle implements GoogleAuth {
  bool _init = false;
  @override
  bool get available => googleServerClientId.isNotEmpty;
  @override
  Future<String> idToken() async {
    try {
      if (!_init) { await GoogleSignIn.instance.initialize(serverClientId: googleServerClientId); _init = true; }
      final a = await GoogleSignIn.instance.authenticate();
      final t = a.authentication.idToken;
      if (t == null) throw ApiError('google');
      return t;
    } on GoogleSignInException catch (e) {
      throw ApiError(e.code == GoogleSignInExceptionCode.canceled ? 'cancel' : 'google');
    }
  }
}

/// Another account as the server shows it (never an email).
