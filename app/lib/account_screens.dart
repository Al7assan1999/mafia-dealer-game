// The account's screens: sign-in, choosing the @handle, profile and devices, friends, and the bell.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'account.dart';
import 'api.dart';
import 'l10n/app_localizations.dart';
import 'ui.dart';

/// A server error as the player reads it.
String errText(L l, Object e) => switch (e is ApiError ? e.code : '') {
      'offline' => l.eOffline, 'code' => l.eCode, 'slow_down' => l.eSlow, 'handle_taken' => l.eTaken, 'bad_request' => l.eOther,
      'not_found' => l.eNoUser, 'self' => l.eSelf, 'full' => l.eFull, 'mail' => l.eMail, 'google' => l.eGoogle,
      'too_big' => l.eTooBig, 'auth' => l.eSignedOut, _ => l.eOther,
    };

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(text), backgroundColor: C.card2));

final _handleRx = RegExp(r'^@?[A-Za-z0-9_.]{3,20}$');

// ---------------------------------------------------------------- avatar
/// The old app's 10 presets: a color and a picture.
const _presets = [
  (Color(0xFFFF4D7D), Icons.dangerous_outlined), (Color(0xFF3CE0A0), Icons.healing_outlined), (Color(0xFF5AA2FF), Icons.search),
  (Color(0xFFFFC65A), Icons.person_outline), (Color(0xFFB98BFF), Icons.nightlight_round), (Color(0xFFFF8A3D), Icons.workspace_premium_outlined),
  (Color(0xFF4DD4E0), Icons.visibility_outlined), (Color(0xFFE05A5A), Icons.mood_bad_outlined), (Color(0xFF9ADF5A), Icons.emoji_events_outlined),
  (Color(0xFFC9C3D6), Icons.groups_outlined),
];

class AvatarView extends StatelessWidget {
  const AvatarView({super.key, required this.api, required this.id, this.preset, this.photo, this.size = 40, this.online});
  AvatarView.of(this.api, Person p, {super.key, this.size = 40, this.online}) : id = p.id, preset = p.preset, photo = p.photo;
  final Api api;
  final String id;
  final int? preset, photo;
  final double size;
  final bool? online;

  Widget _preset(int i) {
    final (c, ic) = _presets[i.clamp(0, 9)];
    return Container(color: c.withValues(alpha: .15), child: Icon(ic, color: c, size: size * .55));
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size, height: size,
        child: Stack(children: [
          Positioned.fill(child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: photo != null
                ? Image.network(api.avatarUrl(id, photo!), fit: BoxFit.cover, errorBuilder: (_, _, _) => _preset(0))
                : _preset(preset ?? 0),
          )),
          if (online != null)
            PositionedDirectional(end: 0, bottom: 0, child: Container(width: size * .28, height: size * .28,
                decoration: BoxDecoration(color: online! ? C.green : C.dim, shape: BoxShape.circle, border: Border.all(color: C.bg, width: 2)))),
        ]),
      );
}

// ---------------------------------------------------------------- home bar
/// The top of the home screen: sign in, or my avatar + the friends and bell buttons.
class AccountBar extends StatelessWidget {
  const AccountBar({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: account, builder: (context, _) {
        final l = L.of(context), a = account;
        void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
        if (!a.signedIn) {
          return Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const Key('signIn'),
              onPressed: () => go(SignInScreen(account: a)), icon: const Icon(Icons.login, color: C.red2), label: Text(l.aIn, style: const TextStyle(color: C.red2))));
        }
        return Row(children: [
          InkWell(
            key: const Key('profile'),
            onTap: () => go(a.needsHandle ? HandleScreen(account: a) : ProfileScreen(account: a)),
            child: Row(children: [
              AvatarView.of(a.api, a.card!, size: 34),
              const SizedBox(width: 8),
              Text(a.handle != null ? '@${a.handle}' : a.display, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (a.offline) Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: Text(l.eOfflineShort, style: const TextStyle(color: C.dim, fontSize: 12))),
            ]),
          ),
          const Spacer(),
          IconButton(key: const Key('friends'), tooltip: l.friendsT, onPressed: () => go(FriendsScreen(account: a)),
              icon: Badge(isLabelVisible: a.incoming.isNotEmpty, label: Text('${a.incoming.length}'), child: const Icon(Icons.group_outlined, color: C.mute))),
          IconButton(key: const Key('bell'), tooltip: l.notifT, onPressed: () => showModalBottomSheet(context: context, backgroundColor: C.card, isScrollControlled: true, builder: (_) => BellSheet(account: a)),
              icon: Badge(isLabelVisible: a.unread > 0, label: Text('${a.unread}'), child: const Icon(Icons.notifications_none, color: C.mute))),
        ]);
      });
}

// ---------------------------------------------------------------- sign in
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.account});
  final Account account;
  @override
  State<SignInScreen> createState() => _SignInState();
}

class _SignInState extends State<SignInScreen> {
  final email = TextEditingController(), code = TextEditingController();
  String? sentTo, error;
  bool busy = false;
  int wait = 0;
  Timer? _t;

  @override
  void dispose() { _t?.cancel(); email.dispose(); code.dispose(); super.dispose(); }

  Future<void> _run(Future<void> Function() f) async {
    if (busy) return; // a second tap while the first is on its way
    setState(() { busy = true; error = null; });
    try { await f(); } catch (e) { if (mounted) setState(() => error = (e is ApiError && e.code == 'cancel') ? null : errText(L.of(context), e)); }
    if (mounted) setState(() => busy = false);
  }

  void _done() {
    if (!mounted) return;
    final a = widget.account;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => a.needsHandle ? HandleScreen(account: a) : ProfileScreen(account: a)));
  }

  Future<void> _send() => _run(() async {
        final e = email.text.trim().toLowerCase();
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) { setState(() => error = L.of(context).eEmail); return; }
        await widget.account.emailStart(e);
        setState(() { sentTo = e; wait = 60; });
        _t?.cancel();
        _t = Timer.periodic(const Duration(seconds: 1), (t) { if (!mounted || --wait <= 0) t.cancel(); if (mounted) setState(() {}); });
      });

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), a = widget.account;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.aIn, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, children: [
        Text(l.aWhy, style: const TextStyle(color: C.mute)),
        const SizedBox(height: 18),
        if (sentTo == null) ...[
          Btn(a.google.available ? l.aGoogle : l.aGoogleSoon, key: const Key('google'), icon: Icons.account_circle_outlined,
              onTap: a.google.available && !busy ? () => _run(() async { await a.signInGoogle(); _done(); }) : null),
          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(l.aOr, textAlign: TextAlign.center, style: const TextStyle(color: C.dim))),
          TextField(key: const Key('email'), controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: l.aEmail), onSubmitted: (_) => _send()),
          const SizedBox(height: 12),
          Btn(l.aEmailGo, key: const Key('sendCode'), ghost: true, onTap: busy ? null : _send),
        ] else ...[
          Text(l.aCodeSent(sentTo!), style: const TextStyle(color: C.mute)),
          const SizedBox(height: 12),
          TextField(key: const Key('code'), controller: code, keyboardType: TextInputType.number, maxLength: 6, autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(labelText: l.aCode, counterText: ''),
              style: head.copyWith(fontSize: 26, letterSpacing: 8)),
          const SizedBox(height: 12),
          Btn(l.aVerify, key: const Key('verify'), onTap: busy ? null : () => _run(() async {
                if (code.text.length != 6) { setState(() => error = l.eCode); return; }
                await a.emailVerify(sentTo!, code.text);
                _done();
              })),
          Row(children: [
            TextButton(key: const Key('resend'), onPressed: wait > 0 || busy ? null : _send, child: Text(wait > 0 ? l.aResendIn(wait) : l.aResend)),
            const Spacer(),
            TextButton(onPressed: () => setState(() { sentTo = null; code.clear(); error = null; }), child: Text(l.aOtherEmail, style: const TextStyle(color: C.mute))),
          ]),
        ],
        if (busy) const Padding(padding: EdgeInsets.only(top: 14), child: Center(child: CircularProgressIndicator(color: C.red2))),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(error!, key: const Key('error'), style: const TextStyle(color: C.red2))),
      ]),
    );
  }
}

/// A new account picks its @handle and display name first.
class HandleScreen extends StatefulWidget {
  const HandleScreen({super.key, required this.account});
  final Account account;
  @override
  State<HandleScreen> createState() => _HandleState();
}

class _HandleState extends State<HandleScreen> {
  late final handle = TextEditingController(text: widget.account.handle ?? ''), name = TextEditingController(text: widget.account.display);
  String? error;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), a = widget.account;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.aPickHandle, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, bottom: [
        Btn(l.aContinue, key: const Key('saveHandle'), onTap: busy ? null : () async {
          if (!_handleRx.hasMatch(handle.text.trim())) return setState(() => error = l.eHandle);
          if (name.text.trim().isEmpty) return setState(() => error = l.eBadName);
          setState(() { busy = true; error = null; });
          try {
            await a.patch({'handle': handle.text.trim(), 'display': name.text.trim()});
            if (context.mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ProfileScreen(account: a)));
          } catch (e) {
            if (mounted) setState(() => error = errText(l, e));
          }
          if (mounted) setState(() => busy = false);
        }),
      ], children: [
        Text(l.aPickHandleD, style: const TextStyle(color: C.mute)),
        const SizedBox(height: 14),
        TextField(key: const Key('handle'), controller: handle, maxLength: 21, decoration: InputDecoration(labelText: l.aUser, prefixText: '@', counterText: '')),
        const SizedBox(height: 12),
        TextField(key: const Key('display'), controller: name, maxLength: 18, decoration: InputDecoration(labelText: l.aName, counterText: '')),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, key: const Key('error'), style: const TextStyle(color: C.red2))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- profile
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.account});
  final Account account;
  /// Tests replace the gallery with a fake picture.
  static Future<Uint8List?> Function()? testPicker;
  @override
  State<ProfileScreen> createState() => _ProfileState();
}

/// Crops a picture to a square, 256 px, and makes it a JPEG of at most 150 KB (null when it can't be read).
Uint8List? squareJpeg(Uint8List bytes) {
  final i = img.decodeImage(bytes);
  if (i == null) return null;
  final sq = img.copyResizeCropSquare(i, size: 256);
  for (var q = 85; q >= 40; q -= 15) {
    final out = img.encodeJpg(sq, quality: q);
    if (out.length <= 150000) return out;
  }
  return null;
}

class _ProfileState extends State<ProfileScreen> {
  late final a = widget.account;
  late final handle = TextEditingController(text: a.handle ?? ''), name = TextEditingController(text: a.display);
  late String fav = (a.me?['fav'] as String?) ?? '';
  late bool showOn = a.me?['showOnline'] != false;
  List<Map<String, Object?>>? devices;
  bool busy = false;

  @override
  void initState() { super.initState(); _loadDevices(); }
  Future<void> _loadDevices() async { try { final d = await a.sessions(); if (mounted) setState(() => devices = d); } catch (_) {} }

  Future<void> _do(Future<void> Function() f, [String? ok]) async {
    if (busy) return;
    setState(() => busy = true);
    final l = L.of(context);
    try { await f(); if (ok != null && mounted) toast(context, ok); } catch (e) { if (mounted) toast(context, errText(l, e)); }
    if (mounted) setState(() => busy = false);
  }

  Future<Uint8List?> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
    return f == null ? null : await f.readAsBytes();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: a, builder: (context, _) {
        final l = L.of(context);
        if (!a.signedIn) return Scaffold(appBar: AppBar(backgroundColor: C.bg), body: Stage(children: [Big(l.aDeleted)]));
        return Scaffold(
          appBar: AppBar(backgroundColor: C.bg, title: Text(l.profT, style: head.copyWith(fontSize: 20))),
          body: Stage(center: false, children: [
            Sec(title: l.aAvatar, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < 10; i++)
                  InkWell(key: Key('preset$i'), onTap: () => _do(() => a.avatarPreset(i)),
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: a.card!.photo == null && a.card!.preset == i ? C.red : Colors.transparent, width: 2), borderRadius: BorderRadius.circular(6)),
                        child: AvatarView(api: a.api, id: a.card!.id, preset: i, size: 44))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                AvatarView.of(a.api, a.card!, size: 56),
                const SizedBox(width: 12),
                OutlinedButton.icon(key: const Key('photo'), icon: const Icon(Icons.photo_outlined), label: Text(l.aPhoto),
                    onPressed: busy ? null : () => _do(() async {
                          final raw = await (ProfileScreen.testPicker ?? _pick)();
                          if (raw == null) return;
                          final jpeg = squareJpeg(raw);
                          if (jpeg == null) throw ApiError('avatar');
                          await a.avatarPhoto(jpeg);
                        })),
              ]),
            ])),
            Sec(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(key: const Key('handle'), controller: handle, maxLength: 21, decoration: InputDecoration(labelText: l.aUser, prefixText: '@', counterText: '')),
              const SizedBox(height: 10),
              TextField(key: const Key('display'), controller: name, maxLength: 18, decoration: InputDecoration(labelText: l.aName, counterText: '')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: const Key('fav'), initialValue: fav, decoration: InputDecoration(labelText: l.aFav),
                items: [
                  for (final (k, t) in [('', l.aNone), ('mafia', l.mafia), ('doctor', l.doctor), ('detective', l.detective), ('citizen', l.citizen)])
                    DropdownMenuItem(value: k, child: Text(t)),
                ],
                onChanged: (v) => setState(() => fav = v ?? ''),
              ),
              SwitchListTile(key: const Key('showOnline'), contentPadding: EdgeInsets.zero, value: showOn, onChanged: (v) => setState(() => showOn = v),
                  title: Text(l.fShowOn), subtitle: Text(l.fShowOnD, style: const TextStyle(color: C.dim, fontSize: 12))),
              Btn(l.aSave, key: const Key('saveProfile'), onTap: busy ? null : () {
                if (!_handleRx.hasMatch(handle.text.trim())) return toast(context, l.eHandle);
                if (name.text.trim().isEmpty) return toast(context, l.eBadName);
                _do(() => a.patch({'handle': handle.text.trim(), 'display': name.text.trim(), 'fav': fav, 'showOnline': showOn}), l.aSaved);
              }),
            ])),
            Sec(title: l.aDevices, child: Column(children: [
              for (final d in devices ?? const <Map<String, Object?>>[])
                Row(children: [
                  const Icon(Icons.smartphone, color: C.mute, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${d['device']}${d['current'] == true ? ' · ${l.aThisDevice}' : ''}')),
                  TextButton(onPressed: () => _do(() async {
                        await a.endSession(d['id'] as String, current: d['current'] == true);
                        await _loadDevices();
                      }), child: Text(l.aSignOutDevice, style: const TextStyle(color: C.red2))),
                ]),
            ])),
            Btn(l.aOut, key: const Key('signOut'), ghost: true, icon: Icons.logout, onTap: () async {
              if (await ask(context, l.aOutQ, l.aOutD, l.aOut)) {
                await a.logout();
                if (context.mounted) Navigator.of(context).pop();
              }
            }),
            const SizedBox(height: 12),
            TextButton(key: const Key('deleteAccount'), onPressed: () => _confirmDelete(l), child: Text(l.aDel, style: const TextStyle(color: C.red2))),
          ]),
        );
      });

  Future<void> _confirmDelete(L l) async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
          title: Text(l.aDelQ, style: head.copyWith(fontSize: 20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(l.aDelD, style: const TextStyle(color: C.mute)),
            const SizedBox(height: 10),
            TextField(key: const Key('typeDelete'), controller: typed, onChanged: (_) => set(() {}), decoration: const InputDecoration(hintText: 'delete')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel, style: const TextStyle(color: C.mute))),
            TextButton(key: const Key('confirmDelete'), onPressed: typed.text.trim().toLowerCase() == 'delete' ? () => Navigator.pop(c, true) : null,
                child: Text(l.aDel, style: const TextStyle(color: C.red2, fontWeight: FontWeight.w700))),
          ],
        )));
    if (ok != true || !mounted) return;
    await _do(() async {
      await a.deleteAccount();
      if (mounted) { toast(context, l.aDeleted); Navigator.of(context).pop(); }
    });
  }
}

// ---------------------------------------------------------------- friends
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.account});
  final Account account;
  @override
  State<FriendsScreen> createState() => _FriendsState();
}

class _FriendsState extends State<FriendsScreen> {
  late final a = widget.account;
  final add = TextEditingController();
  bool busy = false;

  @override
  void initState() { super.initState(); if (a.signedIn) a.loadFriends().catchError((_) {}); }

  Future<void> _do(Future<void> Function() f) async {
    if (busy) return;
    setState(() => busy = true);
    final l = L.of(context);
    try { await f(); } catch (e) { if (mounted) toast(context, errText(l, e)); }
    if (mounted) setState(() => busy = false);
  }

  String _status(L l, Person p) => !p.online ? l.fOffline : p.status == 'game' ? l.fInGame : p.status == 'lobby' ? l.fInRoom : l.fOnline;

  Widget _row(Person p, List<Widget> actions, {String? sub}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          AvatarView.of(a.api, p, size: 40, online: sub != null ? p.online : null),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.display, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text([if (p.handle != null) '@${p.handle}', ?sub].join(' · '), style: const TextStyle(color: C.mute, fontSize: 12)),
          ])),
          ...actions,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    if (!a.signedIn) {
      return Scaffold(appBar: AppBar(backgroundColor: C.bg, title: Text(l.friendsT, style: head.copyWith(fontSize: 20))),
          body: Stage(children: [Big(l.friendsT, sub: l.fWhy), const SizedBox(height: 18), Btn(l.aIn, onTap: () =>
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SignInScreen(account: a))))]));
    }
    return ListenableBuilder(listenable: a, builder: (context, _) => DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: C.bg,
              title: Text(l.friendsT, style: head.copyWith(fontSize: 20)),
              actions: [
                if (a.handle != null)
                  IconButton(key: const Key('share'), tooltip: l.fShareMe, icon: const Icon(Icons.share_outlined),
                      onPressed: () => SharePlus.instance.share(ShareParams(text: l.fShareTxt(a.handle!)))),
              ],
              bottom: TabBar(indicatorColor: C.red, labelColor: C.text, unselectedLabelColor: C.mute, tabs: [
                Tab(text: '${l.fTabF} (${a.friends.length})'),
                Tab(key: const Key('tabRequests'), text: '${l.fTabR} (${a.incoming.length})'),
                Tab(key: const Key('tabSent'), text: '${l.fTabS} (${a.outgoing.length})'),
              ]),
            ),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Expanded(child: TextField(key: const Key('addHandle'), controller: add, decoration: InputDecoration(hintText: l.fAdd, prefixText: '@'))),
                  const SizedBox(width: 8),
                  FilledButton(key: const Key('addFriend'), style: FilledButton.styleFrom(backgroundColor: C.red), onPressed: busy ? null : () {
                    final h = add.text.trim();
                    if (!_handleRx.hasMatch(h)) return toast(context, l.eHandle);
                    _do(() async {
                      final rel = await a.request(h);
                      add.clear();
                      if (context.mounted) toast(context, rel == 'friends' ? l.fNowFriends('@${h.replaceFirst('@', '')}') : l.fReqSent('@${h.replaceFirst('@', '')}'));
                    });
                  }, child: Text(l.fAddBtn)),
                ]),
              ),
              if (a.offline) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.eOffline, style: const TextStyle(color: C.red2))),
              Expanded(child: TabBarView(children: [
                _list(l.fNone, [for (final p in a.friends) _row(p, [
                  if (a.roomCode != null && p.status != 'lobby' && p.status != 'game')
                    TextButton(onPressed: () => _do(() async { await a.invite(p.id, a.roomCode!); if (context.mounted) toast(context, l.invited); }),
                        child: Text(l.invite, style: const TextStyle(color: C.red2)))
                  else if (p.j['op'] == true && a.roomCode == null)
                    TextButton(key: Key('askJoin_${p.handle}'), onPressed: () => _do(() async { await a.askToJoin(p.id); if (context.mounted) toast(context, l.asked); }),
                        child: Text(l.askJoin, style: const TextStyle(color: C.red2))),
                  IconButton(tooltip: l.fRemove, icon: const Icon(Icons.person_remove_outlined, color: C.dim), onPressed: () async {
                    if (await ask(context, l.fRemoveQ(p.display), l.fRemoveD, l.fRemove)) _do(() => a.unfriend(p.id));
                  }),
                ], sub: _status(l, p))]),
                _list(l.fNoReq, [for (final p in a.incoming) _row(p, [
                  TextButton(key: Key('accept_${p.handle}'), onPressed: () => _do(() => a.accept(p.id)), child: Text(l.fAccept, style: const TextStyle(color: C.green))),
                  TextButton(onPressed: () => _do(() => a.decline(p.id)), child: Text(l.fDecline, style: const TextStyle(color: C.mute))),
                ])]),
                _list(l.fNoSent, [for (final p in a.outgoing) _row(p, [
                  TextButton(onPressed: () => _do(() => a.decline(p.id)), child: Text(l.fCancelReq, style: const TextStyle(color: C.mute))),
                ])]),
              ])),
            ]),
          ),
        ));
  }

  Widget _list(String empty, List<Widget> rows) => RefreshIndicator(
        onRefresh: () => a.loadFriends().catchError((_) {}),
        child: ListView(padding: const EdgeInsets.all(16), children: rows.isEmpty ? [Text(empty, style: const TextStyle(color: C.mute))] : rows),
      );
}

// ---------------------------------------------------------------- the bell
class BellSheet extends StatefulWidget {
  const BellSheet({super.key, required this.account});
  final Account account;
  @override
  State<BellSheet> createState() => _BellState();
}

class _BellState extends State<BellSheet> {
  @override
  void initState() { super.initState(); widget.account.loadNotes().then((_) => widget.account.readAll()).catchError((_) {}); }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.account, builder: (context, _) {
        final l = L.of(context), a = widget.account;
        final notes = a.notes;
        return SafeArea(child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
          child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(l.notifT, style: head.copyWith(fontSize: 22))),
              if (notes.isNotEmpty) TextButton(key: const Key('clearNotes'), onPressed: () => a.deleteNote(null).catchError((_) {}), child: Text(l.nClear, style: const TextStyle(color: C.mute))),
            ]),
            if (notes.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text(l.nNone, style: const TextStyle(color: C.mute))),
            Flexible(child: ListView(shrinkWrap: true, children: [
              for (final n in notes)
                ListTile(
                  key: Key('note_${n.id}'), contentPadding: EdgeInsets.zero,
                  leading: AvatarView.of(a.api, n.from, size: 36),
                  title: Text(n.from.display, style: TextStyle(fontWeight: n.read ? FontWeight.w400 : FontWeight.w700)),
                  subtitle: Text(switch (n.kind) {
                    'friend_request' => l.nReq, 'friend_accept' => l.nAcc, 'invite' => l.nInvite(n.code ?? ''),
                    'let_in' => l.nLetIn(n.code ?? ''), _ => l.nJoinReq,
                  }, style: const TextStyle(color: C.mute)),
                  trailing: n.kind == 'join_request' && a.roomCode != null
                      ? TextButton(key: Key('letIn_${n.from.handle}'), onPressed: () async {
                          try { await a.invite(n.from.id, a.roomCode!); await a.deleteNote(n.id); } catch (e) { if (context.mounted) toast(context, errText(l, e)); }
                        }, child: Text(l.letIn, style: const TextStyle(color: C.green)))
                      : IconButton(icon: const Icon(Icons.close, color: C.dim), onPressed: () => a.deleteNote(n.id).catchError((_) {})),
                  onTap: () {
                    Navigator.of(context).pop();
                    if ((n.kind == 'invite' || n.kind == 'let_in') && n.code != null && a.openRoom != null) return a.openRoom!(n.code!);
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FriendsScreen(account: a)));
                  },
                ),
            ])),
          ])),
        ));
      });
}
