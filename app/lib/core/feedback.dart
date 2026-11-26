import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

/// A server error as the player reads it.
String errText(L l, Object e) => switch (e is ApiError ? e.code : '') {
      'offline' => l.eOffline, 'code' => l.eCode, 'slow_down' => l.eSlow, 'handle_taken' => l.eTaken, 'bad_request' => l.eOther,
      'not_found' => l.eNoUser, 'self' => l.eSelf, 'full' => l.eFull, 'mail' => l.eMail, 'google' => l.eGoogle,
      'too_big' => l.eTooBig, 'auth' => l.eSignedOut, 'banned' => l.eBanned, 'blocked' => l.eBlocked, _ => l.eOther,
    };

/// [1.1.1 hotfix] 2.5 s (was 4), and a tap puts it away: it never sits over the screen's buttons for long.
void toast(BuildContext context, String text, {bool error = false}) {
  final m = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2500),
      content: GestureDetector(onTap: m.hideCurrentSnackBar, child: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: error ? C.red2 : C.green, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: C.text))),
      ])),
      backgroundColor: C.card2));
}
/// [1.1.1 hotfix] a username someone else has: an alert, not a toast that's gone before it's read. True when shown.
bool takenAlert(BuildContext context, Object e, String handle) {
  if (e is! ApiError || e.code != 'handle_taken') return false;
  final l = L.of(context);
  showDialog<void>(context: context, builder: (c) => AlertDialog(
        key: const Key('handleTaken'),
        title: Text(l.eTaken, style: head.copyWith(fontSize: 20)),
        content: Text(l.eTakenD(handle.replaceFirst('@', '')), style: TextStyle(color: C.mute)),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(l.ok, style: TextStyle(color: C.red2, fontWeight: FontWeight.w700)))],
      ));
  return true;
}

/// A failure: the same message bar with the red mark.
void toastErr(BuildContext context, String text) => toast(context, text, error: true);

final handleRx = RegExp(r'^@?[A-Za-z0-9_.]{3,20}$');
