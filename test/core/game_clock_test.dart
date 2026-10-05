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
