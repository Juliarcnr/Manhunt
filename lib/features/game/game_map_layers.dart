import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/geo/arrows.dart';
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

  /// Players whose full history is shown – their last ping is part of it.
  Set<String> skip = const {},
}) => MarkerLayer(
  markers: [
    for (final entry in byPlayer.entries)
      if (entry.value.isNotEmpty && !skip.contains(entry.key))
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
  required Map<String, Color> colors,
  required String Function(DateTime) formatTime,
}) => _positionsLayer(
  keyPrefix: 'hunter',
  positions: positions,
  names: names,
  colors: colors,
  fallbackColor: AppColors.hunter,
  icon: Icons.track_changes,
  formatTime: formatTime,
);

/// Other players' current positions from the player joker (R-PLAY-03).
MarkerLayer playersLayer({
  required Map<String, LocationFix> positions,
  required Map<String, String> names,
  required Map<String, Color> colors,
  required String Function(DateTime) formatTime,
}) => _positionsLayer(
  keyPrefix: 'player',
  positions: positions,
  names: names,
  colors: colors,
  fallbackColor: AppColors.player,
  icon: Icons.person_pin_circle,
  formatTime: formatTime,
);

/// Named pins with the time of each position ("Alex · 14:32"), so it is
/// clear how old a revealed position is.
MarkerLayer _positionsLayer({
  required String keyPrefix,
  required Map<String, LocationFix> positions,
  required Map<String, String> names,
  required Map<String, Color> colors,
  required Color fallbackColor,
  required IconData icon,
  required String Function(DateTime) formatTime,
}) => MarkerLayer(
  markers: [
    for (final entry in positions.entries)
      Marker(
        key: Key('${keyPrefix}_${entry.key}'),
        point: entry.value.point.toLatLng(),
        width: 160,
        height: 64,
        alignment: Alignment.topCenter,
        child: _NamedPin(
          name:
              '${names[entry.key] ?? '?'} · ${formatTime(entry.value.at.toLocal())}',
          color: colors[entry.key] ?? fallbackColor,
          icon: icon,
        ),
      ),
  ],
);

/// Colour per hunter (by join order), in warm tones distinct from players.
Map<String, Color> hunterColors(List<String> hunterIds) => {
  for (final (i, id) in hunterIds.indexed)
    id: AppColors.hunterPalette[i % AppColors.hunterPalette.length],
};

/// Pings of one player, numbered 1, 2, 3 … in their colour (R-PLAY-01,
/// R-HUNT-04). A speedhunt ping gets a yellow ring; [keyPrefix] keeps marker
/// keys unique when several players are shown.
MarkerLayer historyLayer(
  List<PingRecord> pings, {
  required Color color,
  String keyPrefix = 'history',
}) => MarkerLayer(
  markers: [
    for (final (i, p) in pings.indexed)
      Marker(
        key: Key('${keyPrefix}_${i + 1}'),
        point: p.fix.point.toLatLng(),
        width: 28,
        height: 28,
        child: _NumberDot(
          text: '${i + 1}',
          color: color,
          ring: p.kind == PingKind.speedhunt
              ? AppColors.speedhunt
              : Colors.white,
        ),
      ),
  ],
);

/// All speedhunt pings, labelled ⚡1/⚡2/⚡3 within their speedhunt, ring in
/// the player's colour (R-HUNT-07). Players in [skip] already show their
/// full history.
MarkerLayer speedhuntPingsLayer({
  required List<PingRecord> pings,
  required Map<String, Color> colors,
  Set<String> skip = const {},
}) => MarkerLayer(
  markers: [
    for (final p in pings)
      if (p.kind == PingKind.speedhunt && !skip.contains(p.playerId))
        Marker(
          key: Key('speedhunt_${p.playerId}_${p.slotId}'),
          point: p.fix.point.toLatLng(),
          width: 34,
          height: 28,
          child: _NumberDot(
            text: '⚡${p.speedhuntNumber ?? ''}',
            color: AppColors.speedhunt,
            ring: colors[p.playerId] ?? AppColors.player,
            wide: true,
          ),
        ),
  ],
);

/// Connects each selected player's pings in time order, with arrows in the
/// walking direction (R-HUNT-05).
List<Widget> pathLayers(
  Map<String, List<PingRecord>> byPlayer,
  Map<String, Color> colors,
) {
  final paths = {
    for (final e in byPlayer.entries)
      if (e.value.length > 1) e.key: [for (final p in e.value) p.fix.point],
  };
  if (paths.isEmpty) return const [];
  return [
    PolylineLayer(
      polylines: [
        for (final e in paths.entries)
          Polyline(
            points: [for (final p in e.value) p.toLatLng()],
            color: (colors[e.key] ?? AppColors.player).withValues(alpha: 0.85),
            strokeWidth: 3,
          ),
      ],
    ),
    MarkerLayer(
      markers: [
        for (final e in paths.entries)
          for (final (i, a) in pathArrows(e.value).indexed)
            Marker(
              key: Key('arrow_${e.key}_$i'),
              point: a.at.toLatLng(),
              width: 18,
              height: 18,
              child: Transform.rotate(
                angle: a.bearingRad,
                child: Icon(
                  Icons.navigation,
                  size: 18,
                  color: colors[e.key] ?? AppColors.player,
                  shadows: const [Shadow(blurRadius: 3, color: Colors.black54)],
                ),
              ),
            ),
      ],
    ),
  ];
}

class _NumberDot extends StatelessWidget {
  const _NumberDot({
    required this.text,
    required this.color,
    required this.ring,
    this.wide = false,
  });

  final String text;
  final Color color;
  final Color ring;
  final bool wide;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color,
      shape: wide ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: wide ? BorderRadius.circular(14) : null,
      border: Border.all(color: ring, width: 2.5),
      boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
    ),
    alignment: Alignment.center,
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

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
