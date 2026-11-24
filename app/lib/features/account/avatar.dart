import 'package:flutter/material.dart';
import 'package:mafia_dealer/core/api.dart';
import 'package:mafia_dealer/core/ui.dart';
import 'package:mafia_dealer/state/models.dart';

// ---------------------------------------------------------------- avatar
/// 10 neutral presets (a color and a picture). No role symbols: in a hidden-role game a lobby of "Mafia" avatars misleads.
const avatarPresets = [
  (Color(0xFFC9C3D6), Icons.theater_comedy_outlined), (Color(0xFFB98BFF), Icons.nightlight_round), (Color(0xFF4DD4E0), Icons.visibility_outlined),
  (Color(0xFFFFC65A), Icons.workspace_premium_outlined), (Color(0xFFFF8A3D), Icons.key_outlined), (Color(0xFF5AA2FF), Icons.diamond_outlined),
  (Color(0xFFFF4D7D), Icons.local_florist_outlined), (Color(0xFF3CE0A0), Icons.music_note_outlined), (Color(0xFF9ADF5A), Icons.pets_outlined),
  (Color(0xFFE05A5A), Icons.casino_outlined),
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
    final (c, ic) = avatarPresets[i.clamp(0, 9)];
    return Container(color: c.withValues(alpha: .15), child: Icon(ic, color: c, size: size * .55));
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size, height: size,
        child: Stack(children: [
          Positioned.fill(child: ClipRRect(
            borderRadius: BorderRadius.circular(C.p.radius),
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
