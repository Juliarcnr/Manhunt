import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/geo/polygon.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';

void main() {
  const square = [
    GeoPoint(52.0, 13.0),
    GeoPoint(52.0, 13.1),
    GeoPoint(52.1, 13.1),
    GeoPoint(52.1, 13.0),
  ];

  group('GameSettings (R-SET-*)', () {
    test('defaults match the example game', () {
      const s = GameSettings();
      expect(s.duration, const Duration(hours: 3));
      expect(s.headStart, const Duration(minutes: 15));
      expect(s.pingInterval, const Duration(minutes: 20));
      expect(s.speedhuntCount, 2);
      expect(s.speedhuntPings, 3);
      expect(s.speedhuntInterval, const Duration(minutes: 5));
    });

    test('joker is on by default and can be switched off (R-SET-09)', () {
      expect(const GameSettings().jokerEnabled, isTrue);
      const off = GameSettings(jokerEnabled: false);
      expect(GameSettings.fromJson(off.toJson()).jokerEnabled, isFalse);
      // Settings saved before the option existed keep the joker.
      final legacy = const GameSettings().toJson()..remove('jokerEnabled');
      expect(GameSettings.fromJson(legacy).jokerEnabled, isTrue);
    });

    test('player joker and earliest speedhunt (R-SET-11, R-SET-12)', () {
      const s = GameSettings();
      expect(s.playerJokerEnabled, isTrue);
      expect(s.speedhuntEarliest, const Duration(minutes: 60));
      const custom = GameSettings(
        playerJokerEnabled: false,
        speedhuntEarliest: Duration(minutes: 45),
      );
      final back = GameSettings.fromJson(custom.toJson());
      expect(back.playerJokerEnabled, isFalse);
      expect(back.speedhuntEarliest, const Duration(minutes: 45));
      // Older saved settings get the defaults.
      final legacy = s.toJson()
        ..remove('playerJokerEnabled')
        ..remove('speedhuntEarliestSec');
      expect(GameSettings.fromJson(legacy).playerJokerEnabled, isTrue);
      expect(
        GameSettings.fromJson(legacy).speedhuntEarliest,
        const Duration(minutes: 60),
      );
    });

    test('json roundtrip', () {
      const s = GameSettings(hunterCount: 3, area: square);
      final back = GameSettings.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
    });

    test('validate', () {
      expect(
        const GameSettings(area: square).validate(memberCount: 7),
        isEmpty,
      );
      expect(
        const GameSettings().validate(),
        contains(SettingsError.areaMissing),
      );
      expect(
        const GameSettings(
          hunterCount: 7,
          area: square,
        ).validate(memberCount: 7),
        contains(SettingsError.notEnoughPlayers),
      );
      expect(
        const GameSettings(
          headStart: Duration(hours: 4),
          area: square,
        ).validate(),
        contains(SettingsError.headStartInvalid),
      );
    });
  });

  test('Member json roundtrip', () {
    const m = Member(id: 'x', name: 'Xa', role: Role.player, caught: true);
    final back = Member.fromJson(m.toJson());
    expect(back.toJson(), m.toJson());
  });

  test('isInsidePolygon', () {
    expect(isInsidePolygon(const GeoPoint(52.05, 13.05), square), isTrue);
    expect(isInsidePolygon(const GeoPoint(52.2, 13.05), square), isFalse);
    expect(
      isInsidePolygon(const GeoPoint(52.05, 13.05), square.take(2).toList()),
      isFalse,
    );
  });
}
