import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/bots/bot_plan.dart';
import 'package:manhunt/core/bots/bot_walk.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';

/// Metres between two points (equirectangular, fine for a few hundred m).
double metres(GeoPoint a, GeoPoint b) {
  const r = 6371000.0;
  final x = (b.lng - a.lng) * pi / 180 * cos((a.lat + b.lat) / 2 * pi / 180);
  final y = (b.lat - a.lat) * pi / 180;
  return sqrt(x * x + y * y) * r;
}

void main() {
  group('computer members walk around the host (R-BOT-04)', () {
    const anchor = GeoPoint(52.52, 13.405);

    test('never more than 500 m away over a long walk', () {
      final random = Random(7);
      var walk = BotWalk.random(random);
      for (var i = 0; i < 10000; i++) {
        walk = walk.step(const Duration(seconds: 1), random);
        expect(walk.distanceM, lessThanOrEqualTo(botRadiusM + 1e-9));
        expect(metres(anchor, walk.at(anchor)), lessThan(botRadiusM + 0.5));
      }
    });

    test('actually moves, and pauses now and then', () {
      final random = Random(3);
      var walk = BotWalk.random(random);
      final points = <GeoPoint>{};
      var paused = 0;
      for (var i = 0; i < 600; i++) {
        walk = walk.step(const Duration(seconds: 1), random);
        points.add(walk.at(anchor));
        if (walk.pause > Duration.zero) paused++;
      }
      expect(points.length, greaterThan(100));
      expect(paused, greaterThan(0));
    });

    test('same seed, same walk', () {
      BotWalk run(int seed) {
        final random = Random(seed);
        var walk = BotWalk.random(random);
        for (var i = 0; i < 100; i++) {
          walk = walk.step(const Duration(seconds: 1), random);
        }
        return walk;
      }

      expect(run(1).eastM, run(1).eastM);
      expect(run(1).northM, isNot(run(2).northM));
    });

    test('follows the anchor', () {
      const walk = BotWalk(eastM: 10, northM: -5);
      const moved = GeoPoint(52.53, 13.41);
      expect(metres(moved, walk.at(moved)), closeTo(sqrt(125), 0.1));
    });

    test('radius is 500 m (R-BOT-04)', () {
      expect(botRadiusM, 500);
    });
  });

  group('bot names (R-BOT-03)', () {
    test('round trip', () {
      expect(botName(2), '🤖 Stromius');
      expect(isBot(Member(id: 'b', name: botName(1))), isTrue);
      expect(isBot(const Member(id: 'k', name: 'Kim')), isFalse);
      expect(isBot(const Member(id: 'b', name: '🤖 Hunter')), isFalse);
      // A human may be called that.
      expect(isBot(const Member(id: 's', name: 'Stromius')), isFalse);
    });

    test('enough distinct names', () {
      final names = {for (var n = 1; n <= maxBots; n++) botName(n)};
      expect(names, hasLength(maxBots));
    });
  });

  group('the host runs all bots; they join unassigned and keep any role '
      '(R-BOT-02, R-BOT-03)', () {
    const host = Member(id: 'h', name: 'Alex', role: Role.gameMaster);
    const kim = Member(id: 'k', name: 'Kim', role: Role.player);
    const settings = GameSettings(botCount: 3);
    Member bot(String id, int n, {Role role = Role.unassigned}) =>
        Member(id: id, name: botName(n), role: role);

    BotActions plan(
      List<Member> members, {
      bool isHost = true,
      GameSettings s = settings,
      Set<String> mine = const {},
    }) => botActions(
      settings: s,
      members: members,
      myBotIds: mine,
      isHost: isHost,
    );

    test('the host creates the missing bots, numbered uniquely – whatever '
        'the roles of the people', () {
      expect(plan([host, kim]).create, [
        '🤖 Adelgunde',
        '🤖 Stromius',
        '🤖 Pankratius',
      ]);
      final members = [host, kim, bot('b1', 1)];
      expect(plan(members, mine: {'b1'}).create, [
        '🤖 Stromius',
        '🤖 Pankratius',
      ]);
      expect(plan(members, isHost: false).isEmpty, isTrue);
    });

    test('fewer wanted → the host removes its newest bots', () {
      final members = [host, bot('b1', 1), bot('b2', 2), bot('b3', 3)];
      final actions = plan(
        members,
        s: const GameSettings(botCount: 1),
        mine: {'b1', 'b2', 'b3'},
      );
      expect(actions.remove, ['b2', 'b3']);
      expect(actions.create, isEmpty);
    });

    test('roles never matter: assigned bots stay as they are', () {
      final members = [
        host,
        kim,
        bot('b1', 1, role: Role.hunter),
        bot('b2', 2, role: Role.player),
        bot('b3', 3),
      ];
      expect(plan(members, mine: {'b1', 'b2', 'b3'}).isEmpty, isTrue);
    });

    test('a phone other than the host removes its bots (older versions)', () {
      final members = [host, kim, bot('b1', 1, role: Role.player)];
      expect(plan(members, isHost: false, mine: {'b1'}).remove, ['b1']);
    });

    test('bots from both old name lists count as bots', () {
      for (final name in ['🤖 Knorbert', '🤖 Ottokar', '🤖 Radegundis']) {
        expect(
          isBot(Member(id: 'x', name: name)),
          isTrue,
          reason: name,
        );
      }
    });
  });
}
