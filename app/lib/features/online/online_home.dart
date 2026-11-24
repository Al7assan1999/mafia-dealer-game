import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/audio.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/prefs.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/sign_in_screen.dart';
import 'package:mafia_dealer/features/room/room_screen.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

// ---------------------------------------------------------------- create / join
class OnlineHome extends StatefulWidget {
  const OnlineHome({super.key, required this.account, required this.prefs, required this.audio});
  final Account account;
  final Prefs prefs;
  final Audio audio;
  @override
  State<OnlineHome> createState() => _OnlineHomeState();
}

class _OnlineHomeState extends State<OnlineHome> {
  final code = TextEditingController();
  bool busy = false;
  String? error;

  void _open(String c) => Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => RoomScreen(account: widget.account, prefs: widget.prefs, audio: widget.audio, code: c)));

  @override
  void initState() { super.initState(); code.addListener(() { if (mounted) setState(() => error = null); }); }
  @override
  void dispose() { code.dispose(); super.dispose(); }

  /// [S12-2] A code with no open room is answered here, not by opening an empty room screen.
  Future<void> _join() async {
    final l = L.of(context), c = code.text;
    setState(() { busy = true; error = null; });
    try {
      await widget.account.api.get('/v1/rooms/$c');
      if (mounted) _open(c);
    } catch (e) {
      if (mounted) setState(() => error = e is ApiError && e.code == 'no_room' ? l.eNoRoom : errText(l, e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), a = widget.account;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.bg, title: Text(l.online, style: head.copyWith(fontSize: 20))),
      body: Stage(center: false, children: [
        Text(l.onlineSub, style: TextStyle(color: C.mute)),
        const SizedBox(height: 18),
        if (!a.signedIn) ...[
          Text(l.onlineNeedsAccount),
          const SizedBox(height: 12),
          Btn(l.aIn, onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SignInScreen(account: a)))),
        ] else ...[
          Btn(l.createRoom, key: const Key('createRoom'), icon: Icons.add_home_outlined, onTap: busy ? null : () async {
            setState(() { busy = true; error = null; });
            try { _open(await a.createRoom()); } catch (e) { if (mounted) setState(() => error = errText(l, e)); }
            if (mounted) setState(() => busy = false);
          }),
          const SizedBox(height: 22),
          Text(l.joinCode, style: head.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(key: const Key('roomCode'), controller: code, maxLength: 6, keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(hintText: l.codeHint, counterText: '', helperText: code.text.isNotEmpty && code.text.length < 6 ? l.code6 : null),
                style: head.copyWith(fontSize: 22, letterSpacing: 6))),
            const SizedBox(width: 10),
            FilledButton(key: const Key('joinRoom'), style: FilledButton.styleFrom(backgroundColor: C.red),
                onPressed: code.text.length == 6 && !busy ? _join : null, child: Text(l.join)), // S12-2: off until 6 digits
          ]),
        ],
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, key: const Key('error'), style: TextStyle(color: C.red2))),
      ]),
    );
  }
}
