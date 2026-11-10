import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/round/read_budget.dart';

void main() {
  List<Member> team({
    required int hunters,
    required int players,
    int gameMasters = 0,
  }) => [
    for (var i = 0; i < hunters; i++)
      Member(id: 'h$i', name: 'H$i', role: Role.hunter),
    for (var i = 0; i < players; i++)
      Member(id: 'p$i', name: 'P$i', role: Role.player),
    for (var i = 0; i < gameMasters; i++)
      Member(id: 'g$i', name: 'G$i', role: Role.gameMaster),
  ];
  const threeHours = GameSettings();

  group('estimated reads of a round (R-QUOTA-01)', () {
    test('3 h, 3 hunters, 6 players, 1 game master', () {
      final members = team(hunters: 3, players: 6, gameMasters: 1);
      // Hunters: 3 × 2160 × 3; watchers 1 + 3: 4 × 9 × 720; pings
      // 6 × 9 × (3 + 4).
      expect(
        estimateRoundReads(
          settings: threeHours,
          members: members,
          hunterInterval: hunterLiveNormal,
          watcherInterval: watcherLiveNormal,
        ),
        19440 + 25920 + 378,
      );
      // Throttled: hunters 3 × 720 × 3; watchers 4 × 9 × 360.
      expect(
        estimateRoundReads(
          settings: threeHours,
          members: members,
          hunterInterval: hunterLiveThrottled,
          watcherInterval: watcherLiveThrottled,
        ),
        6480 + 12960 + 378,
      );
    });

    test('a game master counts as a watcher', () {
      int reads(int gm) => estimateRoundReads(
        settings: threeHours,
        members: team(hunters: 2, players: 4, gameMasters: gm),
        hunterInterval: hunterLiveNormal,
        watcherInterval: watcherLiveNormal,
      );
      expect(reads(1), greaterThan(reads(0)));
    });

    test('shared pings are read by all players', () {
      int reads(bool shared) => estimateRoundReads(
        settings: threeHours.copyWith(sharedPings: shared),
        members: team(hunters: 2, players: 4),
        hunterInterval: hunterLiveNormal,
        watcherInterval: watcherLiveNormal,
      );
      expect(reads(true) - reads(false), 4 * 9 * 4);
    });
  });

  group('live positions are throttled from 80 % of the daily reads '
      '(R-QUOTA-01)', () {
    test('a small group stays at 5 s and 15 s', () {
      final members = team(hunters: 2, players: 4);
      expect(liveThrottledFor(threeHours, members), isFalse);
      expect(hunterLiveIntervalFor(threeHours, members), hunterLiveNormal);
    });

    test('a big group gets 15 s for hunters and 30 s for watchers', () {
      final members = team(hunters: 3, players: 6, gameMasters: 1);
      expect(liveThrottledFor(threeHours, members), isTrue);
      expect(hunterLiveIntervalFor(threeHours, members), hunterLiveThrottled);
      // (6480 + 12960 + 378) / 50000.
      expect(estimatedQuotaShare(threeHours, members), closeTo(0.396, 0.001));
    });

    test('4 hunters, 8 players: watchers throttled too, about 59 %', () {
      final members = team(hunters: 4, players: 8);
      // Hunters 4 × 720 × 4; watchers 4 × 12 × 360; pings 8 × 9 × 8.
      expect(
        estimatedQuotaShare(threeHours, members),
        (11520 + 17280 + 576) / dailyReadQuota,
      );
    });

    test('the limit is exactly 80 %', () {
      // 5 hunters, nobody else: 5 × (D / 5 s) × 5 = 5 × D reads.
      final members = team(hunters: 5, players: 0);
      final atLimit = threeHours.copyWith(
        duration: const Duration(seconds: 8000),
      );
      final below = threeHours.copyWith(
        duration: const Duration(seconds: 7995),
      );
      expect(liveThrottledFor(atLimit, members), isTrue);
      expect(hunterLiveIntervalFor(atLimit, members), hunterLiveThrottled);
      expect(liveThrottledFor(below, members), isFalse);
      expect(hunterLiveIntervalFor(below, members), hunterLiveNormal);
    });

    test('a longer round is throttled sooner', () {
      final members = team(hunters: 3, players: 4);
      expect(hunterLiveIntervalFor(threeHours, members), hunterLiveNormal);
      expect(
        hunterLiveIntervalFor(
          threeHours.copyWith(duration: const Duration(hours: 5)),
          members,
        ),
        hunterLiveThrottled,
      );
    });
  });

  group('watchers see everyone every 15 s, 30 s when throttled '
      '(R-GM-05, R-QUOTA-01)', () {
    test('derived from the round hunter interval', () {
      expect(watcherLiveIntervalFor(hunterLiveNormal), watcherLiveNormal);
      expect(watcherLiveIntervalFor(hunterLiveThrottled), watcherLiveThrottled);
      expect(watcherLiveNormal, const Duration(seconds: 15));
      expect(watcherLiveThrottled, const Duration(seconds: 30));
    });
  });
}
