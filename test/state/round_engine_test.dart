import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/round/joker.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/core/schedule/speedhunt.dart';
import 'package:manhunt/data/firestore_round_repository.dart';
import 'package:manhunt/data/game_repository.dart';
import 'package:manhunt/data/location_service.dart';
import 'package:manhunt/state/round_engine.dart';

import '../helpers.dart';

void main() {
  final start = DateTime.utc(2026, 10, 4, 14);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));

  late FakeFirebaseFirestore db;
  late FirestoreRoundRepository rounds;
  late FakeLocationService location;
  late GroupSession hunterSession;
  late DateTime now;
  late RoundEngine engine;
  late List<PingSlot> sent;

  const game0 = GameSettings(duration: Duration(hours: 1));
  GameInfo game({GameStatus status = GameStatus.running}) =>
      GameInfo(adminId: 'h', status: status, settings: game0, startAt: start);
  const player = Member(id: 'kim', name: 'Kim', role: Role.player);
  const hunter = Member(id: 'h', name: 'Alex', role: Role.hunter);

  LocationFix fix(double lat) =>
      LocationFix(point: GeoPoint(lat, 13.4), at: now);

  Future<RoundEngine> engineFor(String userId) async {
    final e = RoundEngine(
      session: await testSession('ABCDE-FGHJK', userId),
      rounds: rounds,
      location: location,
      notice: const TrackingNotice(title: 't', text: 'x'),
      now: () => now,
      // Ticks are driven manually in these tests.
      tickInterval: const Duration(days: 1),
    );
    sent = [];
    e.pingsSent.listen(sent.add);
    addTearDown(e.dispose);
    return e;
  }

  /// Lets stream events propagate.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    db = FakeFirebaseFirestore();
    rounds = FirestoreRoundRepository(db);
    location = FakeLocationService();
    hunterSession = await testSession('ABCDE-FGHJK', 'h');
    now = at(0);
  });

  group('tracking only while needed (R-PRIV-04)', () {
    test('not in the lobby', () async {
      engine = await engineFor('kim');
      engine.update(
        game: game(status: GameStatus.lobby),
        me: player,
        speedhuntsOnMe: [],
      );
      expect(location.isTracking, isFalse);
    });

    test('player tracks during head start and hunting', () async {
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      expect(location.isTracking, isTrue);
      expect(location.lastNotice!.title, 't');
    });

    test('stops when caught', () async {
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      engine.update(
        game: game(),
        me: player.copyWith(caught: true),
        speedhuntsOnMe: [],
      );
      await flush();
      expect(location.isTracking, isFalse);
    });

    test('stops when the time is up, even without updates', () async {
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      now = at(61);
      await engine.tick();
      await flush();
      await flush();
      expect(location.isTracking, isFalse);
    });

    test('unassigned members never track', () async {
      engine = await engineFor('x');
      engine.update(
        game: game(),
        me: const Member(id: 'x', name: 'X'),
        speedhuntsOnMe: [],
      );
      expect(location.isTracking, isFalse);
    });
  });

  group('player pings (R-PING-01, R-PING-02, R-SPEED-03)', () {
    setUp(() async {
      // Fallback position for when the tracked one is stale.
      location.position = const GeoPoint(52.0, 13.0);
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
    });

    test(
      'ping is sent automatically when due, with the latest position',
      () async {
        location.emit(fix(52.5));
        await flush();
        now = at(19);
        await engine.tick();
        await flush();
        expect(sent, isEmpty);

        location.emit(fix(52.6));
        await flush();
        now = at(20);
        await engine.tick();
        await flush();
        expect(sent.single.id, 'regular_1');

        final pings = await rounds.watchAllPings(hunterSession).first;
        expect(pings.single.playerId, 'kim');
        expect(pings.single.fix.point.lat, 52.6);
      },
    );

    test('each ping only once', () async {
      location.emit(fix(52.5));
      await flush();
      now = at(20);
      await engine.tick();
      await flush();
      now = at(21);
      await engine.tick();
      await flush();
      expect(sent, hasLength(1));
    });

    test(
      'no GPS at all → ping is sent as soon as a position arrives',
      () async {
        location.position = null; // GPS gives nothing yet
        now = at(20);
        await engine.tick();
        await flush();
        expect(sent, isEmpty);
        now = at(21);
        location.emit(fix(52.5));
        await flush();
        await engine.tick();
        await flush();
        expect(sent.single.id, 'regular_1');
      },
    );

    test('speedhunt on me adds pings', () async {
      final sh = Speedhunt.fromSettings(
        targetId: 'kim',
        startedAt: at(25),
        settings: const GameSettings(),
      );
      engine.update(game: game(), me: player, speedhuntsOnMe: [sh]);
      location.emit(fix(52.5));
      await flush();
      for (final m in [25, 30, 35]) {
        now = at(m);
        await engine.tick();
        await flush();
      }
      expect(sent.map((s) => s.kind), everyElement(PingKind.speedhunt));
      expect(sent, hasLength(3));
    });

    test('next pings are exposed for the countdown', () {
      expect(engine.mySlots.map((s) => s.at), [at(20), at(40)]);
    });
  });

  group('answering the player joker (R-PLAY-03)', () {
    JokerRequest request() =>
        JokerRequest(id: 'r1', requesterId: 'sam', at: now);

    Future<Map<String, LocationFix>> answersForSam() async => rounds
        .watchJokerAnswers(await testSession('ABCDE-FGHJK', 'sam'), 'r1')
        .first;

    test('active player answers with the current position', () async {
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      location.emit(fix(52.55));
      await flush();
      engine.updateJokerRequests([request()]);
      await flush();
      await flush();
      expect((await answersForSam())['kim']!.point.lat, 52.55);
    });

    test('answers once a position arrives, even if asked before', () async {
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      engine.updateJokerRequests([request()]);
      await flush();
      expect(await answersForSam(), isEmpty);
      location.emit(fix(52.56));
      await flush();
      await engine.tick();
      await flush();
      expect((await answersForSam())['kim']!.point.lat, 52.56);
    });

    test('caught players and hunters do not answer', () async {
      engine = await engineFor('kim');
      engine.update(
        game: game(),
        me: player.copyWith(caught: true),
        speedhuntsOnMe: [],
      );
      engine.updateJokerRequests([request()]);
      await flush();

      final hunterEngine = await engineFor('h');
      hunterEngine.update(game: game(), me: hunter, speedhuntsOnMe: []);
      location.emit(fix(52.4));
      await flush();
      hunterEngine.updateJokerRequests([request()]);
      await flush();
      await flush();
      expect(await answersForSam(), isEmpty);
    });
  });

  group('robust tracking (field test 2026-10-05)', () {
    test('stale position → fresh one directly from the GPS', () async {
      location.position = const GeoPoint(52.9, 13.9);
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      location.emit(fix(52.5)); // at minute 0
      await flush();
      now = at(20); // 20 min later: too old
      await engine.tick();
      await flush();
      expect(location.currentCalls, 1);
      final pings = await rounds.watchAllPings(hunterSession).first;
      expect(pings.single.fix.point.lat, 52.9);
    });

    test('no position at all → GPS asked at ping time', () async {
      location.position = const GeoPoint(52.8, 13.8);
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      now = at(20);
      await engine.tick();
      await flush();
      expect(sent.single.id, 'regular_1');
    });

    test('tracking error is shown and tracking restarts', () async {
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      expect(location.trackCalls, 1);
      location.fail(Exception('GPS crashed'));
      await flush();
      expect(engine.status.value.state, TrackingState.error);
      expect(engine.status.value.lastError, contains('GPS crashed'));
      await engine.tick();
      expect(location.trackCalls, 2);
      expect(location.isTracking, isTrue);
    });

    test('missing permission is shown, retried only on request', () async {
      location.permissionGranted = false;
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      await flush();
      expect(engine.status.value.state, TrackingState.noPermission);
      await engine.tick();
      expect(location.trackCalls, 1); // no endless permission dialogs

      location.permissionGranted = true;
      engine.retry();
      expect(location.trackCalls, 2);
      expect(location.isTracking, isTrue);
    });

    test('status shows positions and the last ping', () async {
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      expect(engine.status.value.state, TrackingState.waiting);
      now = at(20);
      location.emit(fix(52.5));
      await flush();
      expect(engine.status.value.state, TrackingState.ok);
      await engine.tick();
      await flush();
      expect(engine.status.value.lastPingAt, at(20));
    });
  });

  group('hunter live position (R-HUNT-02)', () {
    setUp(() async {
      engine = await engineFor('h');
      engine.update(game: game(), me: hunter, speedhuntsOnMe: []);
    });

    test('first position is uploaded immediately, then throttled', () async {
      location.emit(fix(52.4));
      await flush();
      await flush();
      var locs = await rounds.watchHunterLocations(hunterSession).first;
      expect(locs['h']!.point.lat, 52.4);

      location.emit(fix(52.41));
      await flush();
      now = now.add(const Duration(seconds: 5));
      await engine.tick();
      await flush();
      locs = await rounds.watchHunterLocations(hunterSession).first;
      expect(locs['h']!.point.lat, 52.4); // throttled

      now = now.add(const Duration(seconds: 15));
      await engine.tick();
      await flush();
      locs = await rounds.watchHunterLocations(hunterSession).first;
      expect(locs['h']!.point.lat, 52.41);
    });

    test('hunters never send pings', () async {
      location.emit(fix(52.4));
      await flush();
      now = at(20);
      await engine.tick();
      await flush();
      expect(sent, isEmpty);
      expect(engine.mySlots, isEmpty);
    });
  });
}
