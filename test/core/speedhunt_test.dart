import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/schedule/game_clock.dart';
import 'package:manhunt/core/schedule/speedhunt.dart';

void main() {
  final start = DateTime.utc(2026, 10, 4, 14);
  // No minimum start time here; R-SET-11 is tested separately below.
  const settings = GameSettings(speedhuntEarliest: Duration.zero);
  final clock = GameClock(startAt: start, settings: settings);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));

  const player = Member(id: 'p', name: 'Pia', role: Role.player);

  group('Speedhunt (R-SPEED-03)', () {
    final sh = Speedhunt.fromSettings(
      targetId: 'p',
      startedAt: at(30),
      settings: settings,
    );

    test('3 pings every 5 min, first immediately', () {
      expect(sh.pingTimes(), [at(30), at(35), at(40)]);
    });

    test('active until last ping', () {
      expect(sh.isActiveAt(at(29)), isFalse);
      expect(sh.isActiveAt(at(30)), isTrue);
      expect(sh.isActiveAt(at(40)), isTrue);
      expect(sh.isActiveAt(at(41)), isFalse);
    });

    test('json roundtrip', () {
      final back = Speedhunt.fromJson(sh.toJson());
      expect(back.pingTimes(), sh.pingTimes());
      expect(back.targetId, 'p');
    });
  });

  group('canStartSpeedhunt (R-SPEED-01, R-SPEED-02)', () {
    SpeedhuntDenial? check(
      DateTime now,
      List<Speedhunt> prev, [
      Member target = player,
    ]) => canStartSpeedhunt(
      clock: clock,
      now: now,
      previous: prev,
      target: target,
    );

    test('allowed while hunting', () {
      expect(check(at(30), []), isNull);
    });
    test('not during head start or after end', () {
      expect(check(at(5), []), SpeedhuntDenial.notHunting);
      expect(check(at(200), []), SpeedhuntDenial.notHunting);
    });
    test('limited count', () {
      final used = [
        Speedhunt.fromSettings(
          targetId: 'p',
          startedAt: at(20),
          settings: settings,
        ),
        Speedhunt.fromSettings(
          targetId: 'p',
          startedAt: at(60),
          settings: settings,
        ),
      ];
      expect(check(at(100), used), SpeedhuntDenial.noneLeft);
    });
    test('only one at a time', () {
      final running = [
        Speedhunt.fromSettings(
          targetId: 'p',
          startedAt: at(30),
          settings: settings,
        ),
      ];
      expect(check(at(32), running), SpeedhuntDenial.alreadyRunning);
    });
    test('target must be an uncaught player', () {
      expect(
        check(at(30), [], player.copyWith(caught: true)),
        SpeedhuntDenial.invalidTarget,
      );
      expect(
        check(at(30), [], player.copyWith(role: Role.hunter)),
        SpeedhuntDenial.invalidTarget,
      );
    });
  });

  group('first speedhunt not before the configured time (R-SET-11)', () {
    final defaultClock = GameClock(
      startAt: start,
      settings: const GameSettings(), // 60 min
    );
    SpeedhuntDenial? checkAt(int minute) => canStartSpeedhunt(
      clock: defaultClock,
      now: at(minute),
      previous: const [],
      target: player,
    );

    test('default is 60 minutes', () {
      expect(const GameSettings().speedhuntEarliest, const Duration(hours: 1));
    });

    test('too early before, allowed from minute 60', () {
      expect(checkAt(30), SpeedhuntDenial.tooEarly);
      expect(checkAt(59), SpeedhuntDenial.tooEarly);
      expect(checkAt(60), isNull);
    });

    test('head start still wins over "too early"', () {
      expect(checkAt(5), SpeedhuntDenial.notHunting);
    });
  });
}
