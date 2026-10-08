import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/geo/arrows.dart';
import '../../core/round/ping_schedule.dart';
import '../../theme/app_theme.dart';
import '../map/animated_marker_layer.dart';
import '../map/base_map.dart';

/// Colour per player, stable for the round: by join order (R-HUNT-03).
Map<String, Color> playerColors(List<String> playerIds) => {
  for (final (i, id) in playerIds.indexed)
    id: AppColors.playerPalette[i % AppColors.playerPalette.length],
};

/// Last regular ping of players (see [lastRegularPings], [sharedLastPings])
/// as a location pin with the name above, in the player's own colour
/// (R-HUNT-03, R-PLAY-05); [greyed] players (caught) in grey.
MarkerLayer lastPingsLayer({
  required Map<String, PingRecord> pings,
  required Map<String, String> names,
  required Map<String, Color> colors,
  Set<String> greyed = const {},
}) => MarkerLayer(
  markers: [
    for (final MapEntry(key: id, value: last) in pings.entries)
      Marker(
        key: Key('lastPing_$id'),
        point: last.fix.point.toLatLng(),
        width: 140,
        height: 64,
        alignment: Alignment.topCenter,
        child: _NamedPin(
          name: names[id] ?? '?',
          color: greyed.contains(id)
              ? AppColors.textMuted
              : colors[id] ?? AppColors.player,
          icon: Icons.location_on,
        ),
      ),
  ],
);

/// Live positions of hunters (R-HUNT-02) or a joker snapshot (R-PLAY-02):
/// location pins in the one hunter colour, with the hunter symbol before the
/// name. Live positions carry no time and glide to each new position instead
/// of jumping (R-MAP-04); pass [formatTime] for a snapshot, whose age matters.
Widget huntersLayer({
  required Map<String, LocationFix> positions,
  required Map<String, String> names,
  String Function(DateTime)? formatTime,
}) {
  final layer = _positionsLayer(
    keyPrefix: 'hunter',
    positions: positions,
    names: names,
    colors: const {},
    fallbackColor: AppColors.hunter,
    icon: Icons.location_on,
    labelIcon: Icons.track_changes,
    formatTime: formatTime,
  );
  if (formatTime != null) return layer;
  return AnimatedMarkerLayer(
    key: const Key('liveHunters'),
    markers: layer.markers,
    duration: const Duration(seconds: 2),
    curve: Curves.easeInOut,
  );
}

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

/// Named pins; with [formatTime] the label also shows the time of each
/// position ("Alex · 14:32"), so it is clear how old a revealed position is.
MarkerLayer _positionsLayer({
  required String keyPrefix,
  required Map<String, LocationFix> positions,
  required Map<String, String> names,
  required Map<String, Color> colors,
  required Color fallbackColor,
  required IconData icon,
  IconData? labelIcon,
  String Function(DateTime)? formatTime,
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
          name: [
            names[entry.key] ?? '?',
            if (formatTime != null) formatTime(entry.value.at.toLocal()),
          ].join(' · '),
          color: colors[entry.key] ?? fallbackColor,
          icon: icon,
          labelIcon: labelIcon,
        ),
      ),
  ],
);

/// Regular pings of one player, numbered 1, 2, 3 … in their colour
/// (R-PLAY-01, R-HUNT-04). Speedhunt pings are left out – they have their own
/// ⚡ numbering (R-HUNT-07), so the numbers match on every device.
/// [keyPrefix] keeps marker keys unique when several players are shown.
MarkerLayer historyLayer(
  List<PingRecord> pings, {
  required Color color,
  String keyPrefix = 'history',
}) => MarkerLayer(
  markers: [
    for (final (i, p) in regularPings(pings).indexed)
      Marker(
        key: Key('${keyPrefix}_${i + 1}'),
        point: p.fix.point.toLatLng(),
        width: 28,
        height: 28,
        child: _NumberDot(text: '${i + 1}', color: color, ring: Colors.white),
      ),
  ],
);

/// Speedhunt pings, labelled ⚡1/⚡2/⚡3 within their speedhunt: dark badge
/// (so the yellow bolt stays visible), ring in the player's colour
/// (R-HUNT-07). Each player's latest one also shows the name in the badge
/// ("⚡2 Anna") and a location pin in their colour below it.
MarkerLayer speedhuntPingsLayer({
  required List<PingRecord> pings,
  required Map<String, Color> colors,
  required Map<String, String> names,
}) {
  final latest = latestSpeedhuntPings(pings).values.toSet();
  return MarkerLayer(
    markers: [
      for (final p in pings)
        if (p.kind == PingKind.speedhunt)
          _speedhuntMarker(
            p,
            colors[p.playerId] ?? AppColors.player,
            name: latest.contains(p) ? names[p.playerId] ?? '?' : null,
          ),
    ],
  );
}

/// With a [name] (the player's latest ping) the badge also carries the name
/// and a location pin sits below it.
Marker _speedhuntMarker(PingRecord p, Color color, {String? name}) {
  final label = '⚡${p.speedhuntNumber ?? ''}';
  final pin = name != null;
  return Marker(
    key: Key('speedhunt_${p.playerId}_${p.slotId}'),
    point: p.fix.point.toLatLng(),
    width: pin ? 140 : 34,
    height: pin ? 60 : 28,
    // With a pin, its tip marks the position, like the other location pins.
    alignment: pin ? Alignment.topCenter : Alignment.center,
    child: pin
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color, width: 2.5),
                  boxShadow: const [
                    BoxShadow(blurRadius: 3, color: Colors.black38),
                  ],
                ),
                // Only as wide as the text needs (up to the marker width).
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '$label $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.location_on,
                color: color,
                size: 32,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ],
          )
        : _NumberDot(
            text: label,
            color: AppColors.surface,
            textColor: Colors.white,
            ring: color,
            wide: true,
          ),
  );
}

/// Connects each selected player's regular pings in time order, with arrows
/// in the walking direction (R-HUNT-05).
List<Widget> pathLayers(
  Map<String, List<PingRecord>> byPlayer,
  Map<String, Color> colors,
) {
  final paths = {
    for (final e in byPlayer.entries)
      if (regularPings(e.value) case final pings when pings.length > 1)
        e.key: [for (final p in pings) p.fix.point],
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
    this.textColor = Colors.black,
    this.wide = false,
  });

  final String text;
  final Color color;
  final Color ring;
  final Color textColor;
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
      style: TextStyle(
        color: textColor,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

/// This device's own live position. It moves smoothly between the GPS
/// updates (about one per second) instead of jumping (R-MAP-04).
Widget selfLayer(LocationFix fix) => AnimatedMarkerLayer(
  key: const Key('selfLayer'),
  markers: [
    Marker(
      key: const Key('self'),
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
    this.labelIcon,
  });

  final String name;
  final Color color;
  final IconData icon;

  /// Optional role symbol before the name.
  final IconData? labelIcon;

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
              if (labelIcon case final labelIcon?) ...[
                Icon(labelIcon, size: 13, color: color),
                const SizedBox(width: 3),
              ],
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
