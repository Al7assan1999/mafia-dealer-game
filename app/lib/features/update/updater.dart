import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/push.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/core/version.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

// New builds reach the testers (S8-4), as the old app did until Play: a check of the latest GitHub Release on start and
// on return (at most every 10 minutes), "Update available · What's new" on Home, the APK downloaded inside the app and
// installed through Android's PackageInstaller (the first time Android asks; on Android 12+ later updates need no tap),
// "Updated to vX" once afterwards, and a push on every release (FCM topic `updates`). Off in the Play build.

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

/// [R9] The phone's processor as Android names it in an APK split (Dart's own Abi; no plugin).
String phoneAbi() => switch (Abi.current()) { Abi.androidArm64 => 'arm64-v8a', Abi.androidArm => 'armeabi-v7a', Abi.androidX64 => 'x86_64', _ => '' };

/// [R9] The release's APK for this processor (`…-arm64-v8a.apk`); else one without a processor in its name (an older
/// release, one APK for all); else the first. Releases list arm64 first, so 0.3.0 phones (which took the first) get it.
Map? pickApk(List<Map> assets, String abi) {
  final apks = assets.where((a) => (a['name'] as String? ?? '').endsWith('.apk')).toList();
  const abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
  return apks.where((a) => abi.isNotEmpty && (a['name'] as String).endsWith('-$abi.apk')).firstOrNull
      ?? apks.where((a) => !abis.any((x) => (a['name'] as String).endsWith('-$x.apk'))).firstOrNull
      ?? apks.firstOrNull;
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

  /// Push is ready: follow the `updates_<language>` topic (the release push is sent in both). [S13 his note 14, as he
  /// meant it] the "new version is out" push stays; only the "Mafia Dealer updated" one after installing is gone. Turned
  /// off in Android's settings (channel "New versions"), no switch in the app.
  set push(PushService? p) { _push = p; _topic(); }
  String? _lang;
  Future<void> _topic() async {
    if (!selfUpdate || _push == null) return;
    final lang = prefs.lang;
    for (final t in ['updates_en', 'updates_ar']) { await _push!.topic(t, t == 'updates_$lang'); }
    _lang = lang;
  }

  String? abi; // tests set the phone's processor

  /// The latest release, if newer than this build. Quiet when offline or rate-limited.
  Future<void> check({bool force = false}) async {
    if (!selfUpdate || appBuild == 0) return; // local builds have no build number to compare
    if (!force && _now() - _checked < every) return;
    _checked = _now();
    try {
      final r = await _http.get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: {'accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, Object?>, m = RegExp(r'^v?([\d.]+)-b(\d+)$').firstMatch(j['tag_name'] as String? ?? ''); // v0.2.0-b100003
      final apk = pickApk((j['assets'] as List? ?? const []).cast<Map>(), abi ?? phoneAbi());
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
    if (notes.isNotEmpty) { prefs.versionNotes = notes; prefs.versionNotesOf = appVersion; }
    return (version: appVersion, notes: notes);
  }

  /// [S13-5 / his note 11] What's new in the version on this phone, any time (Home's footer, as the old app): kept from
  /// the update, else read once from this version's GitHub Release.
  Future<List<String>> whatsNew() async {
    if (prefs.versionNotesOf == appVersion && prefs.versionNotes.isNotEmpty) return prefs.versionNotes;
    try {
      final r = await _http.get(Uri.parse('https://api.github.com/repos/$repo/releases/tags/v$appVersion-b$appBuild'),
          headers: {'accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return const [];
      final body = (jsonDecode(r.body) as Map<String, Object?>)['body'] as String? ?? '';
      final notes = [for (final line in body.split('\n')) if (line.trim().startsWith('- ')) line.trim().substring(2)];
      if (notes.isNotEmpty) { prefs.versionNotes = notes; prefs.versionNotesOf = appVersion; }
      return notes;
    } catch (_) { return const []; }
  }

  /// [S13-5 / his note 15] The downloaded update stayed in the cache for good (~27 MB each time): gone once the new
  /// version runs (or the install didn't happen; the next update downloads it again).
  Future<void> cleanup() async {
    try { final f = File('${await installer.cacheDir()}/update.apk'); if (await f.exists()) await f.delete(); } catch (_) {}
  }

  /// [S13-5] What this app keeps on the phone (Settings → long-press the version): data and cache in MB, the biggest
  /// folders first, so a phone that shows "101 MB" can tell us what it is.
  Future<List<(String, double)>> storage() async {
    final out = <(String, double)>[];
    try {
      final cache = Directory(await installer.cacheDir()), root = cache.parent;
      for (final e in root.listSync().whereType<Directory>()) {
        var n = 0;
        for (final f in e.listSync(recursive: true, followLinks: false).whereType<File>()) { try { n += f.lengthSync(); } catch (_) {} }
        out.add((e.path.split(Platform.pathSeparator).last, n / 1048576));
      }
    } catch (_) {}
    return out..sort((a, b) => b.$2.compareTo(a.$2));
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
      context: context, backgroundColor: C.card, isScrollControlled: true, useSafeArea: true,
      builder: (_) => SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: head.copyWith(fontSize: 20)),
        const SizedBox(height: 10),
        for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $n')),
        const SizedBox(height: 8),
        Btn(L.of(context).ok, key: const Key('notesOk'), onTap: () => Navigator.of(context).pop()),
      ]))),
    );
