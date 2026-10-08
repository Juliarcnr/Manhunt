import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/foundation.dart';

import '../core/geo/polygon.dart';
import '../core/models/geo_point.dart';
import '../core/models/member.dart';
import '../core/round/boundary_watch.dart';
import '../core/round/joker.dart';
import '../core/round/ping_schedule.dart';
import '../core/schedule/game_clock.dart';
import '../core/schedule/speedhunt.dart';
import '../data/game_repository.dart';
import '../data/location_service.dart';
import '../data/round_repository.dart';

enum TrackingState {
  /// Not needed right now (lobby, caught, time up, hunter/player not set).
  off,

  /// Tracking requested, no position yet.
  waiting,

  /// Positions arrive.
  ok,

  /// Location permission missing or location services off.
  noPermission,

  /// Something failed; the engine retries automatically.
  error,
}

/// What the engine is doing – shown in the game screen so problems in the
/// field are visible instead of silently losing pings.
@immutable
class EngineStatus {
  const EngineStatus({
    this.state = TrackingState.off,
    this.lastFixAt,
    this.lastPingAt,
    this.lastError,
  });

  final TrackingState state;
  final DateTime? lastFixAt;
  final DateTime? lastPingAt;
  final String? lastError;

  EngineStatus copyWith({
    TrackingState? state,
    DateTime? lastFixAt,
    DateTime? lastPingAt,
    String? lastError,
    bool clearError = false,
  }) => EngineStatus(
    state: state ?? this.state,
    lastFixAt: lastFixAt ?? this.lastFixAt,
    lastPingAt: lastPingAt ?? this.lastPingAt,
    lastError: clearError ? null : lastError ?? this.lastError,
  );
}

/// Drives this device during a running round, without any server:
/// - tracks the location only while needed (R-PRIV-04),
/// - players: sends every due ping automatically (R-PING-01, R-SPEED-03),
/// - hunters: shares the live position with the other hunters (R-HUNT-02),
/// - players outside the play area: warns them and, if they stay outside,
///   shares their live position with the hunters (R-OUT-01 … R-OUT-04).
///
/// Feed it with [update] whenever game, own member or speedhunts change.
class RoundEngine {
  RoundEngine({
    required this.session,
    required this.rounds,
    required this.location,
    required this.notice,
    DateTime Function()? now,
    this.tickInterval = const Duration(seconds: 5),
    this.hunterUploadInterval = const Duration(seconds: 15),
    this.outsideUploadInterval = const Duration(seconds: 5),
  }) : _now = now ?? DateTime.now;

  /// A position older than this is not used for a ping; a fresh one is
  /// requested directly from the GPS instead.
  static const maxFixAge = Duration(minutes: 2);

  final GroupSession session;
  final RoundRepository rounds;
  final LocationService location;
  final TrackingNotice notice;
  final Duration tickInterval;
  final Duration hunterUploadInterval;
  final Duration outsideUploadInterval;
  final DateTime Function() _now;

  GameInfo? _game;
  Member? _me;
  List<Speedhunt> _speedhuntsOnMe = const [];
  List<Speedhunt> _speedhunts = const [];

  /// The own position at every speedhunt ping time, by slot id – recorded on
  /// every active player's device, target or not, so the ⚡ pings reveal no
  /// target (R-SPEED-09). Stays on the device.
  final speedhuntSnapshots = ValueNotifier<Map<String, LocationFix>>(const {});

  StreamSubscription<LocationFix>? _tracking;
  Timer? _timer;
  LocationFix? _lastFix;
  var _permissionMissing = false;

  /// Latest own position while tracking, for the "you are here" dot.
  final position = ValueNotifier<LocationFix?>(null);

  /// Health of tracking and pinging, for the status line.
  final status = ValueNotifier(const EngineStatus());

  DateTime? _lastUpload;
  var _busy = false;
  final _sent = <String>{};
  final _answered = <String>{};
  List<JokerRequest> _jokerRequests = const [];
  final _pingsSent = StreamController<PingSlot>.broadcast();

  /// Emits after each successfully sent own *regular* ping (R-NOTIF-03).
  /// Speedhunt pings are not announced to the player (R-SPEED-04).
  Stream<PingSlot> get pingsSent => _pingsSent.stream;

  /// Where this player stands relative to the play area (R-OUT-01).
  final boundary = ValueNotifier(const BoundaryState());
  final _boundaryEvents = StreamController<BoundaryEvent>.broadcast();

  /// What the player must be told about leaving the play area (R-OUT-06).
  Stream<BoundaryEvent> get boundaryEvents => _boundaryEvents.stream;

  /// A warning is announced at most this often, so standing near the
  /// buffer's edge does not buzz every few seconds.
  static const warningRepeat = Duration(minutes: 2);
  DateTime? _lastWarningAt;

  /// The own outside position may be online: also true at start, so one
  /// left over from before an app restart gets deleted.
  var _outsideMaybeShared = true;
  DateTime? _lastOutsideUpload;
  var _outsideBusy = false;

  bool get isTracking => _tracking != null;

  GameClock? get _clock {
    final startAt = _game?.startAt;
    final game = _game;
    if (startAt == null || game == null) return null;
    return GameClock(startAt: startAt, settings: game.settings);
  }

  /// This player's ping plan incl. speedhunts; empty for hunters. For display
  /// use [visibleSlots] – speedhunt slots would reveal the target.
  List<PingSlot> get mySlots {
    final clock = _clock;
    if (clock == null || !(_me?.isPlayer ?? false)) return const [];
    return playerPingSlots(clock: clock, speedhuntsOnMe: _speedhuntsOnMe);
  }

  /// Regular pings only – what the player may see (R-SPEED-04).
  List<PingSlot> get visibleSlots => [
    for (final s in mySlots)
      if (s.kind == PingKind.regular) s,
  ];

  bool get _shouldTrack => _notTrackingReason == null;

  /// Why tracking is off right now, or null if it should run (for the log).
  String? get _notTrackingReason {
    final game = _game;
    final me = _me;
    final clock = _clock;
    if (game == null) return 'no game';
    if (me == null) return 'own member unknown';
    if (clock == null) return 'no start time yet';
    if (game.status != GameStatus.running) return 'round not running';
    final phase = clock.phaseAt(_now());
    if (phase != GamePhase.headStart && phase != GamePhase.hunting) {
      return 'phase ${phase.name}';
    }
    if (me.isHunter || (me.isPlayer && !me.caught)) return null;
    return me.caught ? 'caught' : 'role ${me.role.name}';
  }

  /// Recent engine events, newest last – shown in the game screen's debug
  /// view (long-press on the header) to analyse problems in the field.
  final log = ValueNotifier<List<String>>(const []);

  void _log(String message) {
    final t = _now().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final line = '${two(t.hour)}:${two(t.minute)}:${two(t.second)} $message';
    if (kDebugMode) debugPrint('[manhunt] $line');
    final lines = [...log.value, line];
    log.value = lines.length > 80 ? lines.sublist(lines.length - 80) : lines;
  }

  /// [speedhunts] are all public speedhunts (without target), for the own
  /// ⚡ pings of every player (R-SPEED-09).
  void update({
    required GameInfo? game,
    required Member? me,
    required List<Speedhunt> speedhuntsOnMe,
    List<Speedhunt> speedhunts = const [],
  }) {
    _game = game;
    _me = me;
    _speedhuntsOnMe = speedhuntsOnMe;
    _speedhunts = speedhunts;
    _sync();
  }

  /// Snapshots saved on the device before an app restart; they are not
  /// recorded again.
  void restoreSpeedhuntSnapshots(Map<String, LocationFix> saved) {
    if (saved.isEmpty) return;
    speedhuntSnapshots.value = {...saved, ...speedhuntSnapshots.value};
  }

  /// After the user granted the permission (e.g. in the system settings).
  void retry() {
    _permissionMissing = false;
    _sync();
  }

  /// Uploads may still finish after [dispose].
  var _disposed = false;

  void _setStatus(EngineStatus Function(EngineStatus s) change) {
    if (!_disposed) status.value = change(status.value);
  }

  String? _loggedReason = '(start)';

  void _sync() {
    // The timer runs as long as the engine exists: whether to track is
    // re-checked every tick, not only on events. Otherwise a round where the
    // own member data arrived a moment late never started tracking (field
    // test 2026-10-05: "only 'screen opened' in the log").
    _timer ??= Timer.periodic(tickInterval, (_) => unawaited(tick()));
    final reason = _notTrackingReason;
    if (reason != _loggedReason) {
      _loggedReason = reason;
      if (reason != null) _log('not tracking: $reason');
    }
    if (reason != null) {
      _stop();
      return;
    }
    if (_tracking != null || _permissionMissing) return;
    _setStatus(
      (s) => s.copyWith(
        state: _lastFix == null ? TrackingState.waiting : TrackingState.ok,
      ),
    );
    _log('tracking: start');
    _tracking = location
        .track(notice)
        .listen(
          (fix) {
            if (_lastStreamFixAt == null) _log('tracking: first position');
            _lastStreamFixAt = _now();
            _acceptFix(fix);
            // Hunters upload right away when they have no position online yet.
            if (_lastUpload == null) unawaited(tick());
          },
          onError: (Object e) {
            // Never lose tracking silently: show it and restart on the next
            // tick – except for a missing permission, which needs the user.
            _log('tracking: error $e');
            _tracking = null;
            if (e is LocationPermissionMissing) {
              _permissionMissing = true;
              _setStatus((s) => s.copyWith(state: TrackingState.noPermission));
            } else {
              _setStatus(
                (s) => s.copyWith(state: TrackingState.error, lastError: '$e'),
              );
            }
          },
          onDone: () {
            _log('tracking: stream ended');
            _tracking = null;
          },
          cancelOnError: true,
        );
  }

  DateTime? _lastStreamFixAt;
  DateTime? _lastDirectFixAt;

  void _acceptFix(LocationFix fix) {
    _lastFix = fix;
    position.value = fix;
    _setStatus((s) => s.copyWith(state: TrackingState.ok, lastFixAt: fix.at));
    _stepBoundary(fix: fix);
  }

  /// Only uncaught players in a running round, with the setting on
  /// (R-SET-17).
  bool get _watchesBoundary {
    final me = _me;
    final game = _game;
    return _shouldTrack &&
        me != null &&
        me.isPlayer &&
        game != null &&
        game.settings.outsideLiveLocation;
  }

  /// Feeds a new position (or just the passing time) into the boundary
  /// watch (R-OUT-01 … R-OUT-04).
  void _stepBoundary({LocationFix? fix}) {
    if (!_watchesBoundary) {
      _setBoundary(const BoundaryState(), why: 'not watched');
      return;
    }
    final area = _game!.settings.area;
    final before = boundary.value;
    final after = boundaryStep(before, area: area, now: _now(), fix: fix);
    // Did time alone already change the phase (gap, afterglow over)?
    final byTime =
        boundaryStep(before, area: area, now: _now()).phase != before.phase;
    if (fix != null && after.phase == before.phase) _logNearMiss(fix, area);
    _setBoundary(
      after,
      // The position that changed the phase – or why time alone did.
      why: fix != null && !byTime
          ? describeFix(fix, area)
          : switch (before.phase) {
              BoundaryPhase.warning =>
                'no position for '
                    '${maxOutsideFixGap.inSeconds} s',
              BoundaryPhase.afterglow => '${outsideAfterglow.inSeconds} s over',
              _ => null,
            },
    );
  }

  DateTime? _lastNearMissAt;

  /// Positions beyond the buffer that did not count only because of their
  /// accuracy – logged at most every 10 s, to calibrate in the field
  /// (R-OUT-07).
  void _logNearMiss(LocationFix fix, List<GeoPoint> area) {
    if (boundary.value.phase != BoundaryPhase.inside) return;
    final distance = distanceOutsideM(fix.point, area);
    if (distance == null || distance < outsideBufferM) return;
    if (classifyFix(fix, area) == FixSide.outside) return;
    final last = _lastNearMissAt;
    if (last != null && _now().difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _lastNearMissAt = _now();
    _log('boundary: not counted (${describeFix(fix, area)})');
  }

  void _setBoundary(BoundaryState after, {String? why}) {
    final before = boundary.value;
    if (after == before) return;
    boundary.value = after;
    if (after.phase == before.phase) {
      if (after.sharing) unawaited(_syncOutsideLocation());
      return;
    }
    _log('boundary: ${after.phase.name}${why == null ? '' : ' ($why)'}');
    switch (after.phase) {
      case BoundaryPhase.warning:
        final last = _lastWarningAt;
        if (last == null || _now().difference(last) >= warningRepeat) {
          _lastWarningAt = _now();
          _boundaryEvents.add(BoundaryEvent.warning);
        }
      case BoundaryPhase.live:
        // Not again when coming back out during the afterglow.
        if (!before.sharing) _boundaryEvents.add(BoundaryEvent.live);
      case BoundaryPhase.inside:
        if (before.sharing) _boundaryEvents.add(BoundaryEvent.ended);
      case BoundaryPhase.afterglow:
        break;
    }
    unawaited(_syncOutsideLocation());
  }

  /// Uploads the own position while the hunters may see it, deletes it as
  /// soon as they may not any more (R-OUT-03, R-OUT-04).
  Future<void> _syncOutsideLocation() async {
    if (_outsideBusy) return;
    _outsideBusy = true;
    try {
      if (boundary.value.sharing) {
        final fix = _lastFix;
        if (!_isFresh(fix)) return;
        final last = _lastOutsideUpload;
        if (last != null && _now().difference(last) < outsideUploadInterval) {
          return;
        }
        _outsideMaybeShared = true;
        await rounds.updateOutsideLocation(session, fix!);
        _lastOutsideUpload = _now();
      } else if (_outsideMaybeShared) {
        await rounds.clearOutsideLocation(session);
        _outsideMaybeShared = false;
        _lastOutsideUpload = null;
      }
    } on Exception catch (e) {
      // Retried on the next tick.
      _setStatus((s) => s.copyWith(lastError: 'Live: $e'));
    } finally {
      _outsideBusy = false;
    }
  }

  void _stop() {
    if (_tracking != null) {
      _log('tracking: stop (${_notTrackingReason ?? 'disposed'})');
    }
    unawaited(_tracking?.cancel());
    _tracking = null;
    _lastFix = null;
    position.value = null;
    // Caught, time up, screen closed …: no position, so the hunters must not
    // see an old one either.
    _setBoundary(const BoundaryState(), why: 'tracking stopped');
    if (_outsideMaybeShared && (_me?.isPlayer ?? false)) {
      unawaited(_syncOutsideLocation());
    }
    if (status.value.state != TrackingState.off) {
      _setStatus((s) => s.copyWith(state: TrackingState.off));
    }
  }

  bool _isFresh(LocationFix? fix) =>
      fix != null && _now().difference(fix.at) <= maxFixAge;

  /// Sends what is due. Called periodically; public for tests.
  Future<void> tick() async {
    // Phases change with time alone (e.g. time is up), not only on updates;
    // this also restarts tracking after an error.
    _sync();
    final me = _me;
    if (_busy || !_shouldTrack || me == null) return;
    _busy = true;
    try {
      await _refreshIfStreamSilent();
      if (me.isPlayer) {
        _stepBoundary();
        await _confirmOutside();
        await _syncOutsideLocation();
        await _sendDuePings();
        await _recordSpeedhuntSnapshots();
        await _answerJokerRequests();
      } else if (me.isHunter) {
        final fix = _lastFix;
        if (_isFresh(fix)) await _uploadHunterLocation(fix!);
      }
    } finally {
      _busy = false;
    }
  }

  /// Some Android devices deliver no or only sporadic stream updates (field
  /// test 2026-10-05). If the stream was silent for [streamSilence], fetch a
  /// position directly – at most that often – so the own dot, the hunters'
  /// live position and joker answers stay current.
  static const streamSilence = Duration(seconds: 30);

  Future<void> _refreshIfStreamSilent() async {
    final now = _now();
    bool silent(DateTime? t) => t == null || now.difference(t) >= streamSilence;
    if (!silent(_lastStreamFixAt) || !silent(_lastDirectFixAt)) return;
    _lastDirectFixAt = now;
    _log('stream silent → direct GPS request');
    await _fetchDirect();
  }

  /// During a warning, positions must keep coming to confirm the player is
  /// still outside (R-OUT-03): on devices with a sporadic GPS stream, ask
  /// the GPS directly every tick.
  Future<void> _confirmOutside() async {
    if (boundary.value.phase != BoundaryPhase.warning) return;
    final last = _lastStreamFixAt;
    if (last != null && _now().difference(last) < _confirmAfter) return;
    await _fetchDirect();
  }

  /// The stream normally delivers about once per second.
  static const _confirmAfter = Duration(seconds: 3);

  /// Latest tracked position, or – if there is none or it is stale (phone
  /// lying still, GPS stream stalled) – one fetched directly from the GPS.
  Future<LocationFix?> _fixForPing() async {
    final fix = _lastFix;
    if (_isFresh(fix)) return fix;
    return _fetchDirect(log: false);
  }

  /// [log] is false for pings: a log line at a speedhunt ping time would
  /// reveal the target (R-SPEED-04).
  Future<LocationFix?> _fetchDirect({bool log = true}) async {
    try {
      final direct = await location.currentFix();
      if (direct == null) {
        if (log) _log('direct GPS: no position');
        return null;
      }
      final fresh = LocationFix(
        point: direct.point,
        at: _now().toUtc(),
        accuracyM: direct.accuracyM,
      );
      _acceptFix(fresh);
      return fresh;
    } on Exception catch (e) {
      if (log) _log('direct GPS: error $e');
      _setStatus(
        (s) => s.copyWith(state: TrackingState.error, lastError: '$e'),
      );
      return null;
    }
  }

  Future<void> _sendDuePings() async {
    final due = duePings(mySlots, now: _now(), sentIds: _sent);
    if (due.isEmpty) return;
    final fix = await _fixForPing();
    if (fix == null) return; // retry on the next tick (within the grace period)
    for (final slot in due) {
      try {
        await rounds.sendPing(session, slot, fix);
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          // Usually: already sent before an app restart (no overwriting).
          // Shown anyway, so a real rules problem cannot hide.
          _sent.add(slot.id);
          _setStatus((s) => s.copyWith(lastError: 'Ping: ${e.code}'));
          continue;
        }
        _setStatus((s) => s.copyWith(lastError: 'Ping: ${e.code}'));
        return; // Offline etc.: retry on the next tick.
      } on Exception catch (e) {
        _setStatus((s) => s.copyWith(lastError: 'Ping: $e'));
        return;
      }
      _sent.add(slot.id);
      // A speedhunt ping must not reveal the target to the player (R-SPEED-04):
      // no notification, no "last ping" update for it.
      if (slot.kind == PingKind.regular) {
        // Only regular pings are logged: the log is visible to the player and
        // a speedhunt ping (even its time) would reveal the target.
        _log('ping sent');
        _setStatus((s) => s.copyWith(lastPingAt: _now(), clearError: true));
        _pingsSent.add(slot);
      } else {
        _setStatus((s) => s.copyWith(clearError: true));
      }
    }
  }

  /// At every speedhunt ping time – the moment the hunters get the target's
  /// ping – keep the own position as a ⚡ ping (R-SPEED-09). Same on every
  /// player's device, so it reveals no target; nothing is sent or logged.
  Future<void> _recordSpeedhuntSnapshots() async {
    final clock = _clock;
    if (clock == null) return;
    final slots = [
      for (final s in playerPingSlots(
        clock: clock,
        speedhuntsOnMe: _speedhunts,
      ))
        if (s.kind == PingKind.speedhunt) s,
    ];
    final recorded = speedhuntSnapshots.value;
    final due = duePings(slots, now: _now(), sentIds: recorded.keys.toSet());
    if (due.isEmpty) return;
    final fix = await _fixForPing();
    if (fix == null) return; // retry on the next tick (within the grace period)
    speedhuntSnapshots.value = {
      ...speedhuntSnapshots.value,
      for (final slot in due) slot.id: fix,
    };
  }

  Future<void> _uploadHunterLocation(LocationFix fix) async {
    final last = _lastUpload;
    if (last != null && _now().difference(last) < hunterUploadInterval) return;
    try {
      await rounds.updateHunterLocation(session, fix);
      _lastUpload = _now();
    } on Exception catch (e) {
      _setStatus((s) => s.copyWith(lastError: 'Upload: $e'));
    }
  }

  /// Latest joker requests (R-PLAY-03); answered with the current position as
  /// soon as one is available. Only active players answer.
  void updateJokerRequests(List<JokerRequest> requests) {
    _jokerRequests = requests;
    unawaited(_answerJokerRequests());
  }

  Future<void> _answerJokerRequests() async {
    final me = _me;
    final fix = _lastFix;
    if (me == null || !me.isPlayer || !_shouldTrack || fix == null) return;
    final requests = _jokerRequests;
    for (final r in requestsToAnswer(
      requests,
      myId: session.userId,
      now: _now(),
      answered: _answered,
    )) {
      _answered.add(r.id);
      try {
        await rounds.answerJokerRequest(session, r, fix);
      } on Exception {
        _answered.remove(r.id); // retry with the next update
      }
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _stop();
    _disposed = true;
    await _pingsSent.close();
    await _boundaryEvents.close();
    boundary.dispose();
    position.dispose();
    speedhuntSnapshots.dispose();
    log.dispose();
    status.dispose();
  }
}
