import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// The server's REST API. Every call has a 10 s timeout; failures become an ApiError with the server's error code,
// 'offline' (no network, timeout) or 'auth' (the session is gone).

/// The server. Debug builds can point elsewhere: --dart-define=API_BASE=http://10.0.2.2:8787 (the emulator's host).
const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://mafia-dealer-game.mafiadealer.workers.dev');

class ApiError implements Exception {
  ApiError(this.code, [this.status = 0]);
  final String code;
  final int status;
  @override
  String toString() => 'ApiError($code, $status)';
}

class Api {
  Api({this.base = apiBase, http.Client? client}) : _http = client ?? http.Client();
  final String base;
  final http.Client _http;
  String? token;

  Future<Map<String, Object?>> get(String path) => call('GET', path);
  Future<Map<String, Object?>> post(String path, [Object? body]) => call('POST', path, body);
  Future<Map<String, Object?>> patch(String path, Object body) => call('PATCH', path, body);
  Future<Map<String, Object?>> put(String path, Object body) => call('PUT', path, body);
  Future<Map<String, Object?>> delete(String path, [Object? body]) => call('DELETE', path, body);

  Future<Map<String, Object?>> call(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$base$path'));
    if (token != null && token!.isNotEmpty) req.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response r;
    try {
      r = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 10)));
    } on TimeoutException {
      throw ApiError('offline');
    } on SocketException {
      throw ApiError('offline');
    } on http.ClientException {
      throw ApiError('offline');
    }
    Map<String, Object?> j;
    try { j = r.body.isEmpty ? {} : jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>; } catch (_) { j = {}; }
    if (r.statusCode >= 400) throw ApiError(r.statusCode == 401 ? 'auth' : (j['error'] as String? ?? 'server'), r.statusCode);
    return j;
  }

  /// The URL of an account's photo (public; the version in the URL busts the cache).
  String avatarUrl(String userId, int ver) => '$base/v1/avatars/$userId?v=$ver';

  /// The socket URL (wss / ws) for a path.
  Uri socket(String path) => Uri.parse(base.replaceFirst(RegExp('^http'), 'ws') + path);
}
