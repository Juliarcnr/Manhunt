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

    test('unassigned members simply sit out (R-LOBBY-11)', () {
      final c = StartCheck(ready, [
        hunter,
        player,
        const Member(id: 'u', name: 'U'),
      ], adminId: 'h');
      expect(c.hostUnassigned, isFalse);
      expect(c.canStart, isTrue);
    });

    test('blocked while the host is unassigned (R-LOBBY-13)', () {
      final c = StartCheck(ready, [
        hunter,
        player,
        const Member(id: 'u', name: 'U'),
      ], adminId: 'u');
      expect(c.hostUnassigned, isTrue);
      expect(c.canStart, isFalse);
    });

    test('a game master counts as assigned, not as hunter or player '
        '(R-GM-01)', () {
      const gm = Member(id: 'g', name: 'G', role: Role.gameMaster);
      expect(
        StartCheck(ready, [hunter, player, gm], adminId: 'g').canStart,
        isTrue,
      );
      expect(StartCheck(ready, [hunter, gm]).noPlayer, isTrue);
      expect(StartCheck(ready, [player, gm]).noHunter, isTrue);
    });

    test('needs at least one hunter and one player', () {
      expect(StartCheck(ready, [hunter]).noPlayer, isTrue);
      expect(StartCheck(ready, [player]).noHunter, isTrue);
      const u = Member(id: 'u', name: 'U');
      final onlyUnassigned = StartCheck(ready, [u, u]);
      expect(onlyUnassigned.noHunter && onlyUnassigned.noPlayer, isTrue);
      expect(onlyUnassigned.canStart, isFalse);
    });

    test('blocked without play area', () {
      final c = StartCheck(const GameSettings(), [hunter, player]);
      expect(c.settingsErrors, [SettingsError.areaMissing]);
      expect(c.canStart, isFalse);
    });
  });
}
