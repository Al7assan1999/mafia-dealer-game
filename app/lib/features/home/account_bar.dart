import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/account/avatar.dart';
import 'package:mafia_dealer/features/account/profile_screen.dart';
import 'package:mafia_dealer/features/account/sign_in_screen.dart';
import 'package:mafia_dealer/features/friends/friends_screen.dart';
import 'package:mafia_dealer/features/notifications/bell_sheet.dart';
import 'package:mafia_dealer/state/account.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

// ---------------------------------------------------------------- home top row
/// [S15-1 / his note] Home's top row as in 0.4.6 (he preferred it to the old app's boxes): sign in, or my avatar and
/// @handle at the start; the friends and bell icons and the Settings gear at the end. Language and look are in Settings.
class AccountBar extends StatelessWidget {
  const AccountBar({super.key, required this.account, required this.onSettings});
  final Account account;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: account, builder: (context, _) {
        final l = L.of(context), a = account;
        void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
        final gear = IconButton(key: const Key('settings'), tooltip: l.settingsT, icon: Icon(Icons.settings_outlined, color: C.mute), onPressed: onSettings);
        if (!a.signedIn) {
          return Row(children: [
            TextButton.icon(key: const Key('signIn'), onPressed: () => go(SignInScreen(account: a)), icon: Icon(Icons.login, color: C.red2), label: Text(l.aIn, style: TextStyle(color: C.red2))),
            const Spacer(),
            gear,
          ]);
        }
        return Row(children: [
          Flexible(child: InkWell(
            key: const Key('profile'),
            onTap: () => go(a.needsHandle ? HandleScreen(account: a) : ProfileScreen(account: a)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AvatarView.of(a.api, a.card!, size: 34),
              const SizedBox(width: 8),
              Flexible(child: Text(a.handle != null ? atHandle(a.handle) : a.display, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (a.offline) Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: Text(l.eOfflineShort, style: TextStyle(color: C.dim, fontSize: 12))),
            ]),
          )),
          const Spacer(),
          IconButton(key: const Key('friends'), tooltip: l.friendsT, onPressed: () => go(FriendsScreen(account: a)),
              icon: Badge(isLabelVisible: a.incoming.isNotEmpty, label: Text('${a.incoming.length}'), child: Icon(Icons.group_outlined, color: C.mute))),
          IconButton(key: const Key('bell'), tooltip: l.notifT, onPressed: () => showModalBottomSheet(context: context, backgroundColor: C.card, isScrollControlled: true, useSafeArea: true, builder: (_) => BellSheet(account: a)),
              icon: Badge(isLabelVisible: a.unread > 0, label: Text('${a.unread}'), child: Icon(Icons.notifications_none, color: C.mute))),
          gear,
        ]);
      });
}

/// The old app's mark: a hat and a moustache. Noir: red lines in a tilted red square. Neon: white lines on the
/// pink-orange tile with a glow.
class HomeLogo extends StatelessWidget {
  const HomeLogo({super.key});
  @override
  Widget build(BuildContext context) {
    final mark = HatMark(size: 48, color: C.neon ? Colors.white : C.red);
    if (C.neon) {
      return Container(width: 86, height: 86, alignment: Alignment.center,
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF2E63), Color(0xFFFF8A3D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x50FF2E63), blurRadius: 30, offset: Offset(0, 12))]),
          child: mark);
    }
    return Transform.rotate(angle: -.105, child: Container(width: 86, height: 86, alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: C.red, width: 2), borderRadius: BorderRadius.circular(6)), child: mark));
  }
}
