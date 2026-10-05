import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/features/game/game_map_layers.dart';
import 'package:manhunt/theme/app_theme.dart';

void main() {
  test(
    'every hunter and every player gets an own colour (R-HUNT-02, R-HUNT-03)',
    () {
      final hunters = hunterColors(['h1', 'h2', 'h3']);
      final players = playerColors(['p1', 'p2', 'p3', 'p4']);
      expect(hunters.values.toSet(), hasLength(3));
      expect(players.values.toSet(), hasLength(4));
      // Hunter and player colours never mix up.
      expect(
        hunters.values.toSet().intersection(players.values.toSet()),
        isEmpty,
      );
      expect(players.values, isNot(contains(AppColors.speedhunt)));
    },
  );

  test('colours repeat only after the palette is used up', () {
    final ids = [for (var i = 0; i < 12; i++) 'p$i'];
    final colors = playerColors(ids);
    expect(colors['p0'], colors['p${AppColors.playerPalette.length}']);
  });
}
