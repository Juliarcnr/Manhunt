import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/round/round_result.dart';
import 'package:manhunt/core/schedule/game_clock.dart';

void main() {
  final start = DateTime.utc(2026, 10, 4, 14);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));
  const settings = GameSettings(); // 3 h
  final clock = GameClock(startAt: start, settings: settings);

  const members = [
    Member(id: 'h', name: 'Alex', role: Role.hunter),
    Member(id: 'k', name: 'Kim', role: Role.player, caught: true),
    Member(id: 's', name: 'Sam', role: Role.player),
    Member(id: 'l', name: 'Lou', role: Role.player),
  ];
  final allCaught = [
    for (final m in members) m.isPlayer ? m.copyWith(caught: true) : m,
  ];

  group('roundResult (R-GAME-09)', () {
    test('null while the game is on or without start time', () {
      expect(roundResult(clock: clock, now: at(60), members: members), isNull);
      expect(roundResult(clock: null, now: at(200), members: members), isNull);
    });

    test('time up: the players never caught won', () {
      final r = roundResult(clock: clock, now: at(180), members: members);
      expect((r! as PlayersWon).playerIds, ['s', 'l']);
      expect(winnerIds(r, members), {'s', 'l'});
    });

    test('time up with everyone caught: the hunters won', () {
      final r = roundResult(clock: clock, now: at(181), members: allCaught);
      expect(r, isA<HuntersWon>());
      expect(winnerIds(r!, allCaught), {'h'});
    });

    test('no players known (members still loading): no result yet', () {
      expect(
        roundResult(clock: clock, now: at(181), members: const []),
        isNull,
      );
    });

    test('last player caught: the hunters won (R-GAME-08)', () {
      final won = GameClock(
        startAt: start,
        settings: settings,
        finishedAt: at(90),
      );
      // Even if the catch itself has not arrived yet.
      expect(
        roundResult(clock: won, now: at(91), members: members),
        isA<HuntersWon>(),
      );
    });
  });
}
