import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/teams/start_check.dart';

void main() {
  const area = [GeoPoint(52, 13), GeoPoint(52, 13.1), GeoPoint(52.1, 13.1)];
  const ready = GameSettings(area: area);
  const hunter = Member(id: 'h', name: 'H', role: Role.hunter);
  const player = Member(id: 'p', name: 'P', role: Role.player);

  group('StartCheck (R-LOBBY-06)', () {
    test('ok with area, hunter and player', () {
      expect(StartCheck(ready, [hunter, player]).canStart, isTrue);
    });

    test('blocked while someone is unassigned', () {
      final c = StartCheck(ready, [
        hunter,
        player,
        const Member(id: 'u', name: 'U'),
      ]);
      expect(c.hasUnassigned, isTrue);
      expect(c.canStart, isFalse);
    });

    test('needs at least one hunter and one player', () {
      expect(StartCheck(ready, [hunter]).noPlayer, isTrue);
      expect(StartCheck(ready, [player]).noHunter, isTrue);
    });

    test('blocked without play area', () {
      final c = StartCheck(const GameSettings(), [hunter, player]);
      expect(c.settingsErrors, [SettingsError.areaMissing]);
      expect(c.canStart, isFalse);
    });

    test(
      'manual swaps count, not the configured hunter number (R-LOBBY-05)',
      () {
        const twoHunters = GameSettings(area: area, hunterCount: 2);
        expect(StartCheck(twoHunters, [hunter, player]).canStart, isTrue);
      },
    );
  });
}
