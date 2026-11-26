import 'package:flutter/material.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/features/offline/recap_card.dart';
import 'package:mafia_dealer/l10n/app_localizations.dart';

/// The role card: hidden until pressed and held; hidden again on release or when the app goes to the background.
/// The button waits for one look. Used offline (pass the phone) and online (my own phone).
class RoleCard extends StatefulWidget {
  const RoleCard({super.key, required this.name, required this.role, required this.mates, required this.done, required this.onDone, this.extra = const [], this.foot,
      this.sheikh, this.isSheikh = false, this.framer, this.isFramer = false});
  final String? sheikh; // [S17] Mafia: the Godfather's name (another Mafia)
  final bool isSheikh; // this player is the Godfather
  final String? framer; // [S20] Mafia: the Framer's name (another Mafia)
  final bool isFramer; // this player is the Framer
  final String? foot; // [S14-6] "Round 1 · 6/6 alive" under the card
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
    final desc = widget.isSheikh ? l.youSheikh : widget.isFramer ? l.dFramer : roleDesc(l, role);
    return Stage(card: true, foot: widget.foot, bottom: [
      Btn(widget.done, key: const Key('memorized'), ghost: true, onTap: seen && !show ? widget.onDone : null), // outlined, as the old app
      ...widget.extra,
    ], children: [
      // [S14-6] as the old app: "DAREER · YOUR SECRET ROLE" in small caps, a wide card, the role on paper with a stamp
      Text('${widget.name} · ${l.yourRole}'.toUpperCase(), textAlign: TextAlign.center, style: capStyle.copyWith(fontSize: 14)),
      const SizedBox(height: 16),
      // [S12-6] TalkBack: "double-tap and hold" reveals (and again hides) the role; touch keeps press-and-hold
      Semantics(button: true, label: show ? roleName(l, role) : l.holdHint, onLongPress: () => _hold(!show), child: Listener(
        key: const Key('roleCard'),
        onPointerDown: (_) => _hold(true),
        onPointerUp: (_) => _hold(false),
        onPointerCancel: (_) => _hold(false),
        child: AspectRatio(
          aspectRatio: 1.45,
          child: Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: show ? C.alt : Color.lerp(C.bg, C.card, .5),
              border: show ? null : Border.all(color: C.line2),
              borderRadius: BorderRadius.circular(C.neon ? 18 : 3),
              boxShadow: show ? const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 8))] : null,
            ),
            padding: const EdgeInsets.all(16),
            child: show
                ? Stack(children: [
                  if (!C.neon) PositionedDirectional(top: 4, end: -6, child: Transform.rotate(angle: .2, child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(border: Border.all(color: C.red, width: 2)),
                      child: Text(l.classified, style: head.copyWith(color: C.red, fontSize: 13))))),
                  LayoutBuilder(builder: (context, box) => Center(child: FittedBox(fit: BoxFit.scaleDown, child: SizedBox(width: box.maxWidth, child: Column(mainAxisSize: MainAxisSize.min, children: [ // large text: shrinks, never cut; lines still wrap
                    Container(width: 56, height: 56, alignment: Alignment.center,
                        decoration: BoxDecoration(color: _ink(role).withValues(alpha: .12), borderRadius: BorderRadius.circular(C.neon ? 14 : 3)),
                        child: Icon(roleIcon(role), size: 28, color: _ink(role))),
                    const SizedBox(height: 10),
                    Text(seatRole(l, role, widget.isSheikh, framer: widget.isFramer), key: const Key('roleName'), style: head.copyWith(fontSize: 38, color: _ink(role))),
                    const SizedBox(height: 8),
                    Text(desc, textAlign: TextAlign.center, style: TextStyle(color: C.neon ? C.mute : const Color(0xFF3A342C), fontSize: 15)),
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(sideLine(l, role), key: const Key('sideLine'), textAlign: TextAlign.center,
                        style: TextStyle(color: C.neon ? C.mute : const Color(0xFF5A5248), fontSize: 13, fontWeight: FontWeight.w700))),
                    if (widget.mates.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10),
                        child: Text(l.mates(widget.mates.join(', ')), textAlign: TextAlign.center, style: TextStyle(color: C.red, fontWeight: FontWeight.w700))),
                    if (widget.sheikh != null) Padding(padding: const EdgeInsets.only(top: 4),
                        child: Text(l.sheikhIs(widget.sheikh!), key: const Key('sheikhIs'), textAlign: TextAlign.center, style: TextStyle(color: C.red, fontWeight: FontWeight.w700))),
                    if (widget.framer != null) Padding(padding: const EdgeInsets.only(top: 4),
                        child: Text(l.framerIs(widget.framer!), key: const Key('framerIs'), textAlign: TextAlign.center, style: TextStyle(color: C.red, fontWeight: FontWeight.w700))),
                  ]))))),
                ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.visibility_outlined, size: 40, color: C.mute),
                    const SizedBox(height: 12),
                    Text(l.holdHint, textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
          ),
        ),
      )),
    ]);
  }
}

// [Quin Q11] Noir's card is paper: the role's name in the recap's paper ink (4.5:1 or more), as S16-5 did for the recap
Color _ink(Role r) => C.neon ? roleColor(r) : RecapCard.paperInk[r]!;
