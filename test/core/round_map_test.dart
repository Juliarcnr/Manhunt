import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/history/round_map.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/core/schedule/speedhunt.dart';

void main() {
  final start = DateTime.utc(2026, 11, 1, 14);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));
  LocationFix fix(double lat, int minutes) =>
      LocationFix(point: GeoPoint(lat, 13.4), at: at(minutes));
  final shMs = at(70).millisecondsSinceEpoch;
  String sh(int n) => 'speedhunt_${shMs}_$n';

  PingRecord ping(String uid, String slot, double lat, int minutes) =>
      PingRecord(
        playerId: uid,
        kind: slot.startsWith('speedhunt')
            ? PingKind.speedhunt
            : PingKind.regular,
        slotId: slot,
        fix: fix(lat, minutes),
      );

  const members = [
    Member(id: 'uh1', name: 'Alex', role: Role.hunter),
    Member(id: 'uk', name: 'Kim', role: Role.player),
    Member(id: 'us', name: 'Sam', role: Role.player),
    Member(id: 'uh2', name: 'Lou', role: Role.hunter),
    Member(id: 'ugm', name: 'Gina', role: Role.gameMaster),
  ];

  RoundMap build({List<String> playerOrder = const ['us', 'uk']}) =>
      RoundMap.build(
        area: const [GeoPoint(52.5, 13.4), GeoPoint(52.51, 13.41)],
        startedAt: start,
        endedAt: at(100),
        pingInterval: const Duration(minutes: 20),
        members: members,
        playerOrder: playerOrder,
        pings: [
          ping('uk', 'regular_1', 52.1, 20),
          ping('uk', 'regular_2', 52.2, 40),
          ping('us', 'regular_1', 52.3, 20),
          ping('us', 'regular_2', 52.4, 40),
          ping('us', 'regular_3', 52.5, 60),
          ping('us', sh(1), 52.6, 70),
          ping('us', sh(2), 52.7, 75),
          // Sam's position at the end (R-HIST-08).
          ping('us', endSlotId, 52.8, 100),
          // Someone who left the group.
          ping('gone', 'regular_1', 51, 20),
        ],
        hunterSnaps: [
          ping('uh1', 'regular_1', 53.1, 20),
          ping('uh1', 'regular_2', 53.2, 40),
          ping('uh2', 'regular_1', 54.1, 20),
          ping('uh1', sh(1), 53.6, 70),
          ping('uh2', sh(1), 54.6, 70),
          ping('uh2', sh(2), 54.7, 75),
        ],
        hunterLocations: {'uh1': fix(53.9, 99), 'gone': fix(1, 99)},
        catches: [
          CatchRecord(playerId: 'uk', at: at(50)),
          CatchRecord(playerId: 'uk', at: at(45)),
          CatchRecord(playerId: 'us', at: at(76)),
        ],
        speedhunts: [
          Speedhunt(
            targetId: '',
            startedAt: at(70),
            pings: 3,
            interval: const Duration(minutes: 5),
            endedAt: at(76),
          ),
        ],
      );

  group('RoundMap (R-HIST-04)', () {
    test('members are numbered in colour order, with their real names', () {
      final map = build();
      expect(map.players, ['Sam', 'Kim']);
      expect(map.hunters, ['Alex', 'Lou']);
      expect(map.playerIds, ['p0', 'p1']);
      expect(map.hunterIds, ['h0', 'h1']);
      expect(map.names, {'p0': 'Sam', 'p1': 'Kim', 'h0': 'Alex', 'h1': 'Lou'});
    });

    test('players missing from the order follow in member order', () {
      expect(build(playerOrder: const []).players, ['Kim', 'Sam']);
    });

    test('no uids are kept; people who left are dropped', () {
      final map = build();
      expect(map.pings, hasLength(7));
      expect(map.pings.where(isEndPing), isEmpty);
      expect(map.pings.map((p) => p.playerId).toSet(), {'p0', 'p1'});
      expect(map.hunterSnaps.map((p) => p.playerId).toSet(), {'h0', 'h1'});
      expect(map.lastHunters.keys, ['h0']);
    });

    test('earliest catch per player; the speedhunt knows its target', () {
      final map = build();
      expect(
        [for (final c in map.catches) (c.playerId, c.at)],
        [('p1', at(45)), ('p0', at(76))],
      );
      final s = map.speedhunts.single;
      expect(s.targetId, 'p0');
      // Ended by the catch after two pings (R-SPEED-10).
      expect(s.pingTimes, [at(70), at(75)]);
      expect(s.slotId(2), sh(2));
    });

    test('survives JSON, compact and without accuracy', () {
      final map = build();
      final back = RoundMap.fromJson(map.toJson());
      expect(back.area, map.area);
      expect(back.startedAt, start);
      expect(back.endedAt, at(100));
      expect(back.pingInterval, const Duration(minutes: 20));
      expect(back.players, map.players);
      expect(back.hunters, map.hunters);
      String key(PingRecord p) =>
          '${p.playerId} ${p.kind.name} ${p.slotId} ${p.fix.point} '
          '${p.fix.at}';
      expect(back.pings.map(key), map.pings.map(key));
      expect(back.hunterSnaps.map(key), map.hunterSnaps.map(key));
      expect(back.lastHunters['h0']!.point, map.lastHunters['h0']!.point);
      expect(
        [for (final c in back.catches) (c.playerId, c.at)],
        [for (final c in map.catches) (c.playerId, c.at)],
      );
      expect(back.speedhunts.single.targetId, 'p0');
      expect(back.speedhunts.single.pingTimes, [at(70), at(75)]);
      expect(back.endPlayers['p0']!.point, const GeoPoint(52.8, 13.4));
      expect(back.speedhunts.single.startedAt, at(70));
      expect(back.endPlayers['p0']!.point, const GeoPoint(52.8, 13.4));
    });

    test('coordinates are rounded to about 10 cm', () {
      final map = RoundMap(
        area: const [],
        startedAt: start,
        endedAt: at(10),
        pingInterval: const Duration(minutes: 5),
        players: const ['Kim'],
        hunters: const [],
        pings: [
          PingRecord(
            playerId: 'p0',
            kind: PingKind.regular,
            slotId: 'regular_1',
            fix: LocationFix(
              point: const GeoPoint(52.123456789, 13.987654321),
              at: at(5),
              accuracyM: 7,
            ),
          ),
        ],
      );
      final back = RoundMap.fromJson(map.toJson()).pings.single.fix;
      expect(back.point, const GeoPoint(52.123457, 13.987654));
      expect(back.accuracyM, isNull);
    });
  });

  group('hunters on the map (R-HIST-05)', () {
    test('each hunter has a regular history like a player', () {
      final histories = hunterHistories(build().hunterSnaps);
      expect(histories.keys.toSet(), {'h0', 'h1'});
      expect(histories['h0']!.map((p) => p.slotId), ['regular_1', 'regular_2']);
      expect(histories['h1']!.map((p) => p.slotId), ['regular_1']);
    });

    test('a speedhunt shows the hunters at its ping times', () {
      final map = build();
      final speedhunt = speedhuntsFromPings(map.pings).single;
      final snaps = hunterSnapsForSpeedhunt(map.hunterSnaps, speedhunt);
      expect(
        {for (final p in snaps) '${p.playerId} ${p.speedhuntNumber}'},
        {'h0 1', 'h1 1', 'h1 2'},
      );
    });
  });

  group('timeline (R-HIST-07)', () {
    test('regular ping times until the end, speedhunt pings in between', () {
      final steps = timelineSteps(build());
      expect(
        [for (final s in steps) (s.slotId, s.at)],
        [
          ('regular_1', at(20)),
          ('regular_2', at(40)),
          ('regular_3', at(60)),
          (sh(1), at(70)),
          (sh(2), at(75)),
          ('regular_4', at(80)),
          (endSlotId, at(100)),
        ],
      );
      expect(steps.last.isEnd, isTrue);
      expect(steps[3].kind, PingKind.speedhunt);
      expect(steps[3].targetId, 'p0');
      expect(steps[3].speedhuntNumber, 1);
      expect(steps.first.kind, PingKind.regular);
    });

    test('a regular and a speedhunt ping at the same time: regular first', () {
      final map = RoundMap(
        area: const [],
        startedAt: start,
        endedAt: at(60),
        pingInterval: const Duration(minutes: 20),
        players: const ['Kim'],
        hunters: const [],
        speedhunts: [
          RoundMapSpeedhunt(startedAt: at(40), pingTimes: [at(40)]),
        ],
      );
      expect(timelineSteps(map).map((s) => s.slotId), [
        'regular_1',
        'regular_2',
        'speedhunt_${at(40).millisecondsSinceEpoch}_1',
      ]);
    });

    test('a regular step shows everyone still in the game and all hunters', () {
      final map = build();
      final steps = timelineSteps(map);
      final first = timelineAt(map, steps[0]);
      expect(first.players.keys.toSet(), {'p0', 'p1'});
      expect(first.players['p1']!.fix.point.lat, 52.1);
      expect(first.hunters.keys.toSet(), {'h0', 'h1'});
      expect(first.hunters['h1']!.point.lat, 54.1);

      // Kim was caught at minute 45: gone at the third ping; Lou sent no
      // position at the second.
      final second = timelineAt(map, steps[1]);
      expect(second.players.keys.toSet(), {'p0', 'p1'});
      expect(second.hunters.keys, ['h0']);
      final third = timelineAt(map, steps[2]);
      expect(third.players.keys, ['p0']);
      expect(third.hunters, isEmpty);
    });

    test('a speedhunt step shows only its target and the hunters', () {
      final map = build();
      final step = timelineSteps(map)[4];
      final frame = timelineAt(map, step);
      expect(frame.players.keys, ['p0']);
      expect(frame.players['p0']!.speedhuntNumber, 2);
      expect(frame.hunters.keys, ['h1']);
    });

    test('nothing after the end, e.g. after the hunters won', () {
      final map = RoundMap(
        area: const [],
        startedAt: start,
        endedAt: at(40),
        pingInterval: const Duration(minutes: 20),
        players: const [],
        hunters: const [],
      );
      // No ping exactly at the end (R-PING-02).
      expect(timelineSteps(map).map((s) => s.slotId), ['regular_1']);
    });
  });
  group('positions at the end of the round (R-HIST-08)', () {
    test('kept apart from the pings, shown as the last timeline step', () {
      final map = build();
      expect(map.endPlayers.keys, ['p0']);
      expect(map.hasEnd, isTrue);
      final frame = timelineAt(map, timelineSteps(map).last);
      expect(frame.players['p0']!.fix.point.lat, 52.8);
      // The hunters' last live position is where they were at the end.
      expect(frame.hunters['h0']!.point.lat, 53.9);
    });

    test('no end step without any position from then (e.g. older rounds)', () {
      final map = RoundMap(
        area: const [],
        startedAt: start,
        endedAt: at(30),
        pingInterval: const Duration(minutes: 20),
        players: const ['Kim'],
        hunters: const [],
      );
      expect(map.hasEnd, isFalse);
      expect(timelineSteps(map).map((s) => s.slotId), ['regular_1']);
    });

    test('never numbered as a regular ping', () {
      final pings = [
        ping('uk', 'regular_1', 52.1, 20),
        ping('uk', endSlotId, 52.2, 30),
      ];
      expect(regularPings(pings).map((p) => p.slotId), ['regular_1']);
    });
  });

  group('round numbers (R-HIST-06)', () {
    test('one more than the highest, also after deleting a round', () {
      expect(nextRoundNumber(const []), 1);
      expect(nextRoundNumber(const [1, 2]), 3);
      expect(nextRoundNumber(const [3, 1]), 4);
    });
  });
}
