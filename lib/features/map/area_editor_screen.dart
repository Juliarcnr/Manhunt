import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/geo/area_draft.dart';
import '../../core/geo/polygon.dart';
import '../../core/models/geo_point.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import 'base_map.dart';

/// Draw the play area like in Google My Maps (R-SET-06): tap to add corners,
/// drag to move, long-press to delete, "+" on an edge to insert.
/// Pops with the new polygon, or null when cancelled.
class AreaEditorScreen extends ConsumerStatefulWidget {
  const AreaEditorScreen({super.key, this.initial = const []});

  final List<GeoPoint> initial;

  @override
  ConsumerState<AreaEditorScreen> createState() => _AreaEditorScreenState();
}

class _AreaEditorScreenState extends ConsumerState<AreaEditorScreen> {
  final _mapController = MapController();
  final _mapKey = GlobalKey();
  late var _draft = AreaDraft(List.unmodifiable(widget.initial));
  var _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _goToMyLocation(quiet: true),
      );
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _update(AreaDraft draft) => setState(() => _draft = draft);

  Future<void> _goToMyLocation({bool quiet = false}) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _locating = true);
    GeoPoint? pos;
    try {
      pos = await ref.read(locationServiceProvider).currentPosition();
    } on Exception {
      pos = null;
    }
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos != null) {
      _mapController.move(pos.toLatLng(), 15);
    } else if (!quiet) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.areaLocationUnavailable)));
    }
  }

  /// Converts a finger position on screen to map coordinates.
  GeoPoint? _toGeo(Offset globalPosition) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return _mapController.camera
        .screenOffsetToLatLng(box.globalToLocal(globalPosition))
        .toGeoPoint();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final points = _draft.points;
    final latLngs = [for (final p in points) p.toLatLng()];
    final initialFit = fitArea(widget.initial);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.areaTitle),
        actions: [
          IconButton(
            key: const Key('areaUndo'),
            tooltip: l10n.areaUndo,
            onPressed: _draft.canUndo ? () => _update(_draft.undo()) : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const Key('areaClear'),
            tooltip: l10n.areaClear,
            onPressed: points.isEmpty ? null : () => _update(_draft.clear()),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Stack(
        children: [
          BaseMap(
            key: _mapKey,
            controller: _mapController,
            options: MapOptions(
              interactionOptions: northUp,
              initialCenter: fallbackCenter,
              initialZoom: 6,
              initialCameraFit: initialFit,
              onTap: (_, latLng) => _update(_draft.add(latLng.toGeoPoint())),
            ),
            children: [
              if (points.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: latLngs,
                      color: AppColors.hunter.withValues(alpha: 0.15),
                      borderColor: _draft.isSimple
                          ? AppColors.hunter
                          : Colors.red,
                      borderStrokeWidth: 3,
                    ),
                  ],
                )
              else if (points.length == 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: latLngs,
                      color: AppColors.hunter,
                      strokeWidth: 3,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (points.length >= 2)
                    for (var i = 0; i < points.length; i++)
                      if (points.length >= 3 || i == 0)
                        Marker(
                          point: _draft.midpoint(i).toLatLng(),
                          width: 26,
                          height: 26,
                          child: _MidpointHandle(
                            key: Key('areaInsert$i'),
                            onTap: () => _update(
                              _draft.insertAfter(i, _draft.midpoint(i)),
                            ),
                          ),
                        ),
                  for (var i = 0; i < points.length; i++)
                    Marker(
                      point: latLngs[i],
                      width: 32,
                      height: 32,
                      child: _CornerHandle(
                        key: Key('areaCorner$i'),
                        number: i + 1,
                        onDragStart: () {
                          _update(_draft.beginMove());
                        },
                        onDrag: (global) {
                          final geo = _toGeo(global);
                          if (geo != null) {
                            _update(_draft.move(i, geo, record: false));
                          }
                        },
                        onLongPress: () => _update(_draft.remove(i)),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _InfoCard(text: l10n.areaHint, icon: Icons.touch_app),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'myLocation',
              tooltip: l10n.areaMyLocation,
              backgroundColor: AppColors.surface,
              onPressed: _locating ? null : _goToMyLocation,
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AreaStatus(draft: _draft),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('areaSave'),
                onPressed: _draft.isValid
                    ? () => Navigator.of(context).pop(_draft.points)
                    : null,
                icon: const Icon(Icons.check),
                label: Text(l10n.areaSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaStatus extends StatelessWidget {
  const _AreaStatus({required this.draft});

  final AreaDraft draft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fmt = NumberFormat('0.0', Localizations.localeOf(context).toString());
    final (text, color) = !draft.hasMinimumPoints
        ? (l10n.areaNeedPoints, AppColors.textMuted)
        : !draft.isSimple
        ? (l10n.areaCrossing, Colors.redAccent)
        : () {
            final e = polygonExtentKm(draft.points);
            return (
              l10n.areaStats(
                draft.points.length,
                fmt.format(draft.areaKm2),
                fmt.format(e.widthKm),
                fmt.format(e.heightKm),
              ),
              Colors.white,
            );
          }();
    return Text(
      text,
      key: const Key('areaStatus'),
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _CornerHandle extends StatelessWidget {
  const _CornerHandle({
    super.key,
    required this.number,
    required this.onDragStart,
    required this.onDrag,
    required this.onLongPress,
  });

  final int number;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onLongPress;

  /// The map claims horizontal/vertical drags after the normal touch slop
  /// (18 px). A smaller slop lets a corner win the gesture arena, so dragging a
  /// corner moves the corner instead of the map.
  static const _cornerGestureSettings = DeviceGestureSettings(touchSlop: 4);

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              PanGestureRecognizer.new,
              (r) => r
                ..gestureSettings = _cornerGestureSettings
                ..onStart = ((_) => onDragStart())
                ..onUpdate = ((d) => onDrag(d.globalPosition)),
            ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              LongPressGestureRecognizer.new,
              (r) => r.onLongPress = onLongPress,
            ),
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hunter, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _MidpointHandle extends StatelessWidget {
  const _MidpointHandle({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hunter.withValues(alpha: 0.7)),
        ),
        child: const Icon(Icons.add, size: 16, color: AppColors.hunter),
      ),
    );
  }
}
