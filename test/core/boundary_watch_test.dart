import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/boundary_watch.dart';
import 'package:manhunt/core/round/ping_schedule.dart';

void main() {
  // ~1 km × 2 km rectangle; positions given in metres east of its east edge.
  const lat = 52.5;
  const dLat = 2 / 111.195;
  const dLng = 1 / 67.69;
  const area = [
    GeoPoint(lat, 13.4),
    GeoPoint(lat, 13.4 + dLng),
    GeoPoint(lat + dLat, 13.4 + dLng),
    GeoPoint(lat + dLat, 13.4),
  ];
  final t0 = DateTime.utc(2026, 10, 8, 14);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  LocationFix fix(double metresOut, {double? accuracy = 10}) => LocationFix(
    point: GeoPoint(lat + dLat / 2, 13.4 + dLng + metresOut / 67690),
    at: t0,
    accuracyM: accuracy,
  );

  /// Feeds one position per second from [from] to [to] (inclusive).
  BoundaryState walk(
    BoundaryState s,
    double metresOut, {
    required int from,
    required int to,
    double? accuracy = 10,
  }) {
    for (var t = from; t <= to; t++) {
      s = boundaryStep(
        s,
        area: area,
        now: at(t),
        fix: fix(metresOut, accuracy: accuracy),
      );
    }
    return s;
  }

  group('which positions count as outside (R-OUT-02)', () {
    test('inside → inside', () {
      expect(classifyFix(fix(-5), area), FixSide.inside);
    });

    test('buffer plus twice the reported accuracy: 30 m + 2 × 10 m', () {
      expect(classifyFix(fix(41), area), FixSide.unclear);
      expect(classifyFix(fix(49), area), FixSide.unclear);
      expect(classifyFix(fix(51), area), FixSide.outside);
      expect(outsideThresholdM(25), 80);
      expect(classifyFix(fix(79, accuracy: 25), area), FixSide.unclear);
      expect(classifyFix(fix(81, accuracy: 25), area), FixSide.outside);
    });

    test('log line shows distance, accuracy and threshold (R-OUT-07)', () {
      expect(describeFix(fix(48), area), '48 m out, ±10 m, needs 50 m');
      expect(
        describeFix(fix(-20, accuracy: 4), area),
        '20 m in, ±4 m, '
        'needs 38 m',
      );
      expect(
        describeFix(fix(60, accuracy: null), area),
        '60 m out, accuracy unknown',
      );
      expect(describeFix(fix(60), const []), 'no area');
    });

    test('just outside (GPS scatter) is unclear', () {
      expect(classifyFix(fix(25, accuracy: 5), area), FixSide.unclear);
    });

    test('inaccurate or unknown accuracy is never outside', () {
      expect(classifyFix(fix(500, accuracy: 31), area), FixSide.unclear);
      expect(classifyFix(fix(500, accuracy: null), area), FixSide.unclear);
    });

    test('no area → unclear', () {
      expect(classifyFix(fix(500), const []), FixSide.unclear);
    });
  });

  group('live location only after 30 s clearly outside (R-OUT-03)', () {
    test('a single GPS jump only warns', () {
      var s = walk(const BoundaryState(), -10, from: 0, to: 5);
      expect(s.phase, BoundaryPhase.inside);
      s = boundaryStep(s, area: area, now: at(6), fix: fix(200));
      expect(s.phase, BoundaryPhase.warning);
      s = boundaryStep(s, area: area, now: at(7), fix: fix(-10));
      expect(s.phase, BoundaryPhase.inside);
    });

    test('29 s outside: still only a warning, 30 s: live', () {
      var s = walk(const BoundaryState(), 100, from: 0, to: 29);
      expect(s.phase, BoundaryPhase.warning);
      expect(s.liveAt, at(30));
      expect(s.sharing, isFalse);
      s = walk(s, 100, from: 30, to: 30);
      expect(s.phase, BoundaryPhase.live);
      expect(s.sharing, isTrue);
    });

    test('one doubtful position restarts the 30 s', () {
      var s = walk(const BoundaryState(), 100, from: 0, to: 20);
      s = walk(s, 100, from: 21, to: 21, accuracy: 50);
      expect(s.phase, BoundaryPhase.inside);
      s = walk(s, 100, from: 22, to: 51);
      expect(s.phase, BoundaryPhase.warning);
      s = walk(s, 100, from: 52, to: 52);
      expect(s.phase, BoundaryPhase.live);
    });

    test('standing at the edge with GPS scatter never warns', () {
      var s = const BoundaryState();
      for (var t = 0; t < 600; t++) {
        // Scatter of ±30 m around a point 10 m outside, accuracy 15–25 m.
        final out = 10 + 30 * ((t * 7) % 21 - 10) / 10;
        final acc = 15 + (t % 11).toDouble();
        s = boundaryStep(
          s,
          area: area,
          now: at(t),
          fix: fix(out, accuracy: acc),
        );
        expect(s.phase, BoundaryPhase.inside, reason: 't=$t');
      }
    });

    test('too few positions (sporadic GPS) are not enough', () {
      var s = const BoundaryState();
      for (final t in [0, 10, 20, 30]) {
        s = boundaryStep(s, area: area, now: at(t), fix: fix(100));
      }
      expect(s.phase, BoundaryPhase.warning);
      s = boundaryStep(s, area: area, now: at(35), fix: fix(100));
      expect(s.phase, BoundaryPhase.live);
    });

    test('no position for more than 15 s drops the warning', () {
      var s = walk(const BoundaryState(), 100, from: 0, to: 10);
      s = boundaryStep(s, area: area, now: at(26));
      expect(s.phase, BoundaryPhase.inside);
    });
  });

  group('afterglow: still shared 60 s after coming back (R-OUT-04)', () {
    BoundaryState live() => walk(const BoundaryState(), 100, from: 0, to: 30);

    test('stays live while outside, also with doubtful positions', () {
      var s = walk(live(), 20, from: 31, to: 200, accuracy: 80);
      expect(s.phase, BoundaryPhase.live);
      // No positions at all: still live (the last one stays online).
      s = boundaryStep(s, area: area, now: at(400));
      expect(s.phase, BoundaryPhase.live);
    });

    test('back inside → afterglow → after 60 s nothing is shared', () {
      var s = walk(live(), -10, from: 31, to: 31);
      expect(s.phase, BoundaryPhase.afterglow);
      expect(s.afterglowUntil, at(91));
      expect(s.sharing, isTrue);
      s = walk(s, -10, from: 32, to: 90);
      expect(s.phase, BoundaryPhase.afterglow);
      s = boundaryStep(s, area: area, now: at(91));
      expect(s.phase, BoundaryPhase.inside);
      expect(s.sharing, isFalse);
    });

    test('leaving again during the afterglow → live at once', () {
      var s = walk(live(), -10, from: 31, to: 40);
      s = walk(s, 100, from: 41, to: 41);
      expect(s.phase, BoundaryPhase.live);
    });

    test('the afterglow is not extended by positions inside', () {
      var s = walk(live(), -10, from: 31, to: 31);
      s = walk(s, -10, from: 32, to: 95);
      expect(s.phase, BoundaryPhase.inside);
    });
  });

  test('play area removed → nothing shared', () {
    final s = walk(const BoundaryState(), 100, from: 0, to: 30);
    expect(s.phase, BoundaryPhase.live);
    expect(
      boundaryStep(s, area: const [], now: at(31)).phase,
      BoundaryPhase.inside,
    );
  });
}
