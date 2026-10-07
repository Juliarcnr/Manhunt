import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/features/game/map_filters.dart';

void main() {
  group('player chip cycles off → points → lines → off (R-HUNT-04, '
      'R-HUNT-05)', () {
    test('three taps and back to the start', () {
      var f = const MapFilters();
      expect(f.historyOf('kim'), HistoryMode.off);
      f = f.cyclePlayer('kim');
      expect(f.historyOf('kim'), HistoryMode.points);
      f = f.cyclePlayer('kim');
      expect(f.historyOf('kim'), HistoryMode.lines);
      f = f.cyclePlayer('kim');
      expect(f.historyOf('kim'), HistoryMode.off);
      expect(f.playerHistories, isEmpty);
    });

    test('players are independent', () {
      final f = const MapFilters().cyclePlayer('kim').cyclePlayer('sam');
      expect(f.cyclePlayer('kim').historyOf('sam'), HistoryMode.points);
    });
  });

  test('speedhunts are shown until switched off (R-HUNT-07)', () {
    final f = const MapFilters().toggleSpeedhunt('sam_1');
    expect(f.hiddenSpeedhunts, {'sam_1'});
    expect(f.toggleSpeedhunt('sam_1').hiddenSpeedhunts, isEmpty);
  });

  test('"caught" chip starts off and keeps the other filters (R-HUNT-09)', () {
    const f = MapFilters(hiddenSpeedhunts: {'sam_1'});
    expect(f.caught, isFalse);
    final on = f.copyWith(caught: true);
    expect(on.caught, isTrue);
    expect(on.hiddenSpeedhunts, {'sam_1'});
  });
}
