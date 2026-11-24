import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

/// The role card: hidden until pressed and held; hidden again on release or when the app goes to the background.
/// The button waits for one look. Used offline (pass the phone) and online (my own phone).
class RoleCard extends StatefulWidget {
  const RoleCard({super.key, required this.name, required this.role, required this.mates, required this.done, required this.onDone, this.extra = const []});
  final String name, done;
  final Role role;
  final List<String> mates;
  final VoidCallback? onDone;
  final List<Widget> extra; // more buttons under it (online: the host's Start)
  @override
  State<RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<RoleCard> with WidgetsBindingObserver {
  bool show = false, seen = false;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) { if (s != AppLifecycleState.resumed && show) setState(() => show = false); }

  void _hold(bool on) => setState(() { show = on; if (on) seen = true; });

  @override
  Widget build(BuildContext context) {
    final l = L.of(context), role = widget.role;
    final desc = switch (role) { Role.mafia => l.dMafia, Role.doctor => l.dDoctor, Role.detective => l.dDetective, Role.citizen => l.dCitizen };
    return Stage(bottom: [
      Btn(widget.done, key: const Key('memorized'), onTap: seen && !show ? widget.onDone : null),
      ...widget.extra,
    ], children: [
      Text(widget.name, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16)),
      Text(l.yourRole.toUpperCase(), textAlign: TextAlign.center, style: head.copyWith(color: C.dim, letterSpacing: 3)),
      const SizedBox(height: 16),
      // [S12-6] TalkBack: "double-tap and hold" reveals (and again hides) the role; touch keeps press-and-hold
      Semantics(button: true, label: show ? roleName(l, role) : l.holdHint, onLongPress: () => _hold(!show), child: Listener(
        key: const Key('roleCard'),
        onPointerDown: (_) => _hold(true),
        onPointerUp: (_) => _hold(false),
        onPointerCancel: (_) => _hold(false),
        child: AspectRatio(
          aspectRatio: .75,
          child: Container(
            decoration: BoxDecoration(
              color: show ? C.alt : C.card2,
              border: Border.all(color: show ? roleColor(role) : C.line2, width: 2),
              borderRadius: BorderRadius.circular(C.p.radius),
              boxShadow: [BoxShadow(color: C.red, offset: Offset(4, 4))],
            ),
            padding: const EdgeInsets.all(20),
            child: show
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(roleIcon(role), size: 64, color: role == Role.citizen ? const Color(0xFF8A6A30) : roleColor(role)),
                    const SizedBox(height: 12),
                    Text(roleName(l, role), key: const Key('roleName'), style: head.copyWith(fontSize: 34, color: C.altText)),
                    const SizedBox(height: 8),
                    Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF5A5248))),
                    if (widget.mates.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12),
                        child: Text(l.mates(widget.mates.join(', ')), textAlign: TextAlign.center, style: TextStyle(color: C.red, fontWeight: FontWeight.w700))),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.visibility_off_outlined, size: 54, color: C.mute),
                    const SizedBox(height: 12),
                    Text(l.holdHint, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16)),
                  ]),
          ),
        ),
      )),
    ]);
  }
}
