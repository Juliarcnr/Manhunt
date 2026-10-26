import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:intl/intl.dart';

import '../../core/history/round_summary.dart';
import '../../core/models/member.dart';
import '../../core/round/boundary_watch.dart';
import '../../core/round/notices.dart';
import '../../core/round/ping_schedule.dart';
import '../../core/round/player_aliases.dart';
import '../../core/round/round_result.dart';
import '../../core/schedule/game_clock.dart';
import '../../core/schedule/speedhunt.dart';
import '../../data/game_repository.dart';
import '../../data/joker_store.dart';
import '../../data/location_service.dart';
import '../../l10n/app_localizations.dart';
import '../../state/bots.dart';
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

  BotSquad? _bots;

  final _map = MapController();
  final _subscriptions = <ProviderSubscription<Object?>>[];
  StreamSubscription<PingSlot>? _pingsSentSub;
  StreamSubscription<BoundaryEvent>? _boundarySub;
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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      // The time running out is no event, so check every second.
      _checkRoundOver();
      setState(() {});
    });
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
    // Computer members carried by this phone walk around it (R-BOT-05).
    if (ref.read(botsEnabledProvider)) {
      _bots = BotSquad(
        session: widget.session,
        backend: ref.read(botBackendProvider),
        anchor: () => _engine?.position.value,
        notice: engine.notice,
        now: widget.now,
        onLog: engine.note,
      );
    }
    _pingsSentSub = engine.pingsSent.listen(
      (slot) => _notify(PingSentNotice(slot.kind)),
    );
    _boundarySub = engine.boundaryEvents.listen(
      (event) => _notify(OwnBoundaryNotice(event)),
    );
    // Location first, then notifications: Android drops a permission dialog
    // requested while another one is open (field test 2026-10-05).
    unawaited(_requestPermissions());
    unawaited(_loadJokers());

    _subscriptions
      ..add(
        ref.listenManual<AsyncValue<List<Member>>>(membersProvider, (_, next) {
          if (next.value case final members?) unawaited(_bots?.update(members));
          _feedEngine();
          _checkRoundOver();
        }, fireImmediately: true),
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
          if (catches == null) return;
          for (final notice in _notices.onCatches(catches)) {
            if (notice is ReleaseNotice) {
              unawaited(_announceRelease(notice));
            } else {
              _notify(notice);
            }
          }
        }, fireImmediately: true),
      )
      ..add(
        ref.listenManual<AsyncValue<List<Speedhunt>>>(speedhuntsProvider, (
          _,
          next,
        ) {
          final list = next.value;
          if (list != null) _notices.onSpeedhunts(list).forEach(_notify);
          _feedEngine();
        }, fireImmediately: true),
      );
    engine.speedhuntSnapshots.addListener(_onSpeedhuntSnapshots);
    _feedEngine();
  }

  /// Who won, once the round is over (R-GAME-09); null while the game is on
  /// and while the members are not loaded yet.
  RoundResult? _result(List<Member> members) =>
      roundResult(clock: _clock(), now: widget.now(), members: members);

  /// Announces the winners once when the round becomes over (R-GAME-09). The
  /// first check with loaded members is the baseline: a round already over
  /// when opening the app is not announced again.
  void _checkRoundOver() {
    final members = ref.read(membersProvider).value;
    // Not loaded yet (the first value may be an empty list): no baseline.
    if (members == null || !members.any((m) => m.isPlayer)) return;
    _notices.onRoundOver(_result(members)).forEach(_notify);
  }

  /// "Kim, Sam and Lou".
  String _nameList(List<String> names) => names.length < 2
      ? names.join()
      : AppLocalizations.of(
          context,
        ).nameList(names.sublist(0, names.length - 1).join(', '), names.last);

  /// Real names of the winning players (R-ANON-02: the round is over).
  String _winnerNames(PlayersWon result, List<Member> members) {
    final names = {for (final m in members) m.id: m.name};
    return _nameList([for (final id in result.playerIds) names[id] ?? '?']);
  }

  /// The player's own ⚡ pings (R-SPEED-09) as ping records, oldest first.
  List<PingRecord> _ownSpeedhuntPings() => [
    for (final e
        in _engine?.speedhuntSnapshots.value.entries ??
            const <MapEntry<String, LocationFix>>[])
      PingRecord(
        playerId: widget.session.userId,
        kind: PingKind.speedhunt,
        slotId: e.key,
        fix: e.value,
      ),
  ];

  /// Filter id of a speedhunt on this device, as [SpeedhuntPings.id].
  String _ownSpeedhuntId(Speedhunt s) =>
      '${widget.session.userId}_${s.startedAt.millisecondsSinceEpoch}';

  List<PingRecord> _knownSpeedhuntPings = const [];

  /// A new own ⚡ ping switches its speedhunt's chip back on (R-SPEED-09,
  /// like R-HUNT-08) and is kept on the device.
  void _onSpeedhuntSnapshots() {
    final pings = _ownSpeedhuntPings();
    final fresh = speedhuntsWithNewPings(_knownSpeedhuntPings, pings);
    _knownSpeedhuntPings = pings;
    if (!mounted) return;
    setState(() {
      if (_filters.hiddenSpeedhunts.any(fresh.contains)) {
        _filters = _filters.copyWith(
          hiddenSpeedhunts: _filters.hiddenSpeedhunts.difference(fresh),
        );
      }
    });
    unawaited(_saveJokers());
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
    speedhunts: ref.read(speedhuntsProvider).value ?? const [],
  );

  @override
  void didUpdateWidget(GameScreen old) {
    super.didUpdateWidget(old);
    _feedEngine();
    // The hunters' win arrives with the game (R-GAME-08).
    _checkRoundOver();
    // The start time arrives a moment after "start" (server timestamp).
    unawaited(_loadJokers());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _lifecycle = state;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine?.speedhuntSnapshots.removeListener(_onSpeedhuntSnapshots);
    _ticker?.cancel();
    _map.dispose();
    _bannerTimer?.cancel();
    for (final t in _retryTimers.values) {
      t.cancel();
    }
    for (final s in _subscriptions) {
      s.close();
    }
    unawaited(_pingsSentSub?.cancel());
    unawaited(_boundarySub?.cancel());
    // The bots first: they report into the own engine's log.
    final bots = _bots;
    final engine = _engine;
    unawaited(() async {
      await bots?.dispose();
      await engine?.dispose();
    }());
    super.dispose();
  }

  /// Names as shown on this device: hunters see "Player 3" instead of the
  /// players' names until the time is up (R-ANON-01 … R-ANON-03).
  Map<String, String> _displayNames(
    List<Member> members, {
    required bool isHunter,
    required GamePhase phase,
  }) {
    final l10n = AppLocalizations.of(context);
    final aliases = completeAliases(widget.game.aliases, [
      for (final m in members)
        if (m.isPlayer) m.id,
    ]);
    final anonymous = showAliases(
      enabled: widget.game.settings.anonymousPlayers,
      isHunter: isHunter,
      phase: phase,
    );
    return {
      for (final m in members)
        m.id: anonymous && m.isPlayer
            ? l10n.playerAlias(aliases[m.id]!)
            : m.name,
    };
  }

  /// Null while the start time is still missing (server timestamp).
  GameClock? _clock() {
    final startAt = widget.game.startAt;
    if (startAt == null) return null;
    return GameClock(
      startAt: startAt,
      settings: widget.game.settings,
      finishedAt: widget.game.finishedAt,
    );
  }

  GamePhase _phaseNow() =>
      _clock()?.phaseAt(widget.now()) ?? GamePhase.notStarted;

  final _retryTimers = <ProviderOrFamily, Timer>{};

  /// The rules let players read all positions only once the server's clock
  /// says the round is over (R-GAME-06); this phone's clock may be a little
  /// ahead. So a refused stream is simply opened again a bit later.
  void _retryOnError(ProviderOrFamily provider, AsyncValue<Object?> next) {
    if (!next.hasError || _retryTimers.containsKey(provider)) return;
    _retryTimers[provider] = Timer(const Duration(seconds: 5), () {
      _retryTimers.remove(provider);
      if (mounted) ref.invalidate(provider);
    });
  }

  Member? _me(List<Member>? members) {
    for (final m in members ?? const <Member>[]) {
      if (m.id == widget.session.userId) return m;
    }
    return null;
  }

  /// "Back in the game" (R-CATCH-05). Ending a round deletes all catches too,
  /// but only after the group is back in the lobby – so check the (plain)
  /// status first; the decrypted [GameInfo] may still lag behind.
  Future<void> _announceRelease(ReleaseNotice notice) async {
    final status = await ref
        .read(gameRepositoryProvider)
        .watchStatus(widget.session.groupId)
        .first;
    if (status == GameStatus.running) _notify(notice);
  }

  /// In-app banner + vibration in the foreground, system notification in the
  /// background (R-NOTIF-01).
  void _notify(GameNotice notice) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final members = ref.read(membersProvider).value;
    final names = {for (final m in members ?? const <Member>[]) m.id: m.name};
    // Players also get their own ⚡ pings (R-SPEED-09); tell them that this
    // does not mean the speedhunt is on them (R-NOTIF-06).
    final isPlayer = !(_me(members)?.isHunter ?? true);
    final (title, body) = switch (notice) {
      CatchNotice(:final record) => (
        l10n.noticeCaught(names[record.playerId] ?? '?'),
        null,
      ),
      // Real name for everyone, like the catch (R-CATCH-05).
      ReleaseNotice(:final playerId) => (
        playerId == widget.session.userId
            ? l10n.noticeReleasedSelf
            : l10n.noticeReleased(names[playerId] ?? '?'),
        null,
      ),
      SpeedhuntNotice(:final speedhunt) => (
        l10n.noticeSpeedhunt,
        [
          l10n.noticeSpeedhuntBody(
            speedhunt.pings,
            speedhunt.interval.inMinutes,
          ),
          if (isPlayer) l10n.noticeSpeedhuntPlayerHint,
        ].join(' '),
      ),
      PingSentNotice() => (
        widget.game.settings.sharedPings
            ? l10n.noticePingSentAll
            : l10n.noticePingSent,
        null,
      ),
      // Only hunters get it; anonymous like everything else they see
      // (R-ANON-01).
      PlayerOutsideNotice(:final playerId) => (
        l10n.noticePlayerOutside(
          _displayNames(
                members ?? const [],
                isHunter: true,
                phase: _phaseNow(),
              )[playerId] ??
              '?',
        ),
        l10n.noticePlayerOutsideBody,
      ),
      OwnBoundaryNotice(:final event) => switch (event) {
        BoundaryEvent.warning => (
          l10n.noticeOutsideWarning,
          l10n.noticeOutsideWarningBody(outsideGrace.inSeconds),
        ),
        BoundaryEvent.live => (
          l10n.noticeOutsideLive,
          l10n.noticeOutsideLiveBody(outsideAfterglow.inSeconds),
        ),
        BoundaryEvent.ended => (l10n.noticeOutsideEnded, null),
      },
      RoundOverNotice(result: HuntersWon()) => (
        l10n.noticeHuntersWon,
        l10n.gameTimeUpHint,
      ),
      RoundOverNotice(result: final PlayersWon result) => (
        l10n.noticePlayersWon(
          _winnerNames(result, members ?? const []),
          result.playerIds.length,
        ),
        l10n.gameTimeUpHint,
      ),
    };
    // The own boundary state has its own permanent banner (R-OUT-06).
    final banner = notice is! OwnBoundaryNotice;
    final notifications = ref.read(notificationServiceProvider);
    if (_lifecycle == AppLifecycleState.resumed) {
      // App open: own banner + vibration always (also when muted); the
      // system notification only adds the sound, which the OS plays only if
      // the phone is not muted (R-NOTIF-05).
      unawaited(HapticFeedback.vibrate());
      unawaited(
        notifications.show(title: title, body: body ?? '', foreground: true),
      );
      if (!banner) return;
      _bannerTimer?.cancel();
      setState(() => _banner = (title: title, body: body));
      _bannerTimer = Timer(noticeBannerDuration(notice), () {
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
    // After the hunters won the round is over already (R-GAME-08).
    final endAt = _clock()?.endAt;
    final now = widget.now();
    final early = endAt != null && now.isBefore(endAt);

    if (early) {
      if (!await _confirm(
        icon: Icons.warning_amber_rounded,
        color: AppColors.speedhunt,
        title: l10n.gameAbortTitle,
        text: l10n.gameAbortText(formatCountdown(endAt.difference(now))),
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

  /// Host takes back a wrongly reported catch (R-CATCH-04). [m] carries the
  /// name as this device shows it.
  Future<void> _undoCatch(Member m) async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirm(
      icon: Icons.undo,
      color: AppColors.player,
      title: l10n.undoCatchTitle(m.name),
      text: l10n.undoCatchText,
      action: l10n.undoCatchConfirm,
      actionKey: const Key('confirmUndoCatch'),
    )) {
      return;
    }
    await _run(
      () => ref.read(gameRepositoryProvider).undoCatch(widget.session, m.id),
    );
  }

  Future<void> _reportCatchAsHunter(List<Member> members) async {
    final playerId = await showHunterCatchDialog(context, members: members);
    if (playerId == null) return;
    await _catchIfConfirmed(playerId);
  }

  Future<void> _reportSelfCatch() async {
    if (!await showSelfCatchDialog(context)) return;
    await _catchIfConfirmed(widget.session.userId);
  }

  /// Catching the last player while the game is on ends it: the hunters won
  /// (R-GAME-08). That cannot be undone, so it needs an extra confirmation.
  Future<void> _catchIfConfirmed(String playerId) async {
    final members = ref.read(membersProvider).value ?? const <Member>[];
    final phase = _phaseNow();
    final finishes =
        (phase == GamePhase.headStart || phase == GamePhase.hunting) &&
        isLastPlayer(members, playerId);
    if (finishes) {
      final l10n = AppLocalizations.of(context);
      if (!await _confirm(
        icon: Icons.emoji_events_outlined,
        color: AppColors.hunter,
        title: l10n.lastCatchTitle,
        text: l10n.lastCatchText,
        action: l10n.lastCatchConfirm,
        actionKey: const Key('confirmLastCatch'),
      )) {
        return;
      }
    }
    await _run(() => _recordCatch(playerId, finishes: finishes));
  }

  /// A catch of the speedhunt target ends the speedhunt (R-SPEED-10). Hunters
  /// and the caught player may look up the target; the catch names the
  /// speedhunt so everyone else learns it ended.
  Future<void> _recordCatch(String playerId, {bool finishes = false}) async {
    final at = widget.now().toUtc();
    final onTarget = await ref
        .read(roundRepositoryProvider)
        .speedhuntsOn(widget.session, playerId);
    await ref
        .read(gameRepositoryProvider)
        .recordCatch(
          widget.session,
          CatchRecord(
            playerId: playerId,
            at: at,
            endsSpeedhunt: speedhuntEndedByCatch(onTarget, at),
          ),
          finishes: finishes,
        );
  }

  /// [members]: players in the order and with the [names] hunters see them
  /// (R-ANON-01). [targeted]: [previous] with their targets (R-SET-19).
  Future<void> _startSpeedhunt(
    GameClock clock,
    List<Member> members,
    Map<String, String> names,
    List<Speedhunt> previous,
    List<Speedhunt> targeted,
  ) async {
    final l10n = AppLocalizations.of(context);
    String denialText(SpeedhuntDenial d, [String? targetId]) {
      final now = widget.now();
      final until = switch (d) {
        SpeedhuntDenial.targetCoolingDown => speedhuntTargetBlock(
          settings: clock.settings,
          previous: targeted,
          targetId: targetId!,
          now: now,
        )?.until,
        _ => nextSpeedhuntAt(clock, previous),
      };
      return speedhuntDenialText(
        l10n,
        d,
        remaining: until?.difference(now) ?? Duration.zero,
        targetName:
            names[targetId] ??
            members.where((m) => m.id == targetId).firstOrNull?.name ??
            '',
      );
    }

    // Check time/count/running first, so nobody picks a target in vain.
    final early = canStartSpeedhunt(
      clock: clock,
      now: widget.now(),
      previous: previous,
      target: const Member(id: '', name: '', role: Role.player),
    );
    if (early != null) {
      _snack(denialText(early));
      return;
    }
    final targetId = await showSpeedhuntDialog(
      context,
      members: members,
      names: names,
      settings: widget.game.settings,
      targeted: targeted,
      now: widget.now,
    );
    if (targetId == null || !mounted) return;
    final denial = canStartSpeedhunt(
      clock: clock,
      now: widget.now(),
      previous: previous,
      target: members.firstWhere((m) => m.id == targetId),
      targeted: targeted,
    );
    if (denial != null) {
      _snack(denialText(denial, targetId));
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
      playersEnabled: settings.playerJokerAvailable,
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

  /// Joker results and own ⚡ pings are kept on the device, so they can be
  /// shown again later – also after an app restart (R-PLAY-04, R-SPEED-09).
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
            speedhuntPings: _engine?.speedhuntSnapshots.value ?? const {},
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
    _engine?.restoreSpeedhuntSnapshots(saved.speedhuntPings);
  }

  DateTime? _jokersLoadedFor;

  bool _jokersLeft(Member me) {
    final s = widget.game.settings;
    return (s.jokerEnabled && !me.jokerUsed) ||
        (s.playerJokerAvailable && !me.playerJokerUsed);
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
    final membersById = {for (final m in members) m.id: m};
    final caught = {
      for (final m in members)
        if (m.caught) m.id,
    };
    final speedhunts = ref.watch(speedhuntsProvider).value ?? const [];
    final isHunter = me?.isHunter ?? false;
    final isPlayer = me?.isPlayer ?? false;

    // startAt is a server timestamp and briefly null right after "start".
    final clock = _clock();
    final now = widget.now();
    final phase = clock?.phaseAt(now) ?? GamePhase.notStarted;
    final running = activeSpeedhunt(speedhunts, now);
    // Once the time is up, caught players are split up again (R-HUNT-11).
    final caughtNow = caughtOnMap(caught, phase);

    // Anonymous players (R-ANON-01): hunters see "Player 3" instead of the
    // name until the time is up (R-ANON-02); players always see names
    // (R-ANON-03). Chips and colours follow the numbers, not the join order,
    // so neither gives a player away.
    final settings = widget.game.settings;
    final playerIds = [
      for (final m in members)
        if (m.isPlayer) m.id,
    ];
    final orderedPlayers = settings.anonymousPlayers
        ? byAlias(widget.game.aliases, playerIds)
        : playerIds;
    final aliases = completeAliases(widget.game.aliases, playerIds);
    final names = _displayNames(members, isHunter: isHunter, phase: phase);
    final playersByColor = playerColors(orderedPlayers);

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
      GamePhase.ended => (
        // Who won; the names are in the overview (R-GAME-09).
        switch (_result(members)) {
          PlayersWon(:final playerIds) => l10n.gamePhasePlayersWon(
            playerIds.length,
          ),
          HuntersWon() => l10n.gamePhaseHuntersWon,
          null => l10n.gamePhaseTimeUp,
        },
        AppColors.speedhunt,
        null,
      ),
    };

    // Role-specific map content. Hunter-only data is only watched by hunters
    // (the security rules reject it for players) – and by everyone once the
    // round is over: then all see what the hunters see (R-GAME-06).
    final layers = <Widget>[...areaLayers(widget.game.settings.area)];
    final filters = _filters;
    final filterItems = <FilterItem>[];
    if (isHunter || (isPlayer && phase == GamePhase.ended)) {
      if (!isHunter) {
        ref
          ..listen(allPingsProvider, (_, next) {
            _retryOnError(allPingsProvider, next);
          })
          ..listen(hunterLocationsProvider, (_, next) {
            _retryOnError(hunterLocationsProvider, next);
          });
      }
      final pings = ref.watch(allPingsProvider).value ?? const [];
      // New regular pings switch "last pings" back on, new speedhunt pings
      // their speedhunt's chip (R-HUNT-08).
      ref.listen(allPingsProvider, (previous, next) {
        final pings = next.value;
        if (pings == null) return;
        var f = _filters;
        if (!f.lastPings && hasNewRegularPing(previous?.value, pings)) {
          f = f.copyWith(lastPings: true);
        }
        final fresh = speedhuntsWithNewPings(previous?.value, pings);
        if (f.hiddenSpeedhunts.any(fresh.contains)) {
          f = f.copyWith(
            hiddenSpeedhunts: f.hiddenSpeedhunts.difference(fresh),
          );
        }
        if (!identical(f, _filters)) setState(() => _filters = f);
      });
      final hunters =
          ref.watch(hunterLocationsProvider).value ??
          const <String, LocationFix>{};
      final byPlayer = pingsByPlayer(pings);
      // Caught players lose their own chips; the "caught" chip shows all of
      // them at once (R-HUNT-09).
      final selected = {
        for (final id in filters.playerHistories.keys)
          if (byPlayer.containsKey(id) && !caughtNow.contains(id)) id,
      };
      final caughtShown = {
        if (filters.caught)
          for (final id in caughtNow)
            if (byPlayer.containsKey(id)) id,
      };
      layers.addAll(
        pathLayers({
          for (final id in selected)
            if (filters.historyOf(id) == HistoryMode.lines) id: byPlayer[id]!,
        }, playersByColor),
      );
      for (final id in {...selected, ...caughtShown}) {
        layers.add(
          historyLayer(
            byPlayer[id]!,
            color: playersByColor[id] ?? AppColors.player,
            keyPrefix: 'history_$id',
          ),
        );
      }
      final speedhuntGroups = speedhuntsFromPings(pings);
      layers.add(
        speedhuntPingsLayer(
          pings: [
            for (final s in speedhuntGroups)
              if (caughtNow.contains(s.playerId)
                  ? filters.caught
                  : !filters.hiddenSpeedhunts.contains(s.id))
                ...s.pings,
          ],
          colors: playersByColor,
          names: names,
        ),
      );
      if (filters.lastPings) {
        layers.add(
          lastPingsLayer(
            // Shown histories contain the last ping; caught players appear
            // only under "caught" (R-HUNT-03, R-HUNT-09).
            pings: lastRegularPings(
              byPlayer,
              skip: {...selected, ...caughtNow},
            ),
            names: names,
            colors: playersByColor,
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
      // Players outside the play area, live (R-OUT-05) – always shown, on
      // top. Caught players are left out, their devices stop sharing anyway.
      // Hunters only: players never see them (and they end with the time).
      if (isHunter) {
        final outside = {
          for (final e
              in (ref.watch(outsideLocationsProvider).value ??
                      const <String, LocationFix>{})
                  .entries)
            if (!caught.contains(e.key)) e.key: e.value,
        };
        ref.listen(outsideLocationsProvider, (_, next) {
          final ids = next.value?.keys;
          if (ids == null) return;
          final caughtIds = {
            for (final m in ref.read(membersProvider).value ?? const <Member>[])
              if (m.caught) m.id,
          };
          _notices
              .onOutside(ids.where((id) => !caughtIds.contains(id)))
              .forEach(_notify);
        });
        layers.add(
          outsidePlayersLayer(
            positions: outside,
            names: names,
            colors: playersByColor,
            liveLabel: l10n.outsideLiveBadge,
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
        // Tap cycles: points → points with lines → off (R-HUNT-04, R-HUNT-05).
        for (final id in orderedPlayers)
          if (!caughtNow.contains(id))
            FilterItem(
              id: 'player_$id',
              label: names[id] ?? '?',
              icon: filters.historyOf(id) == HistoryMode.lines
                  ? Icons.timeline
                  : null,
              color: playersByColor[id] ?? AppColors.player,
              selected: filters.historyOf(id) != HistoryMode.off,
              onChanged: (_) => set(filters.cyclePlayer(id)),
            ),
        // All caught players in one chip (R-HUNT-09).
        if (caughtNow.isNotEmpty)
          FilterItem(
            id: 'caught',
            label: l10n.filterCaught,
            icon: Icons.person_off,
            color: AppColors.textMuted,
            selected: filters.caught,
            onChanged: (v) => set(filters.copyWith(caught: v)),
          ),
        // One chip per speedhunt, e.g. "⚡ Sam 18:35" (R-HUNT-07).
        for (final s in speedhuntGroups)
          if (!caughtNow.contains(s.playerId))
            FilterItem(
              id: 'speedhunt_${s.id}',
              label: l10n.filterSpeedhunt(
                names[s.playerId] ?? '?',
                timeFmt.format(s.startedAt.toLocal()),
              ),
              icon: Icons.bolt,
              color: playersByColor[s.playerId] ?? AppColors.player,
              selected: !filters.hiddenSpeedhunts.contains(s.id),
              onChanged: (_) => set(filters.toggleSpeedhunt(s.id)),
            ),
      ]);
    } else if (isPlayer) {
      final mine = pingsByPlayer(
        ref.watch(myPingsProvider).value ?? const [],
      )[widget.session.userId];
      if (mine != null && filters.myPings) {
        // Own speedhunt pings stay hidden (R-SPEED-04): the history only
        // shows regular pings.
        layers.add(historyLayer(mine, color: AppColors.player));
      }
      // Regular pings to everyone (R-PLAY-05): only the latest ping of each
      // other player, caught ones greyed out until newer pings arrive. The
      // rules reject this stream without the setting.
      final sharedPings = widget.game.settings.sharedPings;
      if (sharedPings) {
        ref.listen(sharedPingsProvider, (previous, next) {
          final pings = next.value;
          if (pings != null &&
              !_filters.sharedPings &&
              hasNewRegularPing(previous?.value, pings)) {
            setState(() => _filters = _filters.copyWith(sharedPings: true));
          }
        });
        if (filters.sharedPings) {
          layers.add(
            lastPingsLayer(
              pings: sharedLastPings(
                pingsByPlayer(ref.watch(sharedPingsProvider).value ?? const []),
                caught: caughtNow,
                skip: {widget.session.userId},
              ),
              names: names,
              colors: playersByColor,
              greyed: caughtNow,
            ),
          );
        }
      }
      // Own position at every speedhunt ping time, ⚡1/⚡2/⚡3 – on every
      // player's phone, target or not (R-SPEED-09).
      layers.add(
        speedhuntPingsLayer(
          pings: [
            for (final s in speedhuntsFromPings(_ownSpeedhuntPings()))
              if (!filters.hiddenSpeedhunts.contains(s.id)) ...s.pings,
          ],
          colors: {widget.session.userId: AppColors.player},
          names: names,
        ),
      );
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
        if (sharedPings)
          FilterItem(
            id: 'sharedPings',
            label: l10n.filterSharedPings,
            icon: Icons.location_on,
            selected: filters.sharedPings,
            onChanged: (v) => set(filters.copyWith(sharedPings: v)),
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
        // Every player gets the same chip per speedhunt, with its first ping
        // like the hunters – without name, so it reveals no target
        // (R-SPEED-09, R-SPEED-04). It switches the own ⚡ pings.
        for (final s in speedhuntsWithFirstPing(speedhunts, now))
          if (_ownSpeedhuntId(s) case final id)
            FilterItem(
              id: 'speedhunt_$id',
              label: timeFmt.format(s.startedAt.toLocal()),
              icon: Icons.bolt,
              color: AppColors.speedhunt,
              selected: !filters.hiddenSpeedhunts.contains(id),
              onChanged: (_) => set(filters.toggleSpeedhunt(id)),
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
    // Hunters: when the next regular pings of all players arrive (R-HUNT-10).
    final nextRegular = isHunter ? clock?.nextRegularPing(now) : null;
    final infoLines = [
      if (nextSlot != null)
        l10n.gameNextPing(formatCountdown(nextSlot.at.difference(now))),
      if (nextRegular != null)
        l10n.gameNextPings(formatCountdown(nextRegular.difference(now))),
      // Once the round is over the time-up hint says enough.
      if ((me?.caught ?? false) && phase != GamePhase.ended)
        l10n.gameCaughtSelf,
      if (phase == GamePhase.ended) l10n.gameTimeUpHint,
    ];
    // Below the filters the same gap as above them: the info lines if any,
    // the app bar (top inset of the overlay) otherwise.
    final filterGap = infoLines.isNotEmpty ? 6.0 : 12.0;
    final filterBar = [
      FilterBar(items: filterItems),
      if (filterItems.isNotEmpty) SizedBox(height: filterGap),
    ];
    final speedhuntsLeft =
        widget.game.settings.speedhuntCount - speedhunts.length;
    // Until the next speedhunt is possible the button is greyed out with a
    // countdown, but stays tappable to tell why (R-SPEED-11).
    final speedhuntWait = switch (clock) {
      final clock? when speedhuntsLeft > 0 && phase != GamePhase.ended =>
        nextSpeedhuntAt(clock, speedhunts).difference(now),
      _ => Duration.zero,
    };
    // Targets for the per-player rules (R-SET-19); hunters only.
    final targeted = isHunter
        ? ref.watch(speedhuntsWithTargetsProvider).value ?? const <Speedhunt>[]
        : const <Speedhunt>[];

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
                  formatCountdown(until.difference(now)),
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
              // Players learn which number the hunters see (R-ANON-04).
              myAlias: isPlayer && settings.anonymousPlayers
                  ? l10n.playerAlias(aliases[widget.session.userId]!)
                  : null,
              speedhuntRunning: running != null,
              // Who won, once the round is over (R-GAME-09).
              winner: switch (_result(members)) {
                null => null,
                HuntersWon() => l10n.overviewHuntersWon,
                final PlayersWon r => l10n.overviewPlayersWon(
                  _winnerNames(r, members),
                  r.playerIds.length,
                ),
              },
              winnerIds: switch (_result(members)) {
                null => const {},
                final r => winnerIds(r, members),
              },
              // Irreversible once the hunters won (R-GAME-08).
              onUndoCatch: _isAdmin && !(clock?.huntersWon ?? false)
                  ? _undoCatch
                  : null,
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
                // Outside the play area: as long as the hunters see (or are
                // about to see) the live location, the player sees it at the
                // very top (R-OUT-06).
                if (engine != null && isPlayer)
                  ValueListenableBuilder(
                    valueListenable: engine.boundary,
                    builder: (_, boundary, _) =>
                        _OutsideBanner(state: boundary, now: now),
                  ),
                // "Next ping(s) in …" on top, above the filters.
                for (final line in infoLines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _InfoChip(icon: Icons.schedule, text: line),
                  ),
                ...filterBar,
                if (engine != null)
                  ValueListenableBuilder(
                    valueListenable: engine.status,
                    builder: (_, status, _) => _TrackingStatusLine(
                      status: status,
                      isPlayer: isPlayer,
                      onRetry: engine.retry,
                    ),
                  ),
                if (running != null)
                  _SpeedhuntBanner(
                    // Countdown to the next speedhunt ping – the same for
                    // everyone, so it reveals no target (R-SPEED-08).
                    text: switch (nextSpeedhuntPing(running, now)) {
                      (:final number, :final at) => l10n.gameSpeedhuntNext(
                        number,
                        running.pings,
                        formatCountdown(at.difference(now)),
                      ),
                      null => l10n.speedhuntActive,
                    },
                  ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
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
                              ? () => _startSpeedhunt(
                                  clock,
                                  [
                                    for (final id in orderedPlayers)
                                      membersById[id]!,
                                  ],
                                  names,
                                  speedhunts,
                                  targeted,
                                )
                              : null,
                          style: speedhuntWait > Duration.zero
                              ? OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.textMuted,
                                )
                              : null,
                          icon: const Icon(Icons.bolt),
                          label: Text(
                            speedhuntWait > Duration.zero
                                ? l10n.speedhuntButtonWait(
                                    speedhuntsLeft,
                                    formatCountdown(speedhuntWait),
                                  )
                                : l10n.speedhuntButton(speedhuntsLeft),
                          ),
                        ),
                      ),
                    ],
                    if (isPlayer && !me.caught) ...[
                      // Jokers are pointless once all positions are open.
                      if (phase != GamePhase.ended &&
                          (widget.game.settings.jokerEnabled ||
                              widget.game.settings.playerJokerAvailable)) ...[
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

/// The player is outside the play area (R-OUT-06): warning with countdown,
/// then – as long as the hunters see the live location – a permanent notice.
class _OutsideBanner extends StatelessWidget {
  const _OutsideBanner({required this.state, required this.now});

  final BoundaryState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, text) = switch (state.phase) {
      BoundaryPhase.inside => (null, null),
      BoundaryPhase.warning => (
        Icons.warning_amber_rounded,
        l10n.outsideWarning(formatCountdown(state.liveAt!.difference(now))),
      ),
      BoundaryPhase.live => (Icons.wifi_tethering, l10n.outsideLive),
      BoundaryPhase.afterglow => (
        Icons.wifi_tethering,
        l10n.outsideAfterglow(
          formatCountdown(state.afterglowUntil!.difference(now)),
        ),
      ),
    };
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: Key('outsideBanner_${state.phase.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.outside,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
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
    // Gap below, so whatever follows (speedhunt banner) keeps its distance.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
