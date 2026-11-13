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

    test('one hunter joker by default, 0 … 5 can be set (R-SET-09)', () {
      expect(const GameSettings().hunterJokers, 1);
      expect(const GameSettings().jokerEnabled, isTrue);
      const off = GameSettings(hunterJokers: 0);
      expect(off.jokerEnabled, isFalse);
      expect(GameSettings.fromJson(off.toJson()).hunterJokers, 0);
      const three = GameSettings(hunterJokers: 3);
      expect(GameSettings.fromJson(three.toJson()).hunterJokers, 3);
      // Older app versions still read the switch.
      expect(three.toJson()['jokerEnabled'], isTrue);
      expect(off.toJson()['jokerEnabled'], isFalse);
      // Saved before the number existed: switch on = 1, off = 0, none = 1.
      final legacyOn = three.toJson()..remove('hunterJokers');
      expect(GameSettings.fromJson(legacyOn).hunterJokers, 1);
      final legacyOff = off.toJson()..remove('hunterJokers');
      expect(GameSettings.fromJson(legacyOff).hunterJokers, 0);
      final oldest = legacyOn..remove('jokerEnabled');
      expect(GameSettings.fromJson(oldest).hunterJokers, 1);
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

    test('regular pings to all players replace the player joker '
        '(R-SET-15)', () {
      const s = GameSettings();
      expect(s.sharedPings, isFalse);
      expect(s.playerJokerAvailable, isTrue);
      const shared = GameSettings(sharedPings: true);
      expect(shared.playerJokerAvailable, isFalse);
      expect(GameSettings.fromJson(shared.toJson()).sharedPings, isTrue);
      final legacy = s.toJson()..remove('sharedPings');
      expect(GameSettings.fromJson(legacy).sharedPings, isFalse);
    });

    test('computer members: none by default, also for older groups '
        '(R-BOT-02)', () {
      const s = GameSettings();
      expect(s.botCount, 0);
      final back = GameSettings.fromJson(
        const GameSettings(botCount: 5).toJson(),
      );
      expect(back.botCount, 5);
      final none = s.toJson()..remove('botCount');
      expect(GameSettings.fromJson(none).botCount, 0);
      // Older groups had hunters and players separately.
      final legacy = {...none, 'botHunters': 1, 'botPlayers': 2};
      expect(GameSettings.fromJson(legacy).botCount, 3);
    });

    test('countdown is not skipped by default, also for older groups '
        '(R-BOT-09)', () {
      const s = GameSettings();
      expect(s.skipCountdown, isFalse);
      expect(
        GameSettings.fromJson(const GameSettings(skipCountdown: true).toJson())
            .skipCountdown,
        isTrue,
      );
      final legacy = s.toJson()..remove('skipCountdown');
      expect(GameSettings.fromJson(legacy).skipCountdown, isFalse);
    });

    test('anonymous players are on by default, also for older groups '
        '(R-SET-16)', () {
      const s = GameSettings();
      expect(s.anonymousPlayers, isTrue);
      const named = GameSettings(anonymousPlayers: false);
      expect(GameSettings.fromJson(named.toJson()).anonymousPlayers, isFalse);
      final legacy = s.toJson()..remove('anonymousPlayers');
      expect(GameSettings.fromJson(legacy).anonymousPlayers, isTrue);
    });

    test('live location outside the area is on by default, also for older '
        'groups (R-SET-17)', () {
      const s = GameSettings();
      expect(s.outsideLiveLocation, isTrue);
      const off = GameSettings(outsideLiveLocation: false);
      expect(GameSettings.fromJson(off.toJson()).outsideLiveLocation, isFalse);
      expect(off.copyWith(sharedPings: true).outsideLiveLocation, isFalse);
      final legacy = s.toJson()..remove('outsideLiveLocation');
      expect(GameSettings.fromJson(legacy).outsideLiveLocation, isTrue);
    });

    test('speedhunt pauses: 30 min each with repeats, also for older groups; '
        'the per-player pause is never shorter (R-SET-18, R-SET-19)', () {
      const custom = GameSettings(
        speedhuntCooldown: Duration(minutes: 45),
        speedhuntRepeatTarget: false,
        speedhuntRepeatCooldown: Duration(minutes: 50),
      );
      final back = GameSettings.fromJson(custom.toJson());
      expect(back.speedhuntCooldown, const Duration(minutes: 45));
      expect(back.speedhuntRepeatTarget, isFalse);
      expect(back.speedhuntRepeatCooldown, const Duration(minutes: 50));
      expect(custom.copyWith(sharedPings: true).speedhuntRepeatTarget, isFalse);

      final legacy = const GameSettings().toJson()
        ..remove('speedhuntCooldownSec')
        ..remove('speedhuntRepeatTarget')
        ..remove('speedhuntRepeatCooldownSec');
      final old = GameSettings.fromJson(legacy);
      expect(old.speedhuntCooldown, const Duration(minutes: 30));
      expect(old.speedhuntRepeatTarget, isTrue);
      expect(old.speedhuntRepeatCooldown, const Duration(minutes: 30));

      const shorter = GameSettings(
        area: square,
        speedhuntRepeatCooldown: Duration(minutes: 20),
      );
      expect(
        shorter.validate(),
        contains(SettingsError.speedhuntRepeatCooldownTooShort),
      );
      // Without repeats the per-player pause does not matter.
      expect(
        shorter.copyWith(speedhuntRepeatTarget: false).validate(),
        isEmpty,
      );
    });

    test('start time: none by default, also for older groups; can be '
        'set and removed (R-SET-21)', () {
      const s = GameSettings();
      expect(s.startTime, isNull);
      final at14 = s.copyWith(startTime: const Duration(hours: 14));
      expect(
        GameSettings.fromJson(at14.toJson()).startTime,
        const Duration(hours: 14),
      );
      expect(at14.copyWith(sharedPings: true).startTime, isNotNull);
      expect(at14.copyWith(startTime: null).startTime, isNull);
      final legacy = s.toJson()..remove('startTimeMin');
      expect(GameSettings.fromJson(legacy).startTime, isNull);
    });

    test('json roundtrip', () {
      const s = GameSettings(speedhuntCount: 3, area: square);
      final back = GameSettings.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
    });

    test('no hunter count any more; older app versions still find one '
        '(R-SET-07, R-LOBBY-04)', () {
      final json = const GameSettings().toJson();
      expect(json['hunterCount'], 1);
      final fromOld = {...json, 'hunterCount': 3};
      expect(GameSettings.fromJson(fromOld).toJson()['hunterCount'], 1);
      expect(
        GameSettings.fromJson(json..remove('hunterCount')).duration,
        const GameSettings().duration,
      );
    });

    test('validate', () {
      expect(const GameSettings(area: square).validate(), isEmpty);
      expect(
        const GameSettings().validate(),
        contains(SettingsError.areaMissing),
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
    const m = Member(
      id: 'x',
      name: 'Xa',
      role: Role.player,
      caught: true,
      jokersUsed: 2,
    );
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
