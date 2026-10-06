import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/history/round_summary.dart';
import '../../core/models/member.dart';
import '../../core/round/notices.dart';
import '../../core/round/ping_schedule.dart';
import '../../core/schedule/game_clock.dart';
import '../../core/schedule/speedhunt.dart';
import '../../data/game_repository.dart';
import '../../data/joker_store.dart';
import '../../data/location_service.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/round_engine.dart';
import '../../theme/app_theme.dart';
import 'overview_sheet.dart';
import '../map/base_map.dart';
import 'catch_dialog.dart';
import 'filter_bar.dart';
import 'joker_sheet.dart';
import 'map_filters.dart';
import 'game_map_layers.dart';
import 'speedhunt_dialog.dart';

/// Running round: map with role-specific layers, status, actions, automatic
/// pings in the background and notifications (phase 5).
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({
    super.key,
    required this.session,
    required this.game,
    this.now = DateTime.now,
  });

  final GroupSession session;
  final GameInfo game;

  /// Injectable clock for tests.
  final DateTime Function() now;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  Timer? _ticker;
  var _ending = false;
  RoundEngine? _engine;
  final _notices = NoticeTracker();
  final _map = MapController();
  final _subscriptions = <ProviderSubscription<Object?>>[];
  StreamSubscription<PingSlot>? _pingsSentSub;
  var _lifecycle = AppLifecycleState.resumed;
  ({String title, String? body})? _banner;
  Timer? _bannerTimer;
  ({DateTime at, Map<String, LocationFix> positions})? _jokerReveal;
  ({DateTime at, String requestId})? _playerReveal;
  var _filters = const MapFilters();

  bool get _isAdmin => widget.game.adminId == widget.session.userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_engine != null) return;
    final l10n = AppLocalizations.of(context);
    final engine = RoundEngine(
      session: widget.session,
      rounds: ref.read(roundRepositoryProvider),
      location: ref.read(locationServiceProvider),
      notice: TrackingNotice(
        title: l10n.trackingTitle,
        text: l10n.trackingText,
      ),
      now: widget.now,
    );
    _engine = engine;
    engine.log.value = ['screen opened'];
    _pingsSentSub = engine.pingsSent.listen(
      (slot) => _notify(PingSentNotice(slot.kind)),
    );
    // Location first, then notifications: Android drops a permission dialog
    // requested while another one is open (field test 2026-10-05).
    unawaited(_requestPermissions());
    unawaited(_loadJokers());

    _subscriptions
      ..add(
        ref.listenManual(
          membersProvider,
          (_, _) => _feedEngine(),
          fireImmediately: true,
        ),
      )
      ..add(
        ref.listenManual(
          speedhuntsOnMeProvider,
          (_, _) => _feedEngine(),
          fireImmediately: true,
        ),
      )
      ..add(
        ref.listenManual<AsyncValue<List<CatchRecord>>>(catchesProvider, (
          _,
          next,
        ) {
          final catches = next.value;
          if (catches != null) _notices.onCatches(catches).forEach(_notify);
        }, fireImmediately: true),
      )
      ..add(
        ref.listenManual<AsyncValue<List<Speedhunt>>>(speedhuntsProvider, (
          _,
          next,
        ) {
          final list = next.value;
          if (list != null) _notices.onSpeedhunts(list).forEach(_notify);
        }, fireImmediately: true),
      );
    _feedEngine();
  }

  void _showLog() {
    final engine = _engine;
    if (engine == null) return;
    final l10n = AppLocalizations.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.debugLogTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: ValueListenableBuilder(
              valueListenable: engine.log,
              builder: (_, lines, _) => SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  lines.isEmpty ? '–' : lines.join('\n'),
                  key: const Key('debugLog'),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonClose),
            ),
          ],
        ),
      ),
    );
  }

  /// Like Google Maps: jump to the own position (the map starts on the play
  /// area, which may be elsewhere – field test feedback).
  Future<void> _showMe() async {
    final l10n = AppLocalizations.of(context);
    var point = _engine?.position.value?.point;
    point ??= await ref.read(locationServiceProvider).currentPosition();
    if (!mounted) return;
    if (point == null) {
      _snack(l10n.areaLocationUnavailable);
      return;
    }
    _map.move(point.toLatLng(), 16);
  }

  void _showArea() {
    final fit = fitArea(widget.game.settings.area);
    if (fit != null) _map.fitCamera(fit);
  }

  Future<void> _requestPermissions() async {
    await ref.read(locationServiceProvider).ensurePermission();
    await ref.read(notificationServiceProvider).init();
  }

  void _feedEngine() => _engine?.update(
    game: widget.game,
    me: _me(ref.read(membersProvider).value),
    speedhuntsOnMe: ref.read(speedhuntsOnMeProvider).value ?? const [],
  );

  @override
  void didUpdateWidget(GameScreen old) {
    super.didUpdateWidget(old);
    _feedEngine();
    // The start time arrives a moment after "start" (server timestamp).
    unawaited(_loadJokers());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _lifecycle = state;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _map.dispose();
    _bannerTimer?.cancel();
    for (final s in _subscriptions) {
      s.close();
    }
    unawaited(_pingsSentSub?.cancel());
    unawaited(_engine?.dispose());
    super.dispose();
  }

  Member? _me(List<Member>? members) {
    for (final m in members ?? const <Member>[]) {
      if (m.id == widget.session.userId) return m;
    }
    return null;
  }

  /// In-app banner + vibration in the foreground, system notification in the
  /// background (R-NOTIF-01).
  void _notify(GameNotice notice) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final names = {
      for (final m in ref.read(membersProvider).value ?? const <Member>[])
        m.id: m.name,
    };
    final (title, body) = switch (notice) {
      CatchNotice(:final record) => (
        l10n.noticeCaught(names[record.playerId] ?? '?'),
        null,
      ),
      SpeedhuntNotice(:final speedhunt) => (
        l10n.noticeSpeedhunt,
        l10n.noticeSpeedhuntBody(speedhunt.pings, speedhunt.interval.inMinutes),
      ),
      PingSentNotice() => (l10n.noticePingSent, null),
    };
    final notifications = ref.read(notificationServiceProvider);
    if (_lifecycle == AppLifecycleState.resumed) {
      // App open: own banner + vibration always (also when muted); the
      // system notification only adds the sound, which the OS plays only if
      // the phone is not muted (R-NOTIF-05).
      unawaited(HapticFeedback.vibrate());
      unawaited(
        notifications.show(title: title, body: body ?? '', foreground: true),
      );
      _bannerTimer?.cancel();
      setState(() => _banner = (title: title, body: body));
      _bannerTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _banner = null);
      });
    } else {
      unawaited(notifications.show(title: title, body: body ?? ''));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Exception catch (e) {
      if (!mounted) return;
      _snack(AppLocalizations.of(context).commonError('$e'));
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<bool> _confirm({
    required IconData icon,
    required Color color,
    required String title,
    required String text,
    required String action,
    required Key actionKey,
    bool destructive = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, color: color),
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: actionKey,
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  /// Host ends the round (R-GAME-06). While time is left this is an early
  /// abort that needs two confirmations (R-GAME-07).
  Future<void> _endRound() async {
    final l10n = AppLocalizations.of(context);
    final startAt = widget.game.startAt;
    final endAt = startAt?.add(widget.game.settings.duration);
    final now = widget.now();
    final early = endAt != null && now.isBefore(endAt);

    if (early) {
      if (!await _confirm(
        icon: Icons.warning_amber_rounded,
        color: AppColors.speedhunt,
        title: l10n.gameAbortTitle,
        text: l10n.gameAbortText(_formatCountdown(endAt.difference(now))),
        action: l10n.gameAbortContinue,
        actionKey: const Key('confirmAbortFirst'),
      )) {
        return;
      }
      if (!await _confirm(
        icon: Icons.delete_forever_outlined,
        color: Colors.redAccent,
        title: l10n.gameAbortFinalTitle,
        text: l10n.gameEndConfirmText,
        action: l10n.gameAbortFinalAction,
        actionKey: const Key('confirmEndRound'),
        destructive: true,
      )) {
        return;
      }
    } else if (!await _confirm(
      icon: Icons.delete_sweep_outlined,
      color: AppColors.speedhunt,
      title: l10n.gameEndConfirmTitle,
      text: l10n.gameEndConfirmText,
      action: l10n.gameEndConfirmAction,
      actionKey: const Key('confirmEndRound'),
    )) {
      return;
    }
    setState(() => _ending = true);
    await _run(() => ref.read(gameRepositoryProvider).endRound(widget.session));
    if (mounted) setState(() => _ending = false);
  }

  /// Host removes someone during the round (R-LOBBY-09).
  Future<void> _removeMember(Member m) async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirm(
      icon: Icons.person_remove_outlined,
      color: Colors.redAccent,
      title: l10n.lobbyRemoveMember(m.name),
      text: l10n.removeMemberText,
      action: l10n.lobbyRemove,
      actionKey: const Key('confirmRemove'),
      destructive: true,
    )) {
      return;
    }
    await _run(
      () => ref.read(gameRepositoryProvider).removeMember(widget.session, m.id),
    );
  }

  Future<void> _reportCatchAsHunter(List<Member> members) async {
    final playerId = await showHunterCatchDialog(context, members: members);
    if (playerId == null) return;
    await _run(
      () => ref
          .read(gameRepositoryProvider)
          .recordCatch(
            widget.session,
            CatchRecord(playerId: playerId, at: widget.now().toUtc()),
          ),
    );
  }

  Future<void> _reportSelfCatch() async {
    if (!await showSelfCatchDialog(context)) return;
    await _run(
      () => ref
          .read(gameRepositoryProvider)
          .recordCatch(
            widget.session,
            CatchRecord(
              playerId: widget.session.userId,
              at: widget.now().toUtc(),
            ),
          ),
    );
  }

  Future<void> _startSpeedhunt(
    GameClock clock,
    List<Member> members,
    List<Speedhunt> previous,
  ) async {
    final l10n = AppLocalizations.of(context);
    // Check time/count/running first, so nobody picks a target in vain.
    final early = canStartSpeedhunt(
      clock: clock,
      now: widget.now(),
      previous: previous,
      target: const Member(id: '', name: '', role: Role.player),
    );
    if (early != null) {
      _snack(speedhuntDenialText(l10n, early, widget.game.settings));
      return;
    }
    final targetId = await showSpeedhuntDialog(
      context,
      members: members,
      settings: widget.game.settings,
    );
    if (targetId == null || !mounted) return;
    final denial = canStartSpeedhunt(
      clock: clock,
      now: widget.now(),
      previous: previous,
      target: members.firstWhere((m) => m.id == targetId),
    );
    if (denial != null) {
      _snack(speedhuntDenialText(l10n, denial, widget.game.settings));
      return;
    }
    await _run(
      () => ref
          .read(roundRepositoryProvider)
          .startSpeedhunt(
            widget.session,
            Speedhunt.fromSettings(
              targetId: targetId,
              startedAt: widget.now().toUtc(),
              settings: widget.game.settings,
            ),
          ),
    );
  }

  Future<void> _openJokers(Member me) async {
    final settings = widget.game.settings;
    final kind = await showJokerSheet(
      context,
      huntersEnabled: settings.jokerEnabled,
      huntersUsed: me.jokerUsed,
      playersEnabled: settings.playerJokerEnabled,
      playersUsed: me.playerJokerUsed,
    );
    if (!mounted) return;
    switch (kind) {
      case JokerKind.hunters:
        await _useHunterJoker();
      case JokerKind.players:
        await _usePlayerJoker();
      case null:
        return;
    }
  }

  /// Joker results are kept on the device, so they can be shown again later
  /// – also after an app restart (R-PLAY-04).
  Future<void> _saveJokers() async {
    final startAt = widget.game.startAt;
    if (startAt == null) return;
    await ref
        .read(jokerStoreProvider)
        .save(
          widget.session.groupId,
          SavedJokers(
            roundStart: startAt,
            hunters: _jokerReveal,
            players: _playerReveal,
          ),
        );
  }

  Future<void> _loadJokers() async {
    final startAt = widget.game.startAt;
    if (startAt == null || _jokersLoadedFor == startAt) return;
    _jokersLoadedFor = startAt;
    final saved = await ref
        .read(jokerStoreProvider)
        .load(widget.session.groupId, startAt);
    if (saved == null || !mounted) return;
    setState(() {
      _jokerReveal ??= saved.hunters;
      _playerReveal ??= saved.players;
    });
  }

  DateTime? _jokersLoadedFor;

  bool _jokersLeft(Member me) {
    final s = widget.game.settings;
    return (s.jokerEnabled && !me.jokerUsed) ||
        (s.playerJokerEnabled && !me.playerJokerUsed);
  }

  /// R-PLAY-02: see the hunters once.
  Future<void> _useHunterJoker() async {
    final l10n = AppLocalizations.of(context);
    if (!await showJokerConfirm(
      context,
      title: l10n.jokerTitle,
      text: l10n.jokerText,
    )) {
      return;
    }
    await _run(() async {
      final positions = await ref
          .read(roundRepositoryProvider)
          .useJoker(widget.session);
      if (!mounted) return;
      if (positions.isEmpty) _snack(l10n.jokerNoHunters);
      setState(() {
        _jokerReveal = (at: widget.now(), positions: positions);
        _filters = _filters.copyWith(hunterJoker: true);
      });
      unawaited(_saveJokers());
    });
  }

  /// R-PLAY-03: see all other players once – their devices answer the request.
  Future<void> _usePlayerJoker() async {
    final l10n = AppLocalizations.of(context);
    if (!await showJokerConfirm(
      context,
      title: l10n.jokerPlayersTitle,
      text: l10n.jokerPlayersText,
    )) {
      return;
    }
    await _run(() async {
      final requestId = await ref
          .read(roundRepositoryProvider)
          .requestPlayerPositions(widget.session);
      if (!mounted) return;
      setState(() {
        _playerReveal = (at: widget.now(), requestId: requestId);
        _filters = _filters.copyWith(playerJoker: true);
      });
      unawaited(_saveJokers());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timeFmt = DateFormat.Hm(Localizations.localeOf(context).toString());
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final me = _me(members);
    final names = {for (final m in members) m.id: m.name};
    final playersByColor = playerColors([
      for (final m in members)
        if (m.isPlayer) m.id,
    ]);
    final caught = {
      for (final m in members)
        if (m.caught) m.id,
    };
    final speedhunts = ref.watch(speedhuntsProvider).value ?? const [];
    final isHunter = me?.isHunter ?? false;
    final isPlayer = me?.isPlayer ?? false;

    final startAt = widget.game.startAt;
    // startAt is a server timestamp and briefly null right after "start".
    final clock = startAt == null
        ? null
        : GameClock(startAt: startAt, settings: widget.game.settings);
    final now = widget.now();
    final phase = clock?.phaseAt(now) ?? GamePhase.notStarted;
    final running = activeSpeedhunt(speedhunts, now);

    final (title, color, until) = switch (phase) {
      GamePhase.notStarted => (
        l10n.gamePhaseStarting,
        AppColors.textMuted,
        null,
      ),
      GamePhase.headStart => (
        l10n.gamePhaseHeadStart,
        AppColors.player,
        clock!.huntersReleaseAt,
      ),
      GamePhase.hunting => (
        l10n.gamePhaseHunting,
        AppColors.hunter,
        clock!.endAt,
      ),
      GamePhase.ended => (l10n.gamePhaseTimeUp, AppColors.speedhunt, null),
    };

    // Role-specific map content. Hunter-only data is only watched by hunters
    // (the security rules reject it for players).
    final layers = <Widget>[...areaLayers(widget.game.settings.area)];
    final filters = _filters;
    final filterItems = <FilterItem>[];
    if (isHunter) {
      final pings = ref.watch(allPingsProvider).value ?? const [];
      final hunters =
          ref.watch(hunterLocationsProvider).value ??
          const <String, LocationFix>{};
      final byPlayer = pingsByPlayer(pings);
      final selected = {
        for (final id in filters.playerHistories)
          if (byPlayer.containsKey(id)) id,
      };
      if (filters.lines) {
        layers.addAll(
          pathLayers({
            for (final id in selected) id: byPlayer[id]!,
          }, playersByColor),
        );
      }
      for (final id in selected) {
        layers.add(
          historyLayer(
            byPlayer[id]!,
            color: playersByColor[id] ?? AppColors.player,
            keyPrefix: 'history_$id',
          ),
        );
      }
      if (filters.speedhunts) {
        layers.add(
          speedhuntPingsLayer(
            pings: pings,
            colors: playersByColor,
            skip: selected,
          ),
        );
      }
      if (filters.lastPings) {
        layers.add(
          lastPingsLayer(
            byPlayer: byPlayer,
            names: names,
            caught: caught,
            colors: playersByColor,
            skip: selected,
          ),
        );
      }
      if (filters.hunters) {
        layers.add(
          huntersLayer(
            positions: {
              for (final e in hunters.entries)
                if (e.key != widget.session.userId) e.key: e.value,
            },
            names: names,
          ),
        );
      }
      void set(MapFilters f) => setState(() => _filters = f);
      filterItems.addAll([
        FilterItem(
          id: 'hunters',
          label: l10n.filterHunters,
          icon: Icons.track_changes,
          color: AppColors.hunter,
          selected: filters.hunters,
          onChanged: (v) => set(filters.copyWith(hunters: v)),
        ),
        FilterItem(
          id: 'lastPings',
          label: l10n.filterLastPings,
          icon: Icons.location_on,
          selected: filters.lastPings,
          onChanged: (v) => set(filters.copyWith(lastPings: v)),
        ),
        FilterItem(
          id: 'speedhunts',
          label: l10n.filterSpeedhunts,
          icon: Icons.bolt,
          color: AppColors.speedhunt,
          selected: filters.speedhunts,
          onChanged: (v) => set(filters.copyWith(speedhunts: v)),
        ),
        FilterItem(
          id: 'lines',
          label: l10n.filterLines,
          icon: Icons.timeline,
          selected: filters.lines,
          onChanged: (v) => set(filters.copyWith(lines: v)),
        ),
        for (final m in members)
          if (m.isPlayer)
            FilterItem(
              id: 'player_${m.id}',
              label: m.name,
              color: playersByColor[m.id] ?? AppColors.player,
              selected: filters.playerHistories.contains(m.id),
              onChanged: (_) => set(filters.togglePlayer(m.id)),
            ),
      ]);
    } else if (isPlayer) {
      final mine = pingsByPlayer(
        ref.watch(myPingsProvider).value ?? const [],
      )[widget.session.userId];
      if (mine != null && filters.myPings) {
        // Own speedhunt pings stay hidden (R-SPEED-04).
        final regular = [
          for (final p in mine)
            if (p.kind == PingKind.regular) p,
        ];
        layers.add(historyLayer(regular, color: AppColors.player));
      }
      final reveal = _jokerReveal;
      if (reveal != null && filters.hunterJoker) {
        layers.add(
          huntersLayer(
            positions: reveal.positions,
            names: names,
            formatTime: timeFmt.format,
          ),
        );
      }
      final playerReveal = _playerReveal;
      if (playerReveal != null && filters.playerJoker) {
        final answers =
            ref.watch(jokerAnswersProvider(playerReveal.requestId)).value ??
            const <String, LocationFix>{};
        layers.add(
          playersLayer(
            positions: answers,
            names: names,
            colors: playersByColor,
            formatTime: timeFmt.format,
          ),
        );
      }
      void set(MapFilters f) => setState(() => _filters = f);
      filterItems.addAll([
        FilterItem(
          id: 'myPings',
          label: l10n.filterMyPings,
          icon: Icons.history,
          selected: filters.myPings,
          onChanged: (v) => set(filters.copyWith(myPings: v)),
        ),
        if (reveal != null)
          FilterItem(
            id: 'hunterJoker',
            label: l10n.filterHunterJoker(timeFmt.format(reveal.at.toLocal())),
            icon: Icons.visibility_outlined,
            color: AppColors.hunter,
            selected: filters.hunterJoker,
            onChanged: (v) => set(filters.copyWith(hunterJoker: v)),
          ),
        if (playerReveal != null)
          FilterItem(
            id: 'playerJoker',
            label: l10n.filterPlayerJoker(
              timeFmt.format(playerReveal.at.toLocal()),
            ),
            icon: Icons.groups_outlined,
            selected: filters.playerJoker,
            onChanged: (v) => set(filters.copyWith(playerJoker: v)),
          ),
      ]);
      // Answer other players' joker requests (R-PLAY-03) – players only, the
      // rules hide requests from hunters.
      ref.listen(jokerRequestsProvider, (_, next) {
        _engine?.updateJokerRequests(next.value ?? const []);
      });
    }

    final engine = _engine;
    final nextSlot = isPlayer && !(me?.caught ?? false) && engine != null
        ? nextPing(engine.visibleSlots, now)
        : null;
    final filterBar = [
      FilterBar(items: filterItems),
      if (filterItems.isNotEmpty) const SizedBox(height: 8),
    ];
    final speedhuntsLeft =
        widget.game.settings.speedhuntCount - speedhunts.length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        // Phase + countdown instead of the app name (field test feedback):
        // the map needs the space.
        // Long-press: engine log for analysing problems in the field.
        title: GestureDetector(
          key: const Key('debugLogTrigger'),
          onLongPress: _showLog,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  key: const Key('gamePhase'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (until != null) ...[
                const SizedBox(width: 10),
                Text(
                  _formatCountdown(until.difference(now)),
                  key: const Key('gameCountdown'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          IconButton(
            key: const Key('overviewButton'),
            tooltip: l10n.overviewTitle,
            icon: const Icon(Icons.groups_outlined),
            onPressed: () => showOverviewSheet(
              context,
              members: members,
              myId: widget.session.userId,
              speedhuntRunning: running != null,
              onRemove: _isAdmin ? _removeMember : null,
            ),
          ),
          if (_isAdmin)
            IconButton(
              key: const Key('endRoundButton'),
              tooltip: l10n.gameEndButton,
              onPressed: _ending ? null : _endRound,
              icon: const Icon(Icons.flag_outlined),
            ),
        ],
      ),
      body: Stack(
        children: [
          BaseMap(
            controller: _map,
            options: MapOptions(
              interactionOptions: northUp,
              initialCenter: fallbackCenter,
              initialZoom: 6,
              initialCameraFit: fitArea(widget.game.settings.area),
            ),
            children: [
              ...layers,
              if (engine != null)
                ValueListenableBuilder(
                  valueListenable: engine.position,
                  builder: (_, fix, _) =>
                      fix == null ? const SizedBox.shrink() : selfLayer(fix),
                ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Players see "next ping in …" on top, above their filters.
                if (!isPlayer) ...filterBar,
                for (final line in [
                  if (nextSlot != null)
                    l10n.gameNextPing(
                      _formatCountdown(nextSlot.at.difference(now)),
                    ),
                  if (me?.caught ?? false) l10n.gameCaughtSelf,
                  if (phase == GamePhase.ended) l10n.gameTimeUpHint,
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _InfoChip(icon: Icons.schedule, text: line),
                  ),
                if (isPlayer) ...filterBar,
                if (engine != null)
                  ValueListenableBuilder(
                    valueListenable: engine.status,
                    builder: (_, status, _) => _TrackingStatusLine(
                      status: status,
                      isPlayer: isPlayer,
                      onRetry: engine.retry,
                    ),
                  ),
                if (running != null) ...[
                  const SizedBox(height: 8),
                  _SpeedhuntBanner(
                    // Countdown to the next speedhunt ping – the same for
                    // everyone, so it reveals no target (R-SPEED-08).
                    text: switch (nextSpeedhuntPing(running, now)) {
                      (:final number, :final at) => l10n.gameSpeedhuntNext(
                        number,
                        running.pings,
                        _formatCountdown(at.difference(now)),
                      ),
                      null => l10n.speedhuntActive,
                    },
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  key: const Key('fitAreaButton'),
                  heroTag: 'fitArea',
                  tooltip: l10n.settingsArea,
                  backgroundColor: AppColors.surface,
                  onPressed: _showArea,
                  child: const Icon(Icons.crop_free),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  key: const Key('myLocationButton'),
                  heroTag: 'myLocation',
                  tooltip: l10n.areaMyLocation,
                  backgroundColor: AppColors.surface,
                  onPressed: _showMe,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          if (_banner case final banner?)
            Positioned(
              left: 12,
              right: 68, // leave room for the map buttons
              bottom: 12,
              child: _NoticeBanner(title: banner.title, body: banner.body),
            ),
        ],
      ),
      bottomNavigationBar: me == null || clock == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    if (isHunter) ...[
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('catchButton'),
                          onPressed: () => _reportCatchAsHunter(members),
                          icon: const Icon(Icons.back_hand_outlined),
                          label: Text(l10n.catchTitle),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('speedhuntButton'),
                          onPressed: speedhuntsLeft > 0
                              ? () =>
                                    _startSpeedhunt(clock, members, speedhunts)
                              : null,
                          icon: const Icon(Icons.bolt),
                          label: Text(l10n.speedhuntButton(speedhuntsLeft)),
                        ),
                      ),
                    ],
                    if (isPlayer && !me.caught) ...[
                      if (widget.game.settings.jokerEnabled ||
                          widget.game.settings.playerJokerEnabled) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('jokerButton'),
                            onPressed: _jokersLeft(me)
                                ? () => _openJokers(me)
                                : null,
                            icon: const Icon(Icons.visibility_outlined),
                            label: Text(l10n.jokerButton),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('selfCatchButton'),
                          onPressed: _reportSelfCatch,
                          icon: const Icon(Icons.back_hand_outlined),
                          label: Text(l10n.catchSelfTitle),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

String _formatCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = two(d.inMinutes % 60);
  final s = two(d.inSeconds % 60);
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Visible to everyone while a speedhunt runs (R-SPEED-05).
class _SpeedhuntBanner extends StatelessWidget {
  const _SpeedhuntBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('speedhuntBanner'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.speedhunt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: Colors.black),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hunter),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.hunter),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// In-app notification banner (R-NOTIF-01).
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('noticeBanner'),
      color: AppColors.surfaceHigh,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.notifications_active, color: AppColors.speedhunt),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (body case final body?)
                    Text(
                      body,
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

/// Shows whether tracking and pinging work, so problems are visible in the
/// field (no silent failures).
class _TrackingStatusLine extends StatelessWidget {
  const _TrackingStatusLine({
    required this.status,
    required this.isPlayer,
    required this.onRetry,
  });

  final EngineStatus status;
  final bool isPlayer;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, color, text) = switch (status.state) {
      TrackingState.off => (null, null, null),
      TrackingState.waiting => (
        Icons.gps_not_fixed,
        AppColors.speedhunt,
        l10n.trackingWaiting,
      ),
      // Only problems are shown – "GPS ok" just took space (field test).
      TrackingState.ok => (null, null, null),
      TrackingState.noPermission => (
        Icons.location_disabled,
        Colors.redAccent,
        l10n.trackingNoPermission,
      ),
      TrackingState.error => (
        Icons.gps_off,
        Colors.redAccent,
        l10n.trackingError,
      ),
    };
    if (text == null) return const SizedBox.shrink();
    final error = status.lastError;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        key: const Key('trackingStatus'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(text)),
                if (status.state == TrackingState.noPermission)
                  TextButton(
                    key: const Key('trackingRetry'),
                    onPressed: onRetry,
                    child: Text(l10n.commonRetry),
                  ),
              ],
            ),
            if (error != null)
              Text(
                error,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
