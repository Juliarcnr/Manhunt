import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/geo_point.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// MapTiler key, injected at build time:
/// `--dart-define-from-file=config/maptiler.json` (see CLAUDE.md).
const mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

/// Normal (light) OSM street map by default (R-MAP-01, R-UI-03); satellite
/// images with street names on request (R-MAP-03).
enum MapStyle {
  streets(
    'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}{r}.png?key={key}',
  ),
  satellite(
    'https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}{r}.jpg?key={key}',
  );

  const MapStyle(this.tileUrl);

  final String tileUrl;
}

/// The map style chosen on this device – for all maps, until the app closes.
final mapStyleProvider = NotifierProvider<MapStyleNotifier, MapStyle>(
  MapStyleNotifier.new,
);

class MapStyleNotifier extends Notifier<MapStyle> {
  @override
  MapStyle build() => MapStyle.streets;

  void toggle() =>
      state = state == MapStyle.streets ? MapStyle.satellite : MapStyle.streets;
}

/// Switches between street map and satellite images (R-MAP-03).
class MapStyleButton extends ConsumerWidget {
  const MapStyleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final satellite = ref.watch(mapStyleProvider) == MapStyle.satellite;
    return FloatingActionButton.small(
      key: const Key('mapStyleButton'),
      heroTag: 'mapStyle',
      tooltip: satellite ? l10n.mapStreets : l10n.mapSatellite,
      backgroundColor: AppColors.surface,
      onPressed: ref.read(mapStyleProvider.notifier).toggle,
      child: Icon(satellite ? Icons.map_outlined : Icons.satellite_alt),
    );
  }
}

/// Whether map tiles are loaded from the network. Tests turn this off.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

extension GeoPointLatLng on GeoPoint {
  LatLng toLatLng() => LatLng(lat, lng);
}

extension LatLngGeoPoint on LatLng {
  GeoPoint toGeoPoint() => GeoPoint(latitude, longitude);
}

/// North always up: zoom and pan, but no rotation (field test feedback).
const northUp = InteractionOptions(
  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
);

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
    final style = ref.watch(mapStyleProvider);
    return FlutterMap(
      mapController: controller,
      options: options,
      children: [
        if (tiles)
          TileLayer(
            // A new layer per style, so no tiles of the other style linger.
            key: ValueKey(style),
            urlTemplate: style.tileUrl,
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
