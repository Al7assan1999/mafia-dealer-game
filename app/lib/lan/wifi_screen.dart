// Wi-Fi / Hotspot: host a room on this phone, or find one on the network (list or address). Every phone then plays in
// the online room screen, connected to the host's local server.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account.dart';
import '../api.dart';
import '../audio.dart';
import '../l10n/app_localizations.dart';
import '../online.dart';
import '../prefs.dart';
import '../ui.dart';
import 'lan.dart';
import 'local_room.dart';

/// The hosted room on this phone: its server, its snapshot for "Resume hosting", and the keep-alive service.
abstract final class LanHost {
  static LanServer? server;
  static const _keep = MethodChannel('mafia/keep');

  /// Starts hosting (a new room, or the saved one). Returns the room code, or null if this network refused.
  static Future<String?> start(Prefs prefs, {Map<String, Object?>? restore, String? title, String? text}) async {
    await stop(clear: false);
    final code = (restore?['code'] as String?) ?? newRoomCode();
    final room = LocalRoom(code, prefs.deviceId, restore: restore, onChange: (r) => prefs.lanHost = r.closedRoom ? null : r.toJson());
    final s = LanServer(room);
    try { await s.start(); } catch (_) { return null; }
    server = s;
    prefs.lanHost = room.toJson();
    try { await _keep.invokeMethod('start', {'title': title ?? 'Mafia Dealer', 'text': text ?? code}); } catch (_) {} // not on Android (tests)
    return code;
  }

  /// Stops hosting (the room ends; `clear: false` keeps the snapshot, e.g. before resuming).
  static Future<void> stop({bool clear = true}) async {
    await server?.stop();
    server = null;
    try { await _keep.invokeMethod('stop'); } catch (_) {}
  }
}

/// This phone's Wi-Fi identity token (a device id, a name, and the account if signed in).
String lanToken(Prefs prefs, Account account, String name) => Identity(prefs.deviceId, name,
        handle: account.signedIn ? account.handle : null, userId: account.signedIn ? account.card!.id : null, preset: account.card?.preset ?? 0)
    .token();

/// Opens the room at [address] (the host's own phone uses 127.0.0.1).
void openLanRoom(BuildContext context, {required Prefs prefs, required Audio audio, required Account account, required String address,
    required String code, required String name, bool host = false, bool replace = false}) {
  final api = Api(base: 'http://$address:$lanPort')..token = lanToken(prefs, account, name);
  if (!host) prefs.lanJoin = {'address': address, 'code': code, 'name': name};
  final route = MaterialPageRoute<void>(builder: (_) => RoomScreen(
        account: account, prefs: prefs, audio: audio, code: code, api: api, lan: true, lanHost: host,
        relocate: host ? null : () async {
          final a = await relocate(code, address);
          if (a == null) return null;
          prefs.lanJoin = {'address': a, 'code': code, 'name': name};
          return Api(base: 'http://$a:$lanPort')..token = api.token;
        },
        onClose: host ? () => LanHost.stop() : null,
      ));
  replace ? Navigator.of(context).pushReplacement(route) : Navigator.of(context).push(route);
}

class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key, required this.prefs, required this.audio, required this.account});
  /// Tests replace the network scan (and this phone's addresses).
  static Future<List<FoundRoom>> Function()? testScan;
  static List<String>? testAddresses;
  final Prefs prefs;
  final Audio audio;
  final Account account;
  @override
  State<WifiScreen> createState() => _WifiState();
}

class _WifiState extends State<WifiScreen> {
  late final name = TextEditingController(text: widget.account.signedIn ? widget.account.display : widget.prefs.lanName);
  final address = TextEditingController();
  final found = <FoundRoom>[];
  List<String> mine = const [];
  bool scanning = false, busy = false;
  String? error;

  @override
  void initState() { super.initState(); _scan(); }

  Future<void> _scan() async {
    setState(() { scanning = true; found.clear(); error = null; });
    mine = WifiScreen.testAddresses ?? await localAddresses();
    if (WifiScreen.testScan != null) {
      found.addAll(await WifiScreen.testScan!());
    } else if (mine.isNotEmpty) {
      await scanLan(onFound: (f) { if (mounted) setState(() => found.add(f)); });
    }
    if (mounted) setState(() => scanning = false);
  }

  String? _name(L l) {
    final n = name.text.trim();
    if (n.isEmpty || n.length > 18) { setState(() => error = l.eBadName); return null; }
    widget.prefs.lanName = n;
    return n;
  }

  Future<void> _host(L l) async {
    final n = _name(l);
    if (n == null || busy) return;
    setState(() { busy = true; error = null; });
    final code = await LanHost.start(widget.prefs, title: l.hostingTitle, text: l.hostingText(''));
    if (!mounted) return;
    setState(() => busy = false);
    if (code == null) return setState(() => error = l.cantHost);
    openLanRoom(context, prefs: widget.prefs, audio: widget.audio, account: widget.account, address: '127.0.0.1', code: code, name: n, host: true, replace: true);
  }

  Future<void> _join(L l, String addr, {String? code}) async {
    final n = _name(l);
    if (n == null || busy) return;
    setState(() { busy = true; error = null; });
    final r = code == null ? await probe(addr.trim()) : null;
    if (!mounted) return;
    setState(() => busy = false);
    final c = code ?? r?.code;
    if (c == null) return setState(() => error = l.noAnswer(addr.trim())); // [QA] not the scan's "nothing found" again
    openLanRoom(context, prefs: widget.prefs, audio: widget.audio, account: widget.account, address: addr.trim(), code: c, name: n, replace: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.wifi.replaceAll('\u2011', '-'), style: head.copyWith(fontSize: 20))), // [QA] U1: no U+2011 in the heading font
      body: Stage(center: false, children: [
        Text(l.wifiSub, style: const TextStyle(color: C.mute)),
        const SizedBox(height: 14),
        TextField(key: const Key('lanName'), controller: name, maxLength: 18, decoration: InputDecoration(labelText: l.yourName, counterText: '')),
        const SizedBox(height: 12),
        Btn(l.hostRoom, key: const Key('hostRoom'), icon: Icons.wifi_tethering, onTap: busy ? null : () => _host(l)),
        const SizedBox(height: 18),
        Sec(title: l.joinRoom, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!scanning && mine.isEmpty) Text(l.noWifi, key: const Key('noWifi'), style: const TextStyle(color: C.red2)),
          if (scanning) Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.mute)),
            const SizedBox(width: 10),
            Expanded(child: Text(l.searching, style: const TextStyle(color: C.mute))),
          ]),
          for (final f in found)
            ListTile(
              key: Key('found_${f.code}'), contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.wifi, color: C.gold),
              title: Text('${f.host} · ${f.code}'),
              subtitle: Text(l.roomPlayers(f.players, f.status == 'game' ? l.statusGame : l.statusLobby), style: const TextStyle(color: C.mute)),
              trailing: const Icon(Icons.chevron_right, color: C.dim),
              onTap: () => _join(l, f.address, code: f.code),
            ),
          if (!scanning && mine.isNotEmpty && found.isEmpty) ...[
            Text(l.nothingFound, key: const Key('nothingFound'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(l.nothingFoundTips, style: const TextStyle(color: C.mute, fontSize: 12)),
          ],
          if (!scanning) Align(alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(key: const Key('searchAgain'), onPressed: _scan, icon: const Icon(Icons.refresh, color: C.red2), label: Text(l.searchAgain, style: const TextStyle(color: C.red2)))),
          const Divider(),
          Text(l.manualAddress, style: const TextStyle(color: C.mute, fontSize: 13)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(key: const Key('lanAddress'), controller: address, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr, decoration: InputDecoration(hintText: l.addressHint))),
            const SizedBox(width: 8),
            FilledButton(key: const Key('joinAddress'), style: FilledButton.styleFrom(backgroundColor: C.red), onPressed: busy ? null : () => _join(l, address.text), child: Text(l.join)),
          ]),
        ])),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, key: const Key('error'), style: const TextStyle(color: C.red2))),
      ]),
    );
  }
}

