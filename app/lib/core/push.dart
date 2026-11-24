import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

// Push notifications through Firebase Cloud Messaging. The server sends one only while the app is closed (the hub
// socket is gone); Android shows it on one of the channels MainActivity creates. Without google-services.json (a fork,
// or before Firebase is set up) Firebase can't start, and push simply stays off.

/// What the app needs from push; tests pass a fake.
abstract class PushService {
  /// Asks for Android 13's notification permission (the system shows its prompt once).
  Future<void> ask();
  Future<String?> token();
  Stream<String> get tokenRefresh;
  /// The data of the notification that opened the app, if one did.
  Future<Map<String, String>?> initial();
  /// Notifications tapped while the app was in the background.
  Stream<Map<String, String>> get opened;
  /// Follows (or stops following) a topic: `updates` for new versions, no account needed.
  Future<void> topic(String name, bool on);
}

class FcmPush implements PushService {
  FcmPush._();
  /// Starts Firebase; null when it isn't configured on this build.
  static Future<FcmPush?> start() async {
    try { await Firebase.initializeApp(); return FcmPush._(); } catch (_) { return null; }
  }
  FirebaseMessaging get _m => FirebaseMessaging.instance;
  @override
  Future<void> ask() async { try { await _m.requestPermission(); } catch (_) {} }
  // ponytail: the registration token (deprecated in firebase_messaging 17 for FIDs); the server's HTTP v1 `message.token`
  // takes exactly this. Move to register()/onRegistered once FCM documents FID targets for HTTP v1.
  @override
  // ignore: deprecated_member_use
  Future<String?> token() async { try { return await _m.getToken(); } catch (_) { return null; } }
  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRefresh => _m.onTokenRefresh;
  @override
  Future<Map<String, String>?> initial() async => (await _m.getInitialMessage())?.data.map((k, v) => MapEntry(k, '$v'));
  @override
  Stream<Map<String, String>> get opened => FirebaseMessaging.onMessageOpenedApp.map((m) => m.data.map((k, v) => MapEntry(k, '$v')));
  @override
  Future<void> topic(String name, bool on) async { try { on ? await _m.subscribeToTopic(name) : await _m.unsubscribeFromTopic(name); } catch (_) {} }
}

/// Opens this app's notification settings in Android (each channel can be switched off there).
Future<void> openNotificationSettings() async {
  try { await const MethodChannel('mafia/keep').invokeMethod('notifSettings'); } catch (_) {}
}
