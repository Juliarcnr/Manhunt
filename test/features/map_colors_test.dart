import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/features/game/game_map_layers.dart';
import 'package:manhunt/theme/app_theme.dart';

void main() {
  test('every player gets an own colour (R-HUNT-03)', () {
    final players = playerColors(['p1', 'p2', 'p3', 'p4']);
    expect(players.values.toSet(), hasLength(4));
    expect(players.values, isNot(contains(AppColors.speedhunt)));
  });

  test('player colours are easy to tell from the hunter orange-red '
      '(R-HUNT-02, R-PLAY-02, R-PLAY-03)', () {
    final hunter = HSVColor.fromColor(AppColors.hunter);
    for (final c in AppColors.playerPalette) {
      final p = HSVColor.fromColor(c);
      final d = (p.hue - hunter.hue).abs();
      final hueDistance = d > 180 ? 360 - d : d;
      // Either a clearly different hue or nearly colourless (white, brown).
      expect(
        hueDistance >= 30 || p.saturation < 0.3,
        isTrue,
        reason: '$c is too close to the hunter colour',
      );
    }
  });

  test('colours repeat only after the palette is used up', () {
    final ids = [for (var i = 0; i < 12; i++) 'p$i'];
    final colors = playerColors(ids);
    expect(colors['p0'], colors['p${AppColors.playerPalette.length}']);
  });
}
