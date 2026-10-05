import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/round/joker.dart';

void main() {
  final t = DateTime.utc(2026, 10, 5, 14);
  JokerRequest req(String id, String by, int secondsAgo) => JokerRequest(
    id: id,
    requesterId: by,
    at: t.subtract(Duration(seconds: secondsAgo)),
  );

  group('requestsToAnswer (R-PLAY-03)', () {
    test('answers fresh requests of other players', () {
      final result = requestsToAnswer(
        [req('r1', 'kim', 5)],
        myId: 'sam',
        now: t,
        answered: {},
      );
      expect(result.single.id, 'r1');
    });

    test('never answers own request', () {
      expect(
        requestsToAnswer(
          [req('r1', 'sam', 5)],
          myId: 'sam',
          now: t,
          answered: {},
        ),
        isEmpty,
      );
    });

    test('answers only once', () {
      expect(
        requestsToAnswer(
          [req('r1', 'kim', 5)],
          myId: 'sam',
          now: t,
          answered: {'r1'},
        ),
        isEmpty,
      );
    });

    test('ignores old requests (phone was offline)', () {
      expect(
        requestsToAnswer(
          [req('r1', 'kim', 3 * 60)],
          myId: 'sam',
          now: t,
          answered: {},
        ),
        isEmpty,
      );
    });
  });
}
