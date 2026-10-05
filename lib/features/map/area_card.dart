import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';

import '../../core/geo/polygon.dart';
import '../../core/models/geo_point.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'area_editor_screen.dart';
import 'base_map.dart';

/// Play area preview in the lobby (R-GAME-02). Every member can draw or edit
/// it (R-SET-06, R-SET-10), so it can be planned together.
class AreaCard extends StatelessWidget {
  const AreaCard({super.key, required this.area, required this.onChanged});

  final List<GeoPoint> area;
  final ValueChanged<List<GeoPoint>> onChanged;

  Future<void> _edit(BuildContext context) async {
    final result = await Navigator.of(context).push<List<GeoPoint>>(
      MaterialPageRoute(builder: (_) => AreaEditorScreen(initial: area)),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasArea = area.length >= 3;
    final fmt = NumberFormat('0.0', Localizations.localeOf(context).toString());

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasArea)
            SizedBox(
              height: 180,
              child: IgnorePointer(
                child: BaseMap(
                  // Rebuild (and refit) when the area changes.
                  key: ValueKey(Object.hashAll(area)),
                  options: MapOptions(
                    initialCenter: fallbackCenter,
                    initialCameraFit: fitArea(area),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: areaLayers(area),
                ),
              ),
            ),
          ListTile(
            leading: Icon(
              Icons.map_outlined,
              color: hasArea ? AppColors.player : AppColors.textMuted,
            ),
            title: Text(l10n.settingsArea),
            subtitle: Text(
              hasArea
                  ? '${l10n.settingsAreaPoints(area.length)} · ≈ ${fmt.format(polygonAreaKm2(area))} km²'
                  : l10n.settingsAreaMissing,
            ),
          ),
          // Everyone in the group may draw/edit the area (R-SET-10).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton.tonalIcon(
              key: const Key('editAreaButton'),
              onPressed: () => _edit(context),
              icon: Icon(hasArea ? Icons.edit_location_alt : Icons.draw),
              label: Text(hasArea ? l10n.areaEdit : l10n.areaDraw),
            ),
          ),
        ],
      ),
    );
  }
}
