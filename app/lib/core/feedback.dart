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

void toast(BuildContext context, String text, {bool error = false}) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: error ? C.red2 : C.green, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: C.text))),
      ]),
      backgroundColor: C.card2));
/// A failure: the same message bar with the red mark.
void toastErr(BuildContext context, String text) => toast(context, text, error: true);

final handleRx = RegExp(r'^@?[A-Za-z0-9_.]{3,20}$');
