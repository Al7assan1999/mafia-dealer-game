// New builds reach the testers (S8-4), as the old app did until Play: a check of the latest GitHub Release on start and
// on return (at most every 10 minutes), "Update available · What's new" on Home, the APK downloaded inside the app and
// installed through Android's PackageInstaller (the first time Android asks; on Android 12+ later updates need no tap),
// "Updated to vX" once afterwards, and a push on every release (FCM topic `updates`). Off in the Play build.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'l10n/app_localizations.dart';
import 'prefs.dart';
import 'push.dart';
import 'ui.dart';
import 'version.dart';

/// The Android side (MainActivity, channel "mafia/keep"); tests pass a fake.
abstract class Installer {
  Future<bool> canInstall();
  Future<void> allowInstalls();
  Future<String> cacheDir();
  /// Hands the APK to Android; the result comes back through [onStatus] ('ok' never arrives: the app is replaced).
  Future<void> install(String path);
  Future<void> openUrl(String url);
  set onStatus(void Function(String status, String? message) f);
}

class AndroidInstaller implements Installer {
  static const _ch = MethodChannel('mafia/keep');
  void Function(String, String?)? _onStatus;
  AndroidInstaller() {
    _ch.setMethodCallHandler((c) async { if (c.method == 'installStatus') _onStatus?.call('${(c.arguments as Map)['status']}', (c.arguments as Map)['message'] as String?); });
  }
  @override
  Future<bool> canInstall() async => await _ch.invokeMethod<bool>('canInstall') ?? false;
  @override
  Future<void> allowInstalls() => _ch.invokeMethod('allowInstalls');
  @override
  Future<String> cacheDir() async => (await _ch.invokeMethod<String>('cacheDir'))!;
  @override
  Future<void> install(String path) => _ch.invokeMethod('install', {'path': path});
  @override
  Future<void> openUrl(String url) => _ch.invokeMethod('openUrl', {'url': url});
  @override
  set onStatus(void Function(String, String?) f) => _onStatus = f;
}

class Release {
  Release(this.version, this.build, this.apk, this.page, this.notes);
  final String version, apk, page;
  final int build;
  final List<String> notes;
}

class Updater extends ChangeNotifier {
  Updater(this.prefs, {http.Client? client, Installer? installer, int Function()? clock})
      : _http = client ?? http.Client(), installer = installer ?? AndroidInstaller(), _now = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    this.installer.onStatus = (s, m) { if (s != 'pending') { state = 'failed'; notifyListeners(); _fallback(); } };
    prefs.addListener(() { if (prefs.lang != _lang && _lang != null) _topic(); });
  }
  static const repo = 'Al7assan1999/mafia-dealer-game', every = 10 * 60 * 1000;
  final Prefs prefs;
  final http.Client _http;
  final Installer installer;
  final int Function() _now;
  PushService? _push;

  Release? latest; // a newer build than this one, or null
  String? state; // null | 'downloading' | 'installing' | 'allow' | 'failed'
  double progress = 0;
  int _checked = 0;

  /// Push is ready: follow the `updates_<language>` topic while alerts are on (the release push is sent in both).
  set push(PushService? p) { _push = p; _topic(); }
  String? _lang;
  Future<void> _topic() async {
    if (!selfUpdate || _push == null) return;
    final lang = prefs.lang;
    if (_lang != null && _lang != lang) await _push!.topic('updates_$_lang', false);
    _lang = lang;
    await _push!.topic('updates_$lang', prefs.updAlerts);
  }
  Future<void> setAlerts(bool on) async { prefs.updAlerts = on; notifyListeners(); await _topic(); }

  /// The latest release, if newer than this build. Quiet when offline or rate-limited.
  Future<void> check({bool force = false}) async {
    if (!selfUpdate || appBuild == 0) return; // local builds have no build number to compare
    if (!force && _now() - _checked < every) return;
    _checked = _now();
    try {
      final r = await _http.get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: {'accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, Object?>, m = RegExp(r'^v?([\d.]+)-b(\d+)$').firstMatch(j['tag_name'] as String? ?? ''); // v0.2.0-b100003
      final apk = (j['assets'] as List? ?? const []).cast<Map>().where((a) => (a['name'] as String? ?? '').endsWith('.apk')).firstOrNull;
      if (m == null || apk == null) return;
      final build = int.parse(m.group(2)!);
      latest = build > appBuild ? Release(m.group(1)!, build, apk['browser_download_url'] as String, j['html_url'] as String? ?? 'https://github.com/$repo/releases',
          [for (final line in (j['body'] as String? ?? '').split('\n')) if (line.trim().startsWith('- ')) line.trim().substring(2)]) : null;
      prefs.lastCheck = _now();
      notifyListeners();
    } catch (_) {}
  }

  /// "Updated to vX": once, the first start of a newer build than the last one seen (with that release's bullets).
  ({String version, List<String> notes})? takeUpdated() {
    final last = prefs.lastBuild;
    if (appBuild == 0 || last == appBuild) return null;
    prefs.lastBuild = appBuild;
    if (last == 0) return null; // the first install
    final notes = prefs.pendingNotes;
    prefs.pendingNotes = const [];
    return (version: appVersion, notes: notes);
  }

  /// Downloads the APK with progress and hands it to Android. Falls back to the download page on any failure.
  Future<void> update() async {
    final r = latest;
    if (r == null || state == 'downloading' || state == 'installing') return;
    try {
      if (!await installer.canInstall()) { state = 'allow'; notifyListeners(); await installer.allowInstalls(); return; }
      state = 'downloading'; progress = 0; notifyListeners();
      final res = await _http.send(http.Request('GET', Uri.parse(r.apk)));
      if (res.statusCode != 200) throw HttpException('download ${res.statusCode}');
      final f = File('${await installer.cacheDir()}/update.apk'), out = f.openWrite();
      final total = res.contentLength ?? 0;
      var got = 0;
      await for (final chunk in res.stream) {
        out.add(chunk); got += chunk.length;
        if (total > 0) { final p = got / total; if (p - progress >= .01 || p == 1) { progress = p; notifyListeners(); } }
      }
      await out.close();
      if (total > 0 && got != total) throw const HttpException('short');
      prefs.pendingNotes = r.notes; // shown once by "Updated to vX"
      state = 'installing'; notifyListeners();
      await installer.install(f.path);
    } catch (_) {
      state = 'failed'; notifyListeners();
      await _fallback();
    }
  }

  Future<void> _fallback() async { if (latest != null) { try { await installer.openUrl(latest!.page); } catch (_) {} } }
}

/// Home's "Update available" card.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key, required this.updater});
  final Updater updater;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: updater, builder: (context, _) {
        final r = updater.latest, l = L.of(context);
        if (r == null) return const SizedBox.shrink();
        final busy = updater.state == 'downloading' || updater.state == 'installing';
        return Sec(key: const Key('updateCard'), color: C.card2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.system_update, color: C.gold), const SizedBox(width: 10),
            Expanded(child: Text(l.updAvail, style: head.copyWith(fontSize: 18, color: C.gold))),
            Text('v${r.version}', style: TextStyle(color: C.mute)),
          ]),
          if (r.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l.updWhatsNew(r.version), style: TextStyle(color: C.mute, fontSize: 12)),
            for (final n in r.notes.take(3)) Padding(padding: const EdgeInsets.only(top: 3), child: Text('• $n')),
            if (r.notes.length > 3) Align(alignment: AlignmentDirectional.centerStart, child: TextButton(key: const Key('updSeeAll'),
                onPressed: () => notesSheet(context, l.updWhatsNew(r.version), r.notes), child: Text('${r.notes.length - 3}+', style: TextStyle(color: C.red2)))),
          ],
          const SizedBox(height: 10),
          if (updater.state == 'downloading') ...[
            LinearProgressIndicator(value: updater.progress, color: C.red, backgroundColor: C.card),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.updDownloading((updater.progress * 100).round()), key: const Key('updProgress'), style: TextStyle(color: C.mute))),
          ] else if (updater.state == 'installing')
            Text(l.updInstalling, style: TextStyle(color: C.mute))
          else ...[
            if (updater.state == 'allow') Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l.updAllow, key: const Key('updAllow'), style: TextStyle(color: C.mute))),
            if (updater.state == 'failed') Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l.updFailed, style: TextStyle(color: C.red2))),
            Btn(l.updBtn, key: const Key('updBtn'), icon: Icons.download, onTap: busy ? null : updater.update),
          ],
        ]));
      });
}

Future<void> notesSheet(BuildContext context, String title, List<String> notes) => showModalBottomSheet(
      context: context, backgroundColor: C.card, isScrollControlled: true,
      builder: (_) => SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: head.copyWith(fontSize: 20)),
        const SizedBox(height: 10),
        for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $n')),
        const SizedBox(height: 8),
        Btn(L.of(context).ok, key: const Key('notesOk'), onTap: () => Navigator.of(context).pop()),
      ]))),
    );
