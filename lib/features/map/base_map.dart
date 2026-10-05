import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/geo_point.dart';
import '../../theme/app_theme.dart';

/// MapTiler key, injected at build time:
/// `--dart-define-from-file=config/maptiler.json` (see CLAUDE.md).
const mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

/// Normal (light) OSM street map from MapTiler (R-MAP-01, R-UI-03).
const _tileUrl =
    'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}{r}.png?key={key}';

/// Whether map tiles are loaded from the network. Tests turn this off.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

extension GeoPointLatLng on GeoPoint {
  LatLng toLatLng() => LatLng(lat, lng);
}

extension LatLngGeoPoint on LatLng {
  GeoPoint toGeoPoint() => GeoPoint(latitude, longitude);
}

/// Center of Germany, used when nothing better is known.
const fallbackCenter = LatLng(51.1657, 10.4515);

/// Shared map setup: tiles + required attribution + caller's layers on top.
class BaseMap extends ConsumerWidget {
  const BaseMap({
    super.key,
    required this.options,
    this.controller,
    this.children = const [],
  });

  final MapOptions options;
  final MapController? controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = ref.watch(mapTilesEnabledProvider) && mapTilerKey.isNotEmpty;
    return FlutterMap(
      mapController: controller,
      options: options,
      children: [
        if (tiles)
          TileLayer(
            urlTemplate: _tileUrl,
            additionalOptions: const {'key': mapTilerKey},
            retinaMode: RetinaMode.isHighDensity(context),
            userAgentPackageName: 'play.manhunt.app',
            maxNativeZoom: 20,
          )
        else
          const ColoredBox(color: Color(0xFFE8E4DC)),
        ...children,
        const SimpleAttributionWidget(
          source: Text(
            '© MapTiler © OpenStreetMap contributors',
            style: TextStyle(fontSize: 10, color: Colors.black87),
          ),
          backgroundColor: Color(0xCCFFFFFF),
        ),
      ],
    );
  }
}

/// Darkens everything outside the play area and outlines it (R-GAME-02).
List<Widget> areaLayers(List<GeoPoint> area) {
  if (area.length < 3) return const [];
  final points = [for (final p in area) p.toLatLng()];
  return [
    PolygonLayer(
      polygons: [
        // Whole world with the play area cut out.
        Polygon(
          points: const [
            LatLng(85, -180),
            LatLng(85, 180),
            LatLng(-85, 180),
            LatLng(-85, -180),
          ],
          holePointsList: [points],
          color: Colors.black.withValues(alpha: 0.35),
        ),
        Polygon(
          points: points,
          borderColor: AppColors.hunter,
          borderStrokeWidth: 3,
        ),
      ],
    ),
  ];
}

/// Camera that shows the whole play area, or a fallback overview.
CameraFit? fitArea(List<GeoPoint> area) => area.length < 2
    ? null
    : CameraFit.coordinates(
        coordinates: [for (final p in area) p.toLatLng()],
        padding: const EdgeInsets.all(48),
        maxZoom: 17,
      );
