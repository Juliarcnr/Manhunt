import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/data/joker_store.dart';

void main() {
  final round = DateTime.utc(2026, 10, 5, 14);
  final at = round.add(const Duration(minutes: 30));
  final jokers = SavedJokers(
    roundStart: round,
    hunters: [
      (
        at: at,
        positions: {
          'alex': LocationFix(point: const GeoPoint(52.5, 13.4), at: at),
        },
      ),
    ],
    players: (at: at, requestId: 'r1'),
  );

  group('joker results are kept per round (R-PLAY-04)', () {
    test('roundtrip', () async {
      final store = MemoryJokerStore();
      await store.save('g1', jokers);
      final back = await store.load('g1', round);
      expect(
        back!.hunters.single.positions['alex']!.point,
        const GeoPoint(52.5, 13.4),
      );
      expect(back.hunters.single.at, at);
      expect(back.players!.requestId, 'r1');
    });

    test('own ⚡ pings are kept too (R-SPEED-09)', () async {
      final store = MemoryJokerStore();
      final fix = LocationFix(point: const GeoPoint(52.6, 13.4), at: at);
      await store.save(
        'g1',
        SavedJokers(roundStart: round)
            .copyWith(speedhuntPings: {'speedhunt_1_1': fix}),
      );
      final back = await store.load('g1', round);
      expect(
        back!.speedhuntPings['speedhunt_1_1']!.point,
        const GeoPoint(52.6, 13.4),
      );
      // Saved before the field existed: none.
      expect(SavedJokers.fromJson(jokers.toJson()).speedhuntPings, isEmpty);
    });

    test('the accepted live view is kept per round (R-GM-08)', () async {
      final store = MemoryJokerStore();
      expect(jokers.liveViewAccepted, isFalse);
      await store.save('g1', jokers.copyWith(liveViewAccepted: true));
      expect((await store.load('g1', round))!.liveViewAccepted, isTrue);
      expect(
        await store.load('g1', round.add(const Duration(hours: 4))),
        isNull,
      );
    });

    test('another round → nothing', () async {
      final store = MemoryJokerStore();
      await store.save('g1', jokers);
      expect(
        await store.load('g1', round.add(const Duration(hours: 4))),
        isNull,
      );
    });

    test('several hunter jokers are kept in order (R-SET-09)', () async {
      final store = MemoryJokerStore();
      final later = at.add(const Duration(minutes: 40));
      await store.save(
        'g1',
        jokers.copyWith(
          hunters: [
            ...jokers.hunters,
            (
              at: later,
              positions: {
                'lou': LocationFix(
                  point: const GeoPoint(52.7, 13.5),
                  at: later,
                ),
              },
            ),
          ],
        ),
      );
      final back = (await store.load('g1', round))!.hunters;
      expect([for (final r in back) r.at], [at, later]);
      expect(back.last.positions['lou']!.point, const GeoPoint(52.7, 13.5));
    });

    test('a single hunter joker saved by an older app version is read '
        '(R-SET-09)', () {
      final json = jokers.toJson();
      final reveals = json.remove('hunterReveals')! as List<Object?>;
      json['hunters'] = reveals.single;
      final back = SavedJokers.fromJson(json);
      expect(back.hunters.single.at, at);
      expect(
        back.hunters.single.positions['alex']!.point,
        const GeoPoint(52.5, 13.4),
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
      expect(back!.hunters, isEmpty);
      expect(back.players!.requestId, 'r2');
    });
  });
}
