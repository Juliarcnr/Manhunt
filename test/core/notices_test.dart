import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/round/notices.dart';
import 'package:manhunt/core/schedule/speedhunt.dart';

void main() {
  final t = DateTime.utc(2026, 10, 4, 14);
  CatchRecord c(String player, int minute) => CatchRecord(
    playerId: player,
    at: t.add(Duration(minutes: minute)),
  );
  Speedhunt sh(int minute) => Speedhunt.fromSettings(
    targetId: '',
    startedAt: t.add(Duration(minutes: minute)),
    settings: const GameSettings(),
  );

  group('NoticeTracker (R-NOTIF-02, R-NOTIF-04)', () {
    test('first snapshot is the baseline – no old news', () {
      final tracker = NoticeTracker();
      expect(tracker.onCatches([c('kim', 5)]), isEmpty);
      expect(tracker.onSpeedhunts([sh(10)]), isEmpty);
    });

    test('new catch is announced once', () {
      final tracker = NoticeTracker()..onCatches([]);
      final notices = tracker.onCatches([c('kim', 5)]);
      expect((notices.single as CatchNotice).record.playerId, 'kim');
      expect(tracker.onCatches([c('kim', 5)]), isEmpty);
    });

    test('double report of the same catch is one notice', () {
      final tracker = NoticeTracker()..onCatches([]);
      final notices = tracker.onCatches([c('kim', 5), c('kim', 6)]);
      expect(notices, hasLength(1));
    });

    test('new speedhunt is announced', () {
      final tracker = NoticeTracker()..onSpeedhunts([sh(10)]);
      final notices = tracker.onSpeedhunts([sh(10), sh(40)]);
      expect(
        (notices.single as SpeedhuntNotice).speedhunt.startedAt,
        t.add(const Duration(minutes: 40)),
      );
    });
  });
}
