import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/core/schedule/game_clock.dart';
import 'package:manhunt/core/schedule/speedhunt.dart';

void main() {
  final start = DateTime.utc(2026, 10, 4, 14);
  // No minimum start time here; R-SET-11 is tested separately below.
  const settings = GameSettings(speedhuntEarliest: Duration.zero);
  final clock = GameClock(startAt: start, settings: settings);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));

  const player = Member(id: 'p', name: 'Pia', role: Role.player);

  group('Speedhunt (R-SPEED-03)', () {
    final sh = Speedhunt.fromSettings(
      targetId: 'p',
      startedAt: at(30),
      settings: settings,
    );

    test('3 pings every 5 min, first immediately', () {
      expect(sh.pingTimes(), [at(30), at(35), at(40)]);
    });

    test('active until last ping', () {
      expect(sh.isActiveAt(at(29)), isFalse);
      expect(sh.isActiveAt(at(30)), isTrue);
      expect(sh.isActiveAt(at(40)), isTrue);
      expect(sh.isActiveAt(at(41)), isFalse);
    });

    test('json roundtrip', () {
      final back = Speedhunt.fromJson(sh.toJson());
      expect(back.pingTimes(), sh.pingTimes());
      expect(back.targetId, 'p');
    });
  });

  group('canStartSpeedhunt (R-SPEED-01, R-SPEED-02)', () {
    SpeedhuntDenial? check(
      DateTime now,
      List<Speedhunt> prev, [
      Member target = player,
    ]) => canStartSpeedhunt(
      clock: clock,
      now: now,
      previous: prev,
      target: target,
    );

    test('allowed while hunting', () {
      expect(check(at(30), []), isNull);
    });
    test('not during head start or after end', () {
      expect(check(at(5), []), SpeedhuntDenial.notHunting);
      expect(check(at(200), []), SpeedhuntDenial.notHunting);
    });
    test('limited count', () {
      final used = [
        Speedhunt.fromSettings(
          targetId: 'p',
          startedAt: at(20),
          settings: settings,
        ),
        Speedhunt.fromSettings(
          targetId: 'p',
          startedAt: at(60),
          settings: settings,
        ),
      ];
      expect(check(at(100), used), SpeedhuntDenial.noneLeft);
    });
    test('only one at a time', () {
      final running = [
        Speedhunt.fromSettings(
          targetId: 'p',
          startedAt: at(30),
          settings: settings,
        ),
      ];
      expect(check(at(32), running), SpeedhuntDenial.alreadyRunning);
    });
    test('target must be an uncaught player', () {
      expect(
        check(at(30), [], player.copyWith(caught: true)),
        SpeedhuntDenial.invalidTarget,
      );
      expect(
        check(at(30), [], player.copyWith(role: Role.hunter)),
        SpeedhuntDenial.invalidTarget,
      );
    });
  });

  group('first speedhunt not before the configured time (R-SET-11)', () {
    final defaultClock = GameClock(
      startAt: start,
      settings: const GameSettings(), // 60 min
    );
    SpeedhuntDenial? checkAt(int minute) => canStartSpeedhunt(
      clock: defaultClock,
      now: at(minute),
      previous: const [],
      target: player,
    );

    test('default is 60 minutes', () {
      expect(const GameSettings().speedhuntEarliest, const Duration(hours: 1));
    });

    test('too early before, allowed from minute 60', () {
      expect(checkAt(30), SpeedhuntDenial.tooEarly);
      expect(checkAt(59), SpeedhuntDenial.tooEarly);
      expect(checkAt(60), isNull);
    });

    test('head start still wins over "too early"', () {
      expect(checkAt(5), SpeedhuntDenial.notHunting);
    });
  });

  group('delay until the first speedhunt ping (R-SET-13)', () {
    final delayed = Speedhunt.fromSettings(
      targetId: 'p',
      startedAt: at(30),
      settings: const GameSettings(speedhuntFirstDelay: Duration(minutes: 2)),
    );

    test('default is no delay', () {
      expect(const GameSettings().speedhuntFirstDelay, Duration.zero);
    });

    test('pings shift by the delay, the speedhunt counts from the trigger', () {
      expect(delayed.pingTimes(), [at(32), at(37), at(42)]);
      expect(delayed.endsAt, at(42));
      expect(delayed.isActiveAt(at(30)), isTrue); // banner from the start
      expect(delayed.isActiveAt(at(42)), isTrue);
      expect(delayed.isActiveAt(at(43)), isFalse);
    });

    test('stored with the speedhunt; older ones without it = no delay', () {
      expect(Speedhunt.fromJson(delayed.toJson()).pingTimes(), [
        at(32),
        at(37),
        at(42),
      ]);
      final legacy = delayed.toJson()..remove('firstDelaySec');
      expect(Speedhunt.fromJson(legacy).pingTimes().first, at(30));
    });

    test('settings json roundtrip', () {
      const s = GameSettings(speedhuntFirstDelay: Duration(minutes: 4));
      expect(
        GameSettings.fromJson(s.toJson()).speedhuntFirstDelay,
        const Duration(minutes: 4),
      );
      final legacy = s.toJson()..remove('speedhuntFirstDelaySec');
      expect(GameSettings.fromJson(legacy).speedhuntFirstDelay, Duration.zero);
    });
  });

  test('players get a speedhunt chip with its first ping (R-SPEED-09)', () {
    Speedhunt sh(int minute, {int delay = 0}) => Speedhunt(
      targetId: '',
      startedAt: at(minute),
      pings: 3,
      interval: const Duration(minutes: 5),
      firstDelay: Duration(minutes: delay),
    );
    final later = sh(90);
    final delayed = sh(60, delay: 2);
    expect(speedhuntsWithFirstPing([later, delayed], at(61)), isEmpty);
    expect(speedhuntsWithFirstPing([later, delayed], at(62)), [delayed]);
    // Oldest first.
    expect(speedhuntsWithFirstPing([later, delayed], at(90)), [delayed, later]);
  });

  group('catching the target ends the speedhunt (R-SPEED-10)', () {
    final sh = Speedhunt.fromSettings(
      targetId: 'p',
      startedAt: at(30),
      settings: settings,
    );

    test('no pings from the catch on, inactive right away', () {
      final ended = sh.endAt(at(37));
      expect(ended.pingTimes(), [at(30), at(35)]);
      expect(ended.endsAt, at(37));
      expect(ended.isActiveAt(at(36)), isTrue);
      expect(ended.isActiveAt(at(37)), isFalse);
    });

    test('a catch at a ping time drops that ping', () {
      expect(sh.endAt(at(35)).pingTimes(), [at(30)]);
    });

    test('a catch after the end changes nothing', () {
      final ended = sh.endAt(at(50));
      expect(ended.pingTimes(), sh.pingTimes());
      expect(ended.endsAt, at(40));
    });

    test('caught before the first ping: no chip for players', () {
      final delayed = Speedhunt(
        targetId: '',
        startedAt: at(30),
        pings: 3,
        interval: const Duration(minutes: 5),
        firstDelay: const Duration(minutes: 2),
      ).endAt(at(31));
      expect(delayed.pingTimes(), isEmpty);
      expect(speedhuntsWithFirstPing([delayed], at(45)), isEmpty);
    });

    test('only the running speedhunt on the caught player is ended', () {
      expect(speedhuntEndedByCatch([sh], at(33)), sh.startedAt);
      expect(speedhuntEndedByCatch([sh], at(41)), isNull);
      expect(speedhuntEndedByCatch([], at(33)), isNull);
    });

    test('catches mark the speedhunt they end; others stay', () {
      final other = Speedhunt.fromSettings(
        targetId: '',
        startedAt: at(60),
        settings: settings,
      );
      final result = applyCatches(
        [sh, other],
        [
          CatchRecord(playerId: 'x', at: at(32)),
          CatchRecord(playerId: 'p', at: at(37), endsSpeedhunt: at(30)),
        ],
      );
      expect(result[0].endedAt, at(37));
      expect(result[1].endedAt, isNull);
      expect(activeSpeedhunt(result, at(38)), isNull);
    });

    test('stored in the catch; older catches without it end nothing', () {
      final c = CatchRecord(playerId: 'p', at: at(37), endsSpeedhunt: at(30));
      expect(CatchRecord.fromJson(c.toJson()).endsSpeedhunt, at(30));
      expect(
        CatchRecord.fromJson(CatchRecord(playerId: 'p', at: at(37)).toJson())
            .endsSpeedhunt,
        isNull,
      );
    });
  });
}
