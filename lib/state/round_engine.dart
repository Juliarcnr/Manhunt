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

  /// Latest own position while tracking, for the "you are here" dot.
  final position = ValueNotifier<LocationFix?>(null);
  DateTime? _lastUpload;
  var _busy = false;
  final _sent = <String>{};
  final _answered = <String>{};
  List<JokerRequest> _jokerRequests = const [];
  final _pingsSent = StreamController<PingSlot>.broadcast();

  /// Emits after each successfully sent own ping (R-NOTIF-03).
  Stream<PingSlot> get pingsSent => _pingsSent.stream;

  bool get isTracking => _tracking != null;

  GameClock? get _clock {
    final startAt = _game?.startAt;
    final game = _game;
    if (startAt == null || game == null) return null;
    return GameClock(startAt: startAt, settings: game.settings);
  }

  /// This player's ping plan; empty for hunters.
  List<PingSlot> get mySlots {
    final clock = _clock;
    if (clock == null || !(_me?.isPlayer ?? false)) return const [];
    return playerPingSlots(clock: clock, speedhuntsOnMe: _speedhuntsOnMe);
  }

  bool get _shouldTrack {
    final game = _game;
    final me = _me;
    final clock = _clock;
    if (game == null || me == null || clock == null) return false;
    if (game.status != GameStatus.running) return false;
    final phase = clock.phaseAt(_now());
    if (phase != GamePhase.headStart && phase != GamePhase.hunting) {
      return false;
    }
    return me.isHunter || (me.isPlayer && !me.caught);
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

  void _sync() {
    if (_shouldTrack) {
      _tracking ??= location.track(notice).listen((fix) {
        _lastFix = fix;
        position.value = fix;
        // Hunters upload right away when they have no position online yet.
        if (_lastUpload == null) unawaited(tick());
      });
      _timer ??= Timer.periodic(tickInterval, (_) => unawaited(tick()));
    } else {
      _stop();
    }
  }

  void _stop() {
    unawaited(_tracking?.cancel());
    _tracking = null;
    _timer?.cancel();
    _timer = null;
    _lastFix = null;
    position.value = null;
  }

  /// Sends what is due. Called periodically; public for tests.
  Future<void> tick() async {
    // Phases change with time alone (e.g. time is up), not only on updates.
    _sync();
    final me = _me;
    final fix = _lastFix;
    if (_busy || !_shouldTrack || me == null || fix == null) return;
    _busy = true;
    try {
      if (me.isPlayer) {
        await _sendDuePings(fix);
        await _answerJokerRequests();
      } else if (me.isHunter) {
        await _uploadHunterLocation(fix);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _sendDuePings(LocationFix fix) async {
    for (final slot in duePings(mySlots, now: _now(), sentIds: _sent)) {
      try {
        await rounds.sendPing(session, slot, fix);
      } on FirebaseException catch (e) {
        // Already sent before an app restart: the rules forbid overwriting.
        if (e.code == 'permission-denied') {
          _sent.add(slot.id);
          continue;
        }
        return; // Offline etc.: retry on the next tick.
      } on Exception {
        // Offline etc.: retry on the next tick (within the grace period).
        return;
      }
      _sent.add(slot.id);
      _pingsSent.add(slot);
    }
  }

  Future<void> _uploadHunterLocation(LocationFix fix) async {
    final last = _lastUpload;
    if (last != null && _now().difference(last) < hunterUploadInterval) return;
    try {
      await rounds.updateHunterLocation(session, fix);
      _lastUpload = _now();
    } on Exception {
      // Retry on the next tick.
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
  }
}
