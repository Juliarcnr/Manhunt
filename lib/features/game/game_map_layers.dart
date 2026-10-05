import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/round/ping_schedule.dart';
import '../../theme/app_theme.dart';
import '../map/base_map.dart';

/// Last ping of every player as a location pin with the name above
/// (R-HUNT-03). Caught players are greyed out.
/// Colour per player, stable for the round: by join order (R-HUNT-03).
Map<String, Color> playerColors(List<String> playerIds) => {
  for (final (i, id) in playerIds.indexed)
    id: AppColors.playerPalette[i % AppColors.playerPalette.length],
};

/// Last ping of every player as a location pin with the name above, in the
/// player's own colour (R-HUNT-03). A speedhunt ping gets a bolt badge;
/// caught players are greyed out.
MarkerLayer lastPingsLayer({
  required Map<String, List<PingRecord>> byPlayer,
  required Map<String, String> names,
  required Set<String> caught,
  required Map<String, Color> colors,
}) => MarkerLayer(
  markers: [
    for (final entry in byPlayer.entries)
      if (entry.value.isNotEmpty)
        Marker(
          key: Key('lastPing_${entry.key}'),
          point: entry.value.last.fix.point.toLatLng(),
          width: 140,
          height: 64,
          alignment: Alignment.topCenter,
          child: _NamedPin(
            name: names[entry.key] ?? '?',
            color: caught.contains(entry.key)
                ? AppColors.textMuted
                : colors[entry.key] ?? AppColors.player,
            icon: Icons.location_on,
            speedhunt: entry.value.last.kind == PingKind.speedhunt,
          ),
        ),
  ],
);

/// Live positions of hunters (R-HUNT-02) or a joker snapshot (R-PLAY-02).
MarkerLayer huntersLayer({
  required Map<String, LocationFix> positions,
  required Map<String, String> names,
}) => MarkerLayer(
  markers: [
    for (final entry in positions.entries)
      Marker(
        key: Key('hunter_${entry.key}'),
        point: entry.value.point.toLatLng(),
        width: 140,
        height: 64,
        alignment: Alignment.topCenter,
        child: _NamedPin(
          name: names[entry.key] ?? '?',
          color: AppColors.hunter,
          icon: Icons.track_changes,
        ),
      ),
  ],
);

/// A player's own pings, numbered 1, 2, 3 … (R-PLAY-01, R-HUNT-04).
MarkerLayer historyLayer(List<PingRecord> pings, {required Color color}) =>
    MarkerLayer(
      markers: [
        for (final (i, p) in pings.indexed)
          Marker(
            key: Key('history_${i + 1}'),
            point: p.fix.point.toLatLng(),
            width: 26,
            height: 26,
            child: Container(
              decoration: BoxDecoration(
                color: p.kind == PingKind.speedhunt
                    ? AppColors.speedhunt
                    : color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );

/// This device's own live position.
MarkerLayer selfLayer(LocationFix fix) => MarkerLayer(
  markers: [
    Marker(
      point: fix.point.toLatLng(),
      width: 22,
      height: 22,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blueAccent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
        ),
      ),
    ),
  ],
);

class _NamedPin extends StatelessWidget {
  const _NamedPin({
    required this.name,
    required this.color,
    required this.icon,
    this.speedhunt = false,
  });

  final String name;
  final Color color;
  final IconData icon;
  final bool speedhunt;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (speedhunt)
                const Icon(Icons.bolt, size: 13, color: AppColors.speedhunt),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Icon(
          icon,
          color: color,
          size: 32,
          shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
        ),
      ],
    );
  }
}

/// Other players' current positions from the player joker (R-PLAY-03).
MarkerLayer playersLayer({
  required Map<String, LocationFix> positions,
  required Map<String, String> names,
}) => MarkerLayer(
  markers: [
    for (final entry in positions.entries)
      Marker(
        key: Key('player_${entry.key}'),
        point: entry.value.point.toLatLng(),
        width: 140,
        height: 64,
        alignment: Alignment.topCenter,
        child: _NamedPin(
          name: names[entry.key] ?? '?',
          color: AppColors.player,
          icon: Icons.person_pin_circle,
        ),
      ),
  ],
);
