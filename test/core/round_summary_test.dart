import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/core/models/member.dart';

void main() {
  final start = DateTime.utc(2026, 10, 4, 14);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));

  const members = [
    Member(id: 'h1', name: 'Alex', role: Role.hunter),
    Member(id: 'p1', name: 'Kim', role: Role.player),
    Member(id: 'p2', name: 'Sam', role: Role.player),
    Member(id: 'p3', name: 'Lou', role: Role.player),
  ];

  RoundSummary build(List<CatchRecord> catches) => RoundSummary.build(
    round: 2,
    startedAt: start,
    endedAt: at(190),
    members: members,
    catches: catches,
  );

  group('RoundSummary (R-HIST-01, R-HIST-02)', () {
    test('teams, duration and catches with names and time since start', () {
      final s = build([
        CatchRecord(playerId: 'p2', at: at(95)),
        CatchRecord(playerId: 'p1', at: at(72)),
      ]);
      expect(s.round, 2);
      expect(s.duration, const Duration(minutes: 190));
      expect(s.hunters, ['Alex']);
      expect(s.players, ['Kim', 'Sam', 'Lou']);
      expect(s.catches.map((c) => c.player), ['Kim', 'Sam']);
      expect(s.catches.first.after, const Duration(minutes: 72));
      expect(s.survivors, ['Lou']);
    });

    test('nothing about who caught is stored (R-CATCH-03)', () {
      final s = build([CatchRecord(playerId: 'p1', at: at(10))]);
      expect(s.toJson().toString(), isNot(contains('caught')));
      expect(CatchRecord(playerId: 'p1', at: at(10)).toJson().keys, [
        'playerId',
        'at',
      ]);
    });

    test('double report (hunter + player) counts once, earliest time', () {
      final s = build([
        CatchRecord(playerId: 'p1', at: at(30)),
        CatchRecord(playerId: 'p1', at: at(30)),
        CatchRecord(playerId: 'p1', at: at(31)),
      ]);
      expect(s.catches, hasLength(1));
    });

    test('ending before the planned time marks the round aborted '
        '(R-GAME-07)', () {
      RoundSummary endAt(int minute) => RoundSummary.build(
        round: 1,
        startedAt: start,
        endedAt: at(minute),
        members: members,
        catches: const [],
        plannedDuration: const Duration(hours: 3),
      );
      expect(endAt(90).abortedEarly, isTrue);
      expect(endAt(180).abortedEarly, isFalse);
      expect(endAt(200).abortedEarly, isFalse);
      expect(RoundSummary.fromJson(endAt(90).toJson()).abortedEarly, isTrue);
    });

    test('catches of people who left the group are skipped', () {
      final s = build([CatchRecord(playerId: 'gone', at: at(30))]);
      expect(s.catches, isEmpty);
    });

    test('json roundtrip', () {
      final s = build([
        CatchRecord(playerId: 'p1', at: at(72)),
        CatchRecord(playerId: 'p2', at: at(80)),
      ]);
      final back = RoundSummary.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
      expect(back.survivors, ['Lou']);
    });

    test('CatchRecord json roundtrip', () {
      final c = CatchRecord(playerId: 'p1', at: at(5));
      expect(CatchRecord.fromJson(c.toJson()).toJson(), c.toJson());
    });
  });
}
