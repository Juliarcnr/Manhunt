import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/round/player_aliases.dart';
import 'package:manhunt/core/schedule/game_clock.dart';

void main() {
  group('anonymous numbers (R-ANON-01)', () {
    test('every player gets one of 1 … n, shuffled', () {
      final ids = [for (var i = 0; i < 8; i++) 'p$i'];
      final aliases = shuffleAliases(ids, Random(1));
      expect(aliases.keys, unorderedEquals(ids));
      expect(aliases.values, unorderedEquals([for (var i = 1; i <= 8; i++) i]));
      // Not simply the join order for every seed.
      final orders = {
        for (var seed = 0; seed < 10; seed++)
          [for (final id in ids) shuffleAliases(ids, Random(seed))[id]].join(),
      };
      expect(orders.length, greaterThan(1));
    });

    test('no players, no numbers', () {
      expect(shuffleAliases(const [], Random(1)), isEmpty);
    });

    test('players without a number get the next free ones; existing numbers '
        'never move', () {
      final complete = completeAliases(
        {'kim': 2, 'sam': 1, 'gone': 3},
        ['sam', 'new1', 'kim', 'new2'],
      );
      expect(complete, {'sam': 1, 'new1': 4, 'kim': 2, 'new2': 5});
      expect(completeAliases(const {}, ['a', 'b']), {'a': 1, 'b': 2});
    });

    test('players are ordered by number, not by joining', () {
      expect(byAlias({'kim': 2, 'sam': 1}, ['kim', 'sam', 'new']), [
        'sam',
        'kim',
        'new',
      ]);
    });
  });

  group('who sees numbers (R-ANON-02, R-ANON-03)', () {
    test('only hunters, only with the setting, only until the time is up', () {
      for (final phase in [
        GamePhase.notStarted,
        GamePhase.headStart,
        GamePhase.hunting,
      ]) {
        expect(
          showAliases(enabled: true, isHunter: true, phase: phase),
          isTrue,
          reason: '$phase',
        );
      }
      expect(
        showAliases(enabled: true, isHunter: true, phase: GamePhase.ended),
        isFalse,
      );
      expect(
        showAliases(enabled: true, isHunter: false, phase: GamePhase.hunting),
        isFalse,
      );
      expect(
        showAliases(enabled: false, isHunter: true, phase: GamePhase.hunting),
        isFalse,
      );
    });
  });
}
