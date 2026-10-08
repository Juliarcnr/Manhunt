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

  group('hasNewRegularPing (R-HUNT-08)', () {
    PingRecord p(String player, PingKind kind, String slot) => PingRecord(
      playerId: player,
      kind: kind,
      slotId: slot,
      fix: LocationFix(point: const GeoPoint(0, 0), at: at(10)),
    );
    final old = p('a', PingKind.regular, 'regular_1');

    test('a new regular ping counts', () {
      expect(
        hasNewRegularPing([old], [old, p('a', PingKind.regular, 'regular_2')]),
        isTrue,
      );
      // Same slot, other player.
      expect(
        hasNewRegularPing([old], [old, p('b', PingKind.regular, 'regular_1')]),
        isTrue,
      );
    });

    test('speedhunt pings, unchanged lists and the first load do not', () {
      expect(
        hasNewRegularPing(
          [old],
          [old, p('a', PingKind.speedhunt, 'speedhunt_1_1')],
        ),
        isFalse,
      );
      expect(hasNewRegularPing([old], [old]), isFalse);
      expect(hasNewRegularPing(null, [old]), isFalse);
    });
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

  test('latestSpeedhuntPings follows the slot order, even when the resent '
      'fix has the same time (R-HUNT-07)', () {
    PingRecord sh(String slot) => PingRecord(
      playerId: 'a',
      kind: PingKind.speedhunt,
      slotId: slot,
      // Phone did not move: every ping resends the same fix.
      fix: LocationFix(point: const GeoPoint(0, 0), at: at(30)),
    );
    final first = sh('speedhunt_1000_1');
    final second = sh('speedhunt_1000_2');
    expect(latestSpeedhuntPings([first, second])['a'], same(second));
    expect(latestSpeedhuntPings([second, first])['a'], same(second));
    // A later speedhunt beats a higher number of an earlier one.
    final next = sh('speedhunt_2000_1');
    expect(
      latestSpeedhuntPings([sh('speedhunt_1000_3'), next])['a'],
      same(next),
    );
  });

  group('regularPings / speedhuntsFromPings (R-HUNT-04, R-HUNT-07)', () {
    PingRecord p(String player, String slot, int minute) => PingRecord(
      playerId: player,
      kind: slot.startsWith('speedhunt')
          ? PingKind.speedhunt
          : PingKind.regular,
      slotId: slot,
      fix: LocationFix(point: const GeoPoint(0, 0), at: at(minute)),
    );
    final shA = at(30).millisecondsSinceEpoch;
    final shB = at(50).millisecondsSinceEpoch;

    test('regularPings drops speedhunt pings, keeps the order', () {
      final r1 = p('a', 'regular_1', 20);
      final r2 = p('a', 'regular_2', 40);
      expect(regularPings([r1, p('a', 'speedhunt_${shA}_1', 30), r2]), [
        same(r1),
        same(r2),
      ]);
    });

    test('one group per speedhunt, oldest first, pings by number', () {
      final b1 = p('b', 'speedhunt_${shB}_1', 50);
      final a1 = p('a', 'speedhunt_${shA}_1', 30);
      final a2 = p('a', 'speedhunt_${shA}_2', 35);
      final groups = speedhuntsFromPings([b1, a2, p('a', 'regular_1', 20), a1]);
      expect(groups.map((g) => g.playerId), ['a', 'b']);
      expect(groups.first.startedAt, at(30));
      expect(groups.first.pings, [same(a1), same(a2)]);
      expect(groups.last.pings, [same(b1)]);
      expect(groups.first.id, 'a_$shA');
    });

    test('same player, two speedhunts → two groups; bad ids ignored', () {
      final groups = speedhuntsFromPings([
        p('a', 'speedhunt_${shA}_1', 30),
        p('a', 'speedhunt_${shB}_1', 50),
        p('a', 'speedhunt_broken', 55),
      ]);
      expect(groups.map((g) => g.startedAt), [at(30), at(50)]);
      expect(speedhuntsFromPings([p('a', 'regular_1', 20)]), isEmpty);
    });
  });

  group('speedhuntsWithNewPings (R-HUNT-08)', () {
    PingRecord p(String player, String slot) => PingRecord(
      playerId: player,
      kind: slot.startsWith('speedhunt')
          ? PingKind.speedhunt
          : PingKind.regular,
      slotId: slot,
      fix: LocationFix(point: const GeoPoint(0, 0), at: at(30)),
    );
    final ms = at(30).millisecondsSinceEpoch;
    final a1 = p('a', 'speedhunt_${ms}_1');

    test('a new ping names its speedhunt', () {
      expect(speedhuntsWithNewPings([a1], [a1, p('a', 'speedhunt_${ms}_2')]), {
        'a_$ms',
      });
      // Brand-new speedhunt of another player.
      expect(speedhuntsWithNewPings([a1], [a1, p('b', 'speedhunt_${ms}_1')]), {
        'b_$ms',
      });
    });

    test('regular pings, unchanged lists and the first load do not', () {
      expect(speedhuntsWithNewPings([a1], [a1, p('a', 'regular_1')]), isEmpty);
      expect(speedhuntsWithNewPings([a1], [a1]), isEmpty);
      expect(speedhuntsWithNewPings(null, [a1]), isEmpty);
    });
  });

  test('nextSpeedhuntPing counts down the speedhunt (R-SPEED-08)', () {
    final s = speedhunt(30); // pings at 30, 35, 40
    expect(nextSpeedhuntPing(s, at(29)), (number: 1, at: at(30)));
    expect(nextSpeedhuntPing(s, at(30)), (number: 2, at: at(35)));
    expect(nextSpeedhuntPing(s, at(37)), (number: 3, at: at(40)));
    expect(nextSpeedhuntPing(s, at(40)), isNull);
  });

  group('caught players & shared pings (R-HUNT-11, R-PLAY-05)', () {
    PingRecord p(
      String player,
      String slot, {
      PingKind kind = PingKind.regular,
    }) => PingRecord(
      playerId: player,
      kind: kind,
      slotId: slot,
      fix: LocationFix(point: const GeoPoint(0, 0), at: start),
    );

    test('regularPingNumber reads the slot id', () {
      expect(regularPingNumber(p('a', 'regular_12')), 12);
      expect(
        regularPingNumber(p('a', 'speedhunt_1_2', kind: PingKind.speedhunt)),
        isNull,
      );
    });

    test('lastRegularPings: latest regular ping per player, minus skipped', () {
      final byPlayer = pingsByPlayer([
        p('a', 'regular_1'),
        p('a', 'regular_2'),
        p('b', 'regular_1'),
        p('c', 'speedhunt_1_1', kind: PingKind.speedhunt),
      ]);
      final last = lastRegularPings(byPlayer, skip: {'b'});
      expect(last.keys, ['a']);
      expect(last['a']!.slotId, 'regular_2');
    });

    test('a caught player stays until newer pings arrive', () {
      final pings = [p('a', 'regular_1'), p('b', 'regular_1')];
      // Caught after ping 1: still shown (greyed by the caller).
      expect(
        sharedLastPings(pingsByPlayer(pings), caught: {'b'}).keys,
        unorderedEquals(['a', 'b']),
      );
      // Ping 2 of the others: the caught player's old pin disappears.
      final later = pingsByPlayer([...pings, p('a', 'regular_2')]);
      expect(sharedLastPings(later, caught: {'b'}).keys, ['a']);
      // Uncaught players keep their last pin, even if a ping is missing.
      expect(
        sharedLastPings(later, caught: const {}).keys,
        unorderedEquals(['a', 'b']),
      );
      expect(sharedLastPings(later, caught: const {}, skip: {'a'}).keys, ['b']);
      // Newer pings of a skipped player (the own device) count as well.
      expect(sharedLastPings(later, caught: {'b'}, skip: {'a'}), isEmpty);
    });

    test('after the time is up nobody counts as caught on the map', () {
      expect(caughtOnMap({'a'}, GamePhase.hunting), {'a'});
      expect(caughtOnMap({'a'}, GamePhase.ended), isEmpty);
    });
  });
}
