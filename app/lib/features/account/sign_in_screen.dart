import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/feedback.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/profile_screen.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

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
        Text(l.aWhy, style: TextStyle(color: C.mute)),
        const SizedBox(height: 18),
        if (sentTo == null) ...[
          Btn(a.google.available ? l.aGoogle : l.aGoogleSoon, key: const Key('google'), icon: Icons.account_circle_outlined,
              onTap: a.google.available && !busy ? () => _run(() async { await a.signInGoogle(); _done(); }) : null),
          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(l.aOr, textAlign: TextAlign.center, style: TextStyle(color: C.dim))),
          TextField(key: const Key('email'), controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: l.aEmail), onSubmitted: (_) => _send()),
          const SizedBox(height: 12),
          Btn(l.aEmailGo, key: const Key('sendCode'), ghost: true, onTap: busy ? null : _send),
        ] else ...[
          Text(l.aCodeSent(sentTo!), style: TextStyle(color: C.mute)),
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
            TextButton(onPressed: () => setState(() { sentTo = null; code.clear(); error = null; }), child: Text(l.aOtherEmail, style: TextStyle(color: C.mute))),
          ]),
        ],
        if (busy) Padding(padding: EdgeInsets.only(top: 14), child: Center(child: CircularProgressIndicator(color: C.red2))),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(error!, key: const Key('error'), style: TextStyle(color: C.red2))),
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
          if (!handleRx.hasMatch(handle.text.trim())) return setState(() => error = l.eHandle);
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
        Text(l.aPickHandleD, style: TextStyle(color: C.mute)),
        const SizedBox(height: 14),
        TextField(key: const Key('handle'), controller: handle, maxLength: 21, decoration: InputDecoration(labelText: l.aUser, prefixText: '@', counterText: '')),
        const SizedBox(height: 12),
        TextField(key: const Key('display'), controller: name, maxLength: 18, decoration: InputDecoration(labelText: l.aName, counterText: '')),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, key: const Key('error'), style: TextStyle(color: C.red2))),
      ]),
    );
  }
}
