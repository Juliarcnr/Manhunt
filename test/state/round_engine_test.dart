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

        now = at(20);
        location.emit(fix(52.6)); // stream delivers every few seconds
        await flush();
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

    test(
      'speedhunt on me adds pings, silently (R-SPEED-03, R-SPEED-04)',
      () async {
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
        // Sent to the hunters …
        final pings = await rounds.watchAllPings(hunterSession).first;
        expect(pings.map((p) => p.kind), everyElement(PingKind.speedhunt));
        expect(pings, hasLength(3));
        // … but the player is not told – that would reveal the target
        // (R-SPEED-04).
        expect(sent, isEmpty);
        expect(engine.status.value.lastPingAt, isNull);
        expect(engine.visibleSlots.map((s) => s.kind), [
          PingKind.regular,
          PingKind.regular,
        ]);
      },
    );

    group('own ⚡ pings on every player, target or not (R-SPEED-09)', () {
      Speedhunt sh(String target) => Speedhunt.fromSettings(
        targetId: target,
        startedAt: at(25),
        settings: const GameSettings(),
      );

      for (final target in ['kim', '']) {
        test(target.isEmpty ? 'not the target' : 'the target', () async {
          engine.update(
            game: game(),
            me: player,
            speedhuntsOnMe: [if (target.isNotEmpty) sh(target)],
            speedhunts: [sh('')], // public: without target
          );
          location.emit(fix(52.5));
          await flush();
          now = at(24);
          await engine.tick();
          expect(engine.speedhuntSnapshots.value, isEmpty);
          for (final (m, lat) in [(25, 52.5), (30, 52.6)]) {
            now = at(m);
            location.emit(fix(lat));
            await flush();
            await engine.tick();
            await flush();
          }
          final ms = at(25).millisecondsSinceEpoch;
          final snaps = engine.speedhuntSnapshots.value;
          expect(snaps.keys, ['speedhunt_${ms}_1', 'speedhunt_${ms}_2']);
          expect(snaps['speedhunt_${ms}_2']!.point.lat, 52.6);
          // Only the target sends anything to the hunters.
          final pings = await rounds.watchAllPings(hunterSession).first;
          expect(pings, hasLength(target.isEmpty ? 0 : 2));
          expect(sent, isEmpty);
        });
      }

      test('restored after a restart, not recorded again', () async {
        final ms = at(25).millisecondsSinceEpoch;
        final saved = LocationFix(
          point: const GeoPoint(52.1, 13.4),
          at: at(25),
        );
        engine
          ..restoreSpeedhuntSnapshots({'speedhunt_${ms}_1': saved})
          ..update(
            game: game(),
            me: player,
            speedhuntsOnMe: [],
            speedhunts: [sh('')],
          );
        location.emit(fix(52.5));
        await flush();
        now = at(26);
        await engine.tick();
        expect(engine.speedhuntSnapshots.value['speedhunt_${ms}_1'], saved);
      });

      test('caught players record nothing', () async {
        engine.update(
          game: game(),
          me: player.copyWith(caught: true),
          speedhuntsOnMe: [],
          speedhunts: [sh('')],
        );
        now = at(25);
        await engine.tick();
        expect(engine.speedhuntSnapshots.value, isEmpty);
      });
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

  group('tracking starts by itself (field test: only "screen opened")', () {
    test('phone clock a few seconds behind the server start time', () async {
      // The start time is server time; this phone's clock is 3 s behind, so
      // the round "has not started yet" when the screen opens. Tracking must
      // start on its own a moment later – without any further update.
      now = start.subtract(const Duration(seconds: 3));
      final e = RoundEngine(
        session: await testSession('ABCDE-FGHJK', 'kim'),
        rounds: rounds,
        location: location,
        notice: const TrackingNotice(title: 't', text: 'x'),
        now: () => now,
        tickInterval: const Duration(milliseconds: 10),
      );
      addTearDown(e.dispose);
      e.update(game: game(), me: player, speedhuntsOnMe: []);
      expect(location.isTracking, isFalse);
      expect(e.log.value.last, endsWith('not tracking: phase notStarted'));

      now = start.add(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(location.isTracking, isTrue);
      expect(e.log.value, contains(endsWith('tracking: start')));
    });
  });

  group('silent GPS stream (field test 2026-10-05, Android 10)', () {
    test('stream silent for 30 s → position fetched directly', () async {
      location.position = const GeoPoint(52.7, 13.7);
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      await engine.tick(); // nothing from the stream yet
      expect(location.currentCalls, 1);
      expect(engine.position.value!.point.lat, 52.7);

      now = now.add(const Duration(seconds: 10));
      await engine.tick();
      expect(location.currentCalls, 1); // not more often than every 30 s

      now = now.add(const Duration(seconds: 25));
      await engine.tick();
      expect(location.currentCalls, 2);
    });

    test('working stream → no direct requests', () async {
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      for (var i = 0; i < 6; i++) {
        location.emit(fix(52.5));
        await flush();
        await engine.tick();
        now = now.add(const Duration(seconds: 10));
      }
      expect(location.currentCalls, 0);
    });

    test('hunter position is refreshed and uploaded without stream', () async {
      location.position = const GeoPoint(52.3, 13.3);
      engine = await engineFor('h');
      engine.update(game: game(), me: hunter, speedhuntsOnMe: []);
      await engine.tick();
      await flush();
      final locs = await rounds.watchHunterLocations(hunterSession).first;
      expect(locs['h']!.point.lat, 52.3);
    });

    test('log explains why tracking stopped', () async {
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: []);
      engine.update(
        game: game(),
        me: player.copyWith(caught: true),
        speedhuntsOnMe: [],
      );
      expect(engine.log.value.last, endsWith('tracking: stop (caught)'));
    });

    test('log never reveals a speedhunt on the player (R-SPEED-04)', () async {
      location.position = const GeoPoint(52.1, 13.1);
      final sh = Speedhunt.fromSettings(
        targetId: 'kim',
        startedAt: at(25),
        settings: const GameSettings(),
      );
      engine = await engineFor('kim');
      engine.update(game: game(), me: player, speedhuntsOnMe: [sh]);
      for (final m in [25, 30, 35]) {
        now = at(m);
        location.emit(fix(52.5));
        await flush();
        await engine.tick();
        await flush();
      }
      final text = engine.log.value.join('\n');
      expect(text, isNot(contains('speedhunt')));
      expect(text, isNot(contains('ping')));
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
