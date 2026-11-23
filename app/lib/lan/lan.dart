// Wi-Fi / Hotspot networking: the host phone's server (the room's socket on port 8765, plus a small "who's here" answer
// for discovery), scanning the local network for rooms, and this phone's Wi-Fi identity.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'local_room.dart';

const lanPort = 8765;

class _Conn implements LanConn {
  _Conn(this.ws, this.uid);
  final WebSocket ws;
  @override
  final String uid;
  @override
  void send(String data) => ws.add(data);
  @override
  void close([int code = 1000]) => ws.close(code);
}

/// The host phone's server: runs [room] for every phone on the network (the host's own app connects to it too).
class LanServer {
  LanServer(this.room);
  final LocalRoom room;
  HttpServer? _server;
  Timer? _tick;

  Future<void> start({int port = lanPort}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => room.tick());
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.uri.path == '/mafia') { // discovery: what's here
        final info = room.info(), host = (info['members'] as List).cast<Map>().where((m) => m['host'] == true).firstOrNull;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'app': 'mafia-dealer', 'code': room.code, 'host': host?['display'] ?? '', 'players': (info['members'] as List).length, 'status': info['status']}));
        return await req.response.close();
      }
      if (req.uri.path == '/v1/rooms/${room.code}/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
        final protos = (req.headers['sec-websocket-protocol'] ?? const []).expand((h) => h.split(',')).map((s) => s.trim()).toList();
        final id = protos.length > 1 ? Identity.parse(protos[1]) : null;
        if (id == null || room.closedRoom) { req.response.statusCode = 401; return await req.response.close(); }
        final ws = await WebSocketTransformer.upgrade(req, protocolSelector: (_) => 'mafia.v1');
        final c = _Conn(ws, id.uid);
        if (room.join(c, id, since: int.tryParse(req.uri.queryParameters['rev'] ?? '')) != null) return;
        ws.listen((d) => room.message(c, d is String ? d : utf8.decode(d as List<int>)), onDone: () => room.closed(c), onError: (_) => room.closed(c), cancelOnError: true);
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    } catch (_) {}
  }

  /// The port it listens on (8765; tests pass 0 for a free one).
  int get port => _server?.port ?? lanPort;

  Future<void> stop() async {
    _tick?.cancel();
    for (final c in List.of(room.conns)) { c.close(4000); }
    await _server?.close(force: true);
    _server = null;
  }
}

/// A room found on the network.
class FoundRoom {
  FoundRoom(this.address, this.code, this.host, this.players, this.status);
  final String address, code, host, status;
  final int players;
}

/// This phone's local addresses (private IPv4 only: Wi-Fi, hotspot).
Future<List<String>> localAddresses() async {
  try {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    bool private(String a) => a.startsWith('10.') || a.startsWith('192.168.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a);
    return [for (final i in ifs) for (final a in i.addresses) if (private(a.address)) a.address];
  } catch (_) {
    return const [];
  }
}

/// Asks one address whether a room is there.
Future<FoundRoom?> probe(String address, {Duration timeout = const Duration(milliseconds: 700), int port = lanPort}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(Uri.parse('http://$address:$port/mafia')).timeout(timeout);
    final res = await req.close().timeout(timeout);
    final j = jsonDecode(await res.transform(utf8.decoder).join().timeout(timeout)) as Map<String, Object?>;
    if (j['app'] != 'mafia-dealer') return null;
    return FoundRoom(address, j['code'] as String, j['host'] as String? ?? '', j['players'] as int? ?? 0, j['status'] as String? ?? 'lobby');
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Scans this phone's local networks (/24) for rooms, 64 addresses at a time (a hotspot or home router: a few seconds).
Future<List<FoundRoom>> scanLan({void Function(FoundRoom)? onFound}) async {
  final mine = await localAddresses(), targets = <String>{};
  for (final a in mine) {
    final p = a.substring(0, a.lastIndexOf('.'));
    for (var i = 1; i < 255; i++) { targets.add('$p.$i'); }
  }
  final found = <FoundRoom>[], list = targets.toList();
  for (var i = 0; i < list.length; i += 64) {
    final batch = await Future.wait(list.sublist(i, min(i + 64, list.length)).map(probe));
    for (final f in batch.whereType<FoundRoom>()) { found.add(f); onFound?.call(f); }
  }
  return found;
}

/// The room's address now (after a host restart its address may change): the last address, else a scan for the code.
Future<String?> relocate(String code, String lastAddress) async {
  final again = await probe(lastAddress);
  if (again != null && again.code == code) return lastAddress;
  final all = await scanLan();
  return all.where((r) => r.code == code).firstOrNull?.address;
}

/// A new 6-digit room code.
String newRoomCode() => '${Random.secure().nextInt(900000) + 100000}';
