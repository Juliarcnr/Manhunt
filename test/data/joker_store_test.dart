import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/data/joker_store.dart';

void main() {
  final round = DateTime.utc(2026, 10, 5, 14);
  final at = round.add(const Duration(minutes: 30));
  final jokers = SavedJokers(
    roundStart: round,
    hunters: (
      at: at,
      positions: {
        'alex': LocationFix(point: const GeoPoint(52.5, 13.4), at: at),
      },
    ),
    players: (at: at, requestId: 'r1'),
  );

  group('joker results are kept per round (R-PLAY-04)', () {
    test('roundtrip', () async {
      final store = MemoryJokerStore();
      await store.save('g1', jokers);
      final back = await store.load('g1', round);
      expect(
        back!.hunters!.positions['alex']!.point,
        const GeoPoint(52.5, 13.4),
      );
      expect(back.hunters!.at, at);
      expect(back.players!.requestId, 'r1');
    });

    test('another round → nothing', () async {
      final store = MemoryJokerStore();
      await store.save('g1', jokers);
      expect(
        await store.load('g1', round.add(const Duration(hours: 4))),
        isNull,
      );
    });

    test('only one joker used', () async {
      final store = MemoryJokerStore();
      await store.save(
        'g1',
        SavedJokers(roundStart: round)
            .copyWith(players: (at: at, requestId: 'r2')),
      );
      final back = await store.load('g1', round);
      expect(back!.hunters, isNull);
      expect(back.players!.requestId, 'r2');
    });
  });
}
