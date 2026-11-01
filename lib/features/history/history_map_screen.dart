import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/history/round_map.dart';
import '../../core/history/round_summary.dart';
import '../../core/round/ping_schedule.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../game/filter_bar.dart';
import '../game/game_map_layers.dart';
import '../game/map_filters.dart';
import '../map/base_map.dart';

/// The saved map of one round (R-HIST-04), loaded once.
final roundMapProvider = FutureProvider.autoDispose.family<RoundMap?, String>((
  ref,
  historyId,
) async {
  final session = ref.watch(sessionControllerProvider).value;
  if (session == null) return null;
  return ref.watch(gameRepositoryProvider).loadRoundMap(session, historyId);
});

/// One round's map from the history: what everyone saw once it was over
/// (R-HIST-04) – with filter chips or as a timeline (R-HIST-07).
class HistoryMapScreen extends ConsumerWidget {
  const HistoryMapScreen({super.key, required this.summary});

  final RoundSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final map = ref.watch(roundMapProvider(summary.id));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyRound(summary.round))),
      body: map.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.commonError('$e'))),
        data: (map) => map == null
            ? Center(
                child: Text(
                  l10n.historyNoMap,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              )
            : RoundMapView(map: map),
      ),
    );
  }
}

enum _View { chips, timeline }

/// The map with the same chips as after the round (R-GAME-06, R-HUNT-11):
/// last pings, one chip per player and per speedhunt – and one per hunter,
/// whose positions at the ping times work like a player's history
/// (R-HIST-05). The timeline shows one ping time at a time (R-HIST-07).
class RoundMapView extends StatefulWidget {
  const RoundMapView({super.key, required this.map});

  final RoundMap map;

  @override
  State<RoundMapView> createState() => _RoundMapViewState();
}

class _RoundMapViewState extends State<RoundMapView> {
  final _controller = MapController();
  var _view = _View.chips;

  /// Starts with everyone's position at the end (R-HIST-08) instead of the
  /// last regular pings, so a pin per person is enough.
  var _filters = const MapFilters(lastPings: false);
  var _showEnd = true;

  /// Like [MapFilters.playerHistories], for the hunters; missing means off.
  var _hunterModes = const <String, HistoryMode>{};
  var _step = 0;

  late final _steps = timelineSteps(widget.map);
  late final _byPlayer = pingsByPlayer(widget.map.pings);
  late final _hunterHistories = hunterHistories(widget.map.hunterSnaps);
  late final _speedhunts = speedhuntsFromPings(widget.map.pings);
  late final _names = widget.map.names;
  late final _playerColors = playerColors(widget.map.playerIds);
  late final _hunterColors = hunterColors(widget.map.hunterIds);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cycleHunter(String id) => setState(() {
    final next = (_hunterModes[id] ?? HistoryMode.off).next;
    _hunterModes = {..._hunterModes, id: next};
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timeFmt = DateFormat.Hm(Localizations.localeOf(context).toString());
    final (layers, chips) = _view == _View.chips
        ? _chipsView(l10n, timeFmt)
        : (_timelineLayers(), const <FilterItem>[]);
    return Stack(
      children: [
        BaseMap(
          controller: _controller,
          options: MapOptions(
            interactionOptions: northUp,
            initialCenter: fallbackCenter,
            initialZoom: 6,
            initialCameraFit: fitArea(widget.map.area),
          ),
          children: [...areaLayers(widget.map.area), ...layers],
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<_View>(
                  key: const Key('historyViewSwitch'),
                  segments: [
                    ButtonSegment(
                      value: _View.chips,
                      icon: const Icon(Icons.filter_list),
                      label: Text(l10n.historyViewChips),
                    ),
                    ButtonSegment(
                      value: _View.timeline,
                      icon: const Icon(Icons.timeline),
                      label: Text(
                        l10n.historyViewTimeline,
                        key: const Key('historyViewTimeline'),
                      ),
                    ),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    backgroundColor: AppColors.surface.withValues(alpha: 0.92),
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (s) => setState(() => _view = s.single),
                ),
              ),
              const SizedBox(height: 8),
              FilterBar(items: chips),
            ],
          ),
        ),
        if (_view == _View.timeline)
          Positioned(
            left: 12,
            right: 12,
            bottom: 24,
            child: _timelineBar(l10n, timeFmt),
          ),
        Positioned(
          right: 12,
          bottom: _view == _View.timeline ? 150 : 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MapStyleButton(),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                key: const Key('fitAreaButton'),
                heroTag: 'fitArea',
                tooltip: l10n.settingsArea,
                backgroundColor: AppColors.surface,
                onPressed: () {
                  final fit = fitArea(widget.map.area);
                  if (fit != null) _controller.fitCamera(fit);
                },
                child: const Icon(Icons.crop_free),
              ),
            ],
          ),
        ),
      ],
    );
  }

  (List<Widget>, List<FilterItem>) _chipsView(
    AppLocalizations l10n,
    DateFormat timeFmt,
  ) {
    final filters = _filters;
    void set(MapFilters f) => setState(() => _filters = f);
    final selected = {
      for (final id in filters.playerHistories.keys)
        if (_byPlayer.containsKey(id)) id,
    };
    final shownHunters = {
      for (final e in _hunterModes.entries)
        if (e.value != HistoryMode.off) e.key,
    };
    final shownSpeedhunts = [
      for (final s in _speedhunts)
        if (!filters.hiddenSpeedhunts.contains(s.id)) s,
    ];
    final layers = <Widget>[
      // Lines below the dots, hunters below players.
      ...pathLayers({
        for (final id in shownHunters)
          if (_hunterModes[id] == HistoryMode.lines) id: ?_hunterHistories[id],
      }, _hunterColors),
      ...pathLayers({
        for (final id in selected)
          if (filters.historyOf(id) == HistoryMode.lines) id: _byPlayer[id]!,
      }, _playerColors),
      for (final id in shownHunters)
        if (_hunterHistories[id] case final list?)
          historyLayer(
            list,
            color: _hunterColors[id] ?? AppColors.hunter,
            keyPrefix: 'hunterHistory_$id',
          ),
      for (final id in selected)
        historyLayer(
          _byPlayer[id]!,
          color: _playerColors[id] ?? AppColors.player,
          keyPrefix: 'history_$id',
        ),
      // With each speedhunt the hunters at its ping times (R-HIST-05).
      hunterSnapsLayer(
        snaps: [
          for (final s in shownSpeedhunts)
            ...hunterSnapsForSpeedhunt(widget.map.hunterSnaps, s),
        ],
        colors: _hunterColors,
      ),
      speedhuntPingsLayer(
        pings: [for (final s in shownSpeedhunts) ...s.pings],
        colors: _playerColors,
        names: _names,
      ),
      if (filters.lastPings)
        lastPingsLayer(
          pings: lastRegularPings(_byPlayer, skip: selected),
          names: _names,
          colors: _playerColors,
        ),
      // Where everyone was when the round was over (R-HIST-08).
      if (_showEnd) ...[
        namedPinsLayer(
          keyPrefix: 'endHunter',
          positions: widget.map.lastHunters,
          names: _names,
          colors: _hunterColors,
          hunters: true,
        ),
        namedPinsLayer(
          keyPrefix: 'endPlayer',
          positions: widget.map.endPlayers,
          names: _names,
          colors: _playerColors,
        ),
      ],
    ];
    final chips = [
      if (widget.map.hasEnd)
        FilterItem(
          id: 'end',
          label: l10n.historyEnd,
          icon: Icons.flag,
          color: AppColors.speedhunt,
          selected: _showEnd,
          onChanged: (v) => setState(() => _showEnd = v),
        ),
      FilterItem(
        id: 'lastPings',
        label: l10n.filterLastPings,
        icon: Icons.location_on,
        selected: filters.lastPings,
        onChanged: (v) => set(filters.copyWith(lastPings: v)),
      ),
      // Tap cycles: points → points with lines → off (R-HUNT-04, R-HUNT-05).
      for (final id in widget.map.playerIds)
        FilterItem(
          id: 'player_$id',
          label: _names[id] ?? '?',
          icon: filters.historyOf(id) == HistoryMode.lines
              ? Icons.timeline
              : null,
          color: _playerColors[id] ?? AppColors.player,
          selected: filters.historyOf(id) != HistoryMode.off,
          onChanged: (_) => set(filters.cyclePlayer(id)),
        ),
      // The same for every hunter (R-HIST-05).
      for (final id in widget.map.hunterIds)
        FilterItem(
          id: 'hunter_$id',
          label: _names[id] ?? '?',
          icon: _hunterModes[id] == HistoryMode.lines
              ? Icons.timeline
              : Icons.track_changes,
          color: _hunterColors[id] ?? AppColors.hunter,
          selected: shownHunters.contains(id),
          onChanged: (_) => _cycleHunter(id),
        ),
      for (final s in _speedhunts)
        FilterItem(
          id: 'speedhunt_${s.id}',
          label: l10n.filterSpeedhunt(
            _names[s.playerId] ?? '?',
            timeFmt.format(s.startedAt.toLocal()),
          ),
          icon: Icons.bolt,
          color: _playerColors[s.playerId] ?? AppColors.player,
          selected: !filters.hiddenSpeedhunts.contains(s.id),
          onChanged: (_) => set(filters.toggleSpeedhunt(s.id)),
        ),
    ];
    return (layers, chips);
  }

  List<Widget> _timelineLayers() {
    if (_steps.isEmpty) return const [];
    final step = _steps[_step.clamp(0, _steps.length - 1)];
    final frame = timelineAt(widget.map, step);
    return [
      namedPinsLayer(
        keyPrefix: 'timelineHunter',
        positions: frame.hunters,
        names: _names,
        colors: _hunterColors,
        hunters: true,
      ),
      if (step.kind == PingKind.speedhunt)
        speedhuntPingsLayer(
          pings: frame.players.values.toList(),
          colors: _playerColors,
          names: _names,
        )
      else
        namedPinsLayer(
          keyPrefix: 'timelinePlayer',
          positions: {
            for (final e in frame.players.entries) e.key: e.value.fix,
          },
          names: _names,
          colors: _playerColors,
        ),
    ];
  }

  Widget _timelineBar(AppLocalizations l10n, DateFormat timeFmt) {
    String clock(DateTime t) => timeFmt.format(t.toLocal());
    if (_steps.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.historyTimelineEmpty,
            key: const Key('timelineEmpty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final index = _step.clamp(0, _steps.length - 1);
    final step = _steps[index];
    final regularNumber = int.tryParse(
      step.slotId.substring(step.slotId.lastIndexOf('_') + 1),
    );
    final label = step.isEnd
        ? l10n.historyTimelineEnd(clock(step.at))
        : step.kind == PingKind.speedhunt
        ? l10n.historyTimelineSpeedhunt(
            step.speedhuntNumber ?? 0,
            _names[step.targetId] ?? '?',
            clock(step.at),
          )
        : l10n.historyTimelineRegular(regularNumber ?? 0, clock(step.at));
    void go(int i) => setState(() => _step = i.clamp(0, _steps.length - 1));
    return Card(
      color: AppColors.surface.withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('timelineBack'),
                  tooltip: l10n.historyTimelineBack,
                  onPressed: index > 0 ? () => go(index - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    label,
                    key: const Key('timelineLabel'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: step.kind == PingKind.speedhunt
                          ? AppColors.speedhunt
                          : Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('timelineNext'),
                  tooltip: l10n.historyTimelineNext,
                  onPressed: index < _steps.length - 1
                      ? () => go(index + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (_steps.length > 1)
              Slider(
                key: const Key('timelineSlider'),
                value: index.toDouble(),
                max: (_steps.length - 1).toDouble(),
                divisions: _steps.length - 1,
                activeColor: step.kind == PingKind.speedhunt
                    ? AppColors.speedhunt
                    : AppColors.player,
                onChanged: (v) => go(v.round()),
              ),
            // ⚡ steps marked below the slider, at their position.
            if (_steps.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  height: 6,
                  child: LayoutBuilder(
                    builder: (_, box) => Stack(
                      children: [
                        for (final (i, s) in _steps.indexed)
                          if (s.kind == PingKind.speedhunt)
                            Positioned(
                              left: box.maxWidth * i / (_steps.length - 1) - 3,
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppColors.speedhunt,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    clock(widget.map.startedAt),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const Spacer(),
                  Text(
                    clock(widget.map.endedAt),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
