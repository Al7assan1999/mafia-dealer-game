import 'package:flutter/material.dart';

String pct(num w, num g) => g == 0 ? '–' : '${(w / g * 100).round()}%';

/// Tiles two per row, each row as tall as its tallest tile ([QA] S8 #1: a fixed-ratio grid cut the text off).
Widget pairs(List<Widget> tiles) => Column(children: [
      for (var i = 0; i < tiles.length; i += 2)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: tiles[i]),
          const SizedBox(width: 8),
          Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
        ]))),
    ]);

/// The filters every stats view shares (S13-1: no more "Mine": one board for everyone).
class StatsFilter {
  const StatsFilter({this.source = 'all', this.days = 0});
  final String source;
  final int days;
  StatsFilter copy({String? source, int? days}) => StatsFilter(source: source ?? this.source, days: days ?? this.days);
}
