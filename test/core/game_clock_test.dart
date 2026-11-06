import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/schedule/game_clock.dart';

void main() {
  final start = DateTime.utc(2026, 10, 4, 14);
  const settings = GameSettings(); // 3 h, 15 min head start, ping every 20 min
  final clock = GameClock(startAt: start, settings: settings);

  DateTime at(int minutes) => start.add(Duration(minutes: minutes));

  group('phases (R-GAME-01, R-GAME-04)', () {
    test('before start', () {
      expect(clock.phaseAt(at(-1)), GamePhase.notStarted);
    });
    test('head start until hunters are released', () {
      expect(clock.phaseAt(at(0)), GamePhase.headStart);
      expect(clock.phaseAt(at(14)), GamePhase.headStart);
    });
    test('hunting from release until end', () {
      expect(clock.phaseAt(at(15)), GamePhase.hunting);
      expect(clock.phaseAt(at(179)), GamePhase.hunting);
    });
    test('ended at duration', () {
      expect(clock.phaseAt(at(180)), GamePhase.ended);
    });
  });

  group('hunters won: last player caught (R-GAME-08)', () {
    final won = GameClock(
      startAt: start,
      settings: settings,
      finishedAt: at(50),
    );

    test('the round ends at the last catch, like time up', () {
      expect(won.phaseAt(at(49)), GamePhase.hunting);
      expect(won.phaseAt(at(50)), GamePhase.ended);
      expect(won.endAt, at(50));
      expect(won.plannedEndAt, at(180));
      expect(won.huntersWon, isTrue);
    });

    test('no regular pings after it', () {
      expect(won.regularPingTimes(), [at(20), at(40)]);
      expect(won.nextRegularPing(at(45)), isNull);
    });

    test('a leftover from an earlier round (before the start) is ignored', () {
      final leftover = GameClock(
        startAt: start,
        settings: settings,
        finishedAt: at(-60),
      );
      expect(leftover.huntersWon, isFalse);
      expect(leftover.endAt, at(180));
      expect(leftover.phaseAt(at(30)), GamePhase.hunting);
    });

    test('without it the planned end applies', () {
      expect(clock.endAt, at(180));
      expect(clock.huntersWon, isFalse);
    });
  });

  group('confirmation after the time is up (R-GAME-11)', () {
    GameClock confirmed(DateTime? at) =>
        GameClock(startAt: start, settings: settings, confirmedAt: at);

    test('waits for it from the end on; the phase ends as planned', () {
      expect(clock.awaitingConfirmation(at(179)), isFalse);
      expect(clock.phaseAt(at(180)), GamePhase.ended);
      expect(clock.awaitingConfirmation(at(180)), isTrue);
      expect(clock.awaitingConfirmation(at(189)), isTrue);
      expect(clock.timeUpConfirmed, isFalse);
    });

    test('decided once someone confirmed', () {
      final c = confirmed(at(182));
      expect(c.timeUpConfirmed, isTrue);
      expect(c.decidedAt, at(182));
      expect(c.awaitingConfirmation(at(181)), isTrue);
      expect(c.awaitingConfirmation(at(182)), isFalse);
      expect(c.endAt, at(180));
    });

    test('without one, 10 min after the end counts as "nobody else"', () {
      expect(GameClock.confirmTimeout, const Duration(minutes: 10));
      expect(clock.decidedAt, at(190));
      expect(clock.awaitingConfirmation(at(190)), isFalse);
    });

    test('a leftover from an earlier round (before the end) is ignored', () {
      final leftover = confirmed(at(-60));
      expect(leftover.timeUpConfirmed, isFalse);
      expect(leftover.awaitingConfirmation(at(181)), isTrue);
    });

    test('not after the hunters won by the last catch (R-GAME-08)', () {
      final won = GameClock(
        startAt: start,
        settings: settings,
        finishedAt: at(50),
      );
      expect(won.awaitingConfirmation(at(50)), isFalse);
      expect(won.decidedAt, at(50));
    });
  });

  group('automatic end (R-GAME-10)', () {
    const delay = Duration(seconds: 15);

    test('15 s after the confirmation once the time is up (R-GAME-11)', () {
      final c = GameClock(
        startAt: start,
        settings: settings,
        confirmedAt: at(183),
      );
      expect(c.autoEndAt, at(183).add(delay));
    });

    test('without confirmation 15 s after the timeout (R-GAME-11)', () {
      expect(clock.autoEndAt, at(190).add(delay));
    });

    test('15 s after the last catch', () {
      final won = GameClock(
        startAt: start,
        settings: settings,
        finishedAt: at(50),
      );
      expect(won.autoEndAt, at(50).add(delay));
    });

    test('a leftover from an earlier round does not bring it forward', () {
      final leftover = GameClock(
        startAt: start,
        settings: settings,
        finishedAt: at(-60),
      );
      expect(leftover.autoEndAt, at(190).add(delay));
    });
  });

  group('regular pings (R-PING-02)', () {
    test('first ping at minute 20, then every 20 min, none at the end', () {
      final times = clock.regularPingTimes();
      expect(times.first, at(20));
      expect(times.last, at(160));
      expect(times, hasLength(8));
    });

    test('custom interval', () {
      final c = GameClock(
        startAt: start,
        settings: settings.copyWith(
          duration: const Duration(hours: 1),
          pingInterval: const Duration(minutes: 15),
        ),
      );
      expect(c.regularPingTimes(), [at(15), at(30), at(45)]);
    });

    test('nextRegularPing', () {
      expect(clock.nextRegularPing(at(0)), at(20));
      expect(clock.nextRegularPing(at(20)), at(40));
      expect(clock.nextRegularPing(at(170)), isNull);
    });
  });
}
