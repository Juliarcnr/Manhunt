import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/schedule/start_time.dart';

void main() {
  // Local times: the start time is a time of day on the host's phone.
  final now = DateTime(2026, 11, 1, 13, 57, 30);
  Duration time(int h, int m) => Duration(hours: h, minutes: m);

  group('countdown without a start time (R-START-01)', () {
    test('the official start is one minute after pressing start', () {
      expect(plannedStartAt(now), now.add(const Duration(minutes: 1)));
    });
  });

  group('countdown to the start time (R-SET-21, R-START-02)', () {
    test('a start time later today: countdown until then', () {
      final at = plannedStartAt(now, startTime: time(14, 0));
      expect(at, DateTime(2026, 11, 1, 14));
      expect(at.difference(now), const Duration(minutes: 2, seconds: 30));
    });

    test('also hours ahead', () {
      expect(
        plannedStartAt(now, startTime: time(20, 30)),
        DateTime(2026, 11, 1, 20, 30),
      );
    });

    test('shortly after midnight counts as the coming night', () {
      final late = DateTime(2026, 11, 1, 23, 50);
      expect(
        plannedStartAt(late, startTime: time(0, 30)),
        DateTime(2026, 11, 2, 0, 30),
      );
    });

    test('a start time that has passed: one minute countdown', () {
      expect(
        plannedStartAt(now, startTime: time(13, 0)),
        now.add(startCountdown),
      );
      // Exactly now is passed, too.
      final onTime = DateTime(2026, 11, 1, 14);
      expect(
        plannedStartAt(onTime, startTime: time(14, 0)),
        onTime.add(startCountdown),
      );
    });

    test('more than 12 hours ahead counts as passed', () {
      expect(
        plannedStartAt(now, startTime: time(2, 0)),
        now.add(startCountdown),
      );
    });

    test('works with UTC input and returns the same instant', () {
      final at = plannedStartAt(now.toUtc(), startTime: time(14, 0));
      expect(at.isAtSameMomentAs(DateTime(2026, 11, 1, 14)), isTrue);
    });
  });

  group('skip the countdown when testing (R-BOT-09)', () {
    test('starts right away, also with a start time ahead', () {
      expect(plannedStartAt(now, skipCountdown: true), now);
      expect(
        plannedStartAt(now, startTime: time(14, 0), skipCountdown: true),
        now,
      );
    });
  });

  group('countdown overlay (R-START-05)', () {
    final startAt = DateTime.utc(2026, 11, 1, 14);
    int? left(int ms) =>
        countdownSecondsLeft(startAt, startAt.add(Duration(milliseconds: ms)));

    test('whole seconds left, rounded up', () {
      expect(left(-90000), 90);
      expect(left(-2400), 3);
      expect(left(-1), 1);
    });

    test('"START" right after the start, then nothing', () {
      expect(left(0), 0);
      expect(left(1499), 0);
      expect(left(1500), isNull);
    });
  });
}
