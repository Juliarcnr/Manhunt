import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/core/schedule/game_clock.dart';
import 'package:manhunt/core/schedule/speedhunt.dart';

void main() {
  final start = DateTime.utc(2026, 10, 4, 14);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));
  final clock = GameClock(
    startAt: start,
    settings: const GameSettings(duration: Duration(hours: 1)),
  );
  Speedhunt speedhunt(int minute) => Speedhunt.fromSettings(
    targetId: 'me',
    startedAt: at(minute),
    settings: const GameSettings(),
  );

  group('playerPingSlots (R-PING-02, R-SPEED-03)', () {
    test('regular pings only', () {
      final slots = playerPingSlots(clock: clock, speedhuntsOnMe: []);
      expect(slots.map((s) => s.id), ['regular_1', 'regular_2']);
      expect(slots.map((s) => s.at), [at(20), at(40)]);
    });

    test('speedhunt pings merged chronologically', () {
      final slots = playerPingSlots(
        clock: clock,
        speedhuntsOnMe: [speedhunt(30)],
      );
      expect(slots.map((s) => s.at), [at(20), at(30), at(35), at(40), at(40)]);
      expect(slots.where((s) => s.kind == PingKind.speedhunt), hasLength(3));
    });

    test('ids are deterministic and unique', () {
      final a = playerPingSlots(clock: clock, speedhuntsOnMe: [speedhunt(30)]);
      final b = playerPingSlots(clock: clock, speedhuntsOnMe: [speedhunt(30)]);
      expect(a, b);
      expect(a.map((s) => s.id).toSet(), hasLength(a.length));
    });

    test('speedhunt pings after the round time are dropped', () {
      final slots = playerPingSlots(
        clock: clock,
        speedhuntsOnMe: [speedhunt(55)],
      );
      final sh = slots.where((s) => s.kind == PingKind.speedhunt);
      expect(sh.map((s) => s.at), [at(55)]);
    });
  });

  group('duePings', () {
    final slots = playerPingSlots(clock: clock, speedhuntsOnMe: []);

    test('nothing due before the first ping', () {
      expect(duePings(slots, now: at(19), sentIds: {}), isEmpty);
    });

    test('due exactly at the time and shortly after', () {
      expect(duePings(slots, now: at(20), sentIds: {}).single.id, 'regular_1');
      expect(duePings(slots, now: at(22), sentIds: {}).single.id, 'regular_1');
    });

    test('not sent twice', () {
      expect(duePings(slots, now: at(20), sentIds: {'regular_1'}), isEmpty);
    });

    test('too late pings are skipped (stale position)', () {
      expect(duePings(slots, now: at(24), sentIds: {}), isEmpty);
    });
  });

  test('nextPing', () {
    final slots = playerPingSlots(clock: clock, speedhuntsOnMe: []);
    expect(nextPing(slots, at(0))!.at, at(20));
    expect(nextPing(slots, at(20))!.at, at(40));
    expect(nextPing(slots, at(50)), isNull);
  });

  test('activeSpeedhunt (R-SPEED-05)', () {
    final s = speedhunt(30);
    expect(activeSpeedhunt([s], at(29)), isNull);
    expect(activeSpeedhunt([s], at(33)), s);
    expect(activeSpeedhunt([s], at(41)), isNull);
  });

  test('LocationFix json roundtrip', () {
    final fix = LocationFix(
      point: const GeoPoint(52.5, 13.4),
      at: at(20),
      accuracyM: 8.5,
    );
    final back = LocationFix.fromJson(fix.toJson());
    expect(back.point, fix.point);
    expect(back.at, fix.at);
    expect(back.accuracyM, 8.5);
  });

  test('pingsByPlayer groups and sorts (R-HUNT-04)', () {
    PingRecord p(String id, int minute) => PingRecord(
      playerId: id,
      kind: PingKind.regular,
      fix: LocationFix(point: const GeoPoint(0, 0), at: at(minute)),
    );
    final grouped = pingsByPlayer([p('a', 40), p('b', 20), p('a', 20)]);
    expect(grouped['a']!.map((r) => r.fix.at), [at(20), at(40)]);
    expect(grouped['b'], hasLength(1));
  });

  test('lastRegularPing skips speedhunt pings (R-HUNT-03)', () {
    PingRecord p(PingKind kind, int minute) => PingRecord(
      playerId: 'a',
      kind: kind,
      fix: LocationFix(point: const GeoPoint(0, 0), at: at(minute)),
    );
    final regular = p(PingKind.regular, 20);
    expect(
      lastRegularPing([
        p(PingKind.regular, 10),
        regular,
        p(PingKind.speedhunt, 30),
      ]),
      same(regular),
    );
    expect(lastRegularPing([p(PingKind.speedhunt, 30)]), isNull);
    expect(lastRegularPing(const []), isNull);
  });

  test(
    'latestSpeedhuntPings: newest speedhunt ping per player (R-HUNT-07)',
    () {
      PingRecord p(String player, PingKind kind, int minute) => PingRecord(
        playerId: player,
        kind: kind,
        fix: LocationFix(point: const GeoPoint(0, 0), at: at(minute)),
      );
      final a2 = p('a', PingKind.speedhunt, 35);
      final b1 = p('b', PingKind.speedhunt, 20);
      final latest = latestSpeedhuntPings([
        a2,
        p('a', PingKind.speedhunt, 30),
        p('a', PingKind.regular, 40),
        b1,
      ]);
      expect(latest, {'a': same(a2), 'b': same(b1)});
      expect(latestSpeedhuntPings([p('a', PingKind.regular, 10)]), isEmpty);
    },
  );

  test('nextSpeedhuntPing counts down the speedhunt (R-SPEED-08)', () {
    final s = speedhunt(30); // pings at 30, 35, 40
    expect(nextSpeedhuntPing(s, at(29)), (number: 1, at: at(30)));
    expect(nextSpeedhuntPing(s, at(30)), (number: 2, at: at(35)));
    expect(nextSpeedhuntPing(s, at(37)), (number: 3, at: at(40)));
    expect(nextSpeedhuntPing(s, at(40)), isNull);
  });
}
