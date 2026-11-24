import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/avatar.dart';
import 'package:mafia_dealer/features/account/profile_screen.dart';
import 'package:mafia_dealer/features/account/sign_in_screen.dart';
import 'package:mafia_dealer/features/friends/friends_screen.dart';
import 'package:mafia_dealer/features/notifications/bell_sheet.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

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
              onPressed: () => go(SignInScreen(account: a)), icon: Icon(Icons.login, color: C.red2), label: Text(l.aIn, style: TextStyle(color: C.red2))));
        }
        return Row(children: [
          InkWell(
            key: const Key('profile'),
            onTap: () => go(a.needsHandle ? HandleScreen(account: a) : ProfileScreen(account: a)),
            child: Row(children: [
              AvatarView.of(a.api, a.card!, size: 34),
              const SizedBox(width: 8),
              Text(a.handle != null ? atHandle(a.handle) : a.display, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (a.offline) Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: Text(l.eOfflineShort, style: TextStyle(color: C.dim, fontSize: 12))),
            ]),
          ),
          const Spacer(),
          IconButton(key: const Key('friends'), tooltip: l.friendsT, onPressed: () => go(FriendsScreen(account: a)),
              icon: Badge(isLabelVisible: a.incoming.isNotEmpty, label: Text('${a.incoming.length}'), child: Icon(Icons.group_outlined, color: C.mute))),
          IconButton(key: const Key('bell'), tooltip: l.notifT, onPressed: () => showModalBottomSheet(context: context, backgroundColor: C.card, isScrollControlled: true, useSafeArea: true, builder: (_) => BellSheet(account: a)),
              icon: Badge(isLabelVisible: a.unread > 0, label: Text('${a.unread}'), child: Icon(Icons.notifications_none, color: C.mute))),
        ]);
      });
}
