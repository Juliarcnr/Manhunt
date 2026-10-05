import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/foundation.dart';

import '../core/models/member.dart';
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
/// - hunters: shares the live position with the other hunters (R-HUNT-02).
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
  final DateTime Function() _now;

  GameInfo? _game;
  Member? _me;
  List<Speedhunt> _speedhuntsOnMe = const [];

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

  void update({
    required GameInfo? game,
    required Member? me,
    required List<Speedhunt> speedhuntsOnMe,
  }) {
    _game = game;
    _me = me;
    _speedhuntsOnMe = speedhuntsOnMe;
    _sync();
  }

  /// After the user granted the permission (e.g. in the system settings).
  void retry() {
    _permissionMissing = false;
    _sync();
  }

  void _setStatus(EngineStatus Function(EngineStatus s) change) =>
      status.value = change(status.value);

  void _sync() {
    if (!_shouldTrack) {
      _stop();
      return;
    }
    _timer ??= Timer.periodic(tickInterval, (_) => unawaited(tick()));
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
  }

  void _stop() {
    if (_tracking != null || _timer != null) {
      _log('tracking: stop (${_notTrackingReason ?? 'disposed'})');
    }
    unawaited(_tracking?.cancel());
    _tracking = null;
    _timer?.cancel();
    _timer = null;
    _lastFix = null;
    position.value = null;
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
        await _sendDuePings();
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
      final point = await location.currentPosition();
      if (point == null) {
        if (log) _log('direct GPS: no position');
        return null;
      }
      final fresh = LocationFix(point: point, at: _now().toUtc());
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
    _stop();
    await _pingsSent.close();
    position.dispose();
    log.dispose();
    status.dispose();
  }
}
