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
  group('computer members walk around their carrier (R-BOT-04)', () {
    const anchor = GeoPoint(52.52, 13.405);

    test('never more than 200 m away over a long walk', () {
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
  });

  group('bot names carry the kind (R-BOT-03)', () {
    test('round trip', () {
      expect(botName(BotKind.hunter, 2), '🤖 Knorbert');
      expect(botKindOf(botName(BotKind.hunter, 2)), BotKind.hunter);
      expect(botKindOf(botName(BotKind.player, 8)), BotKind.player);
      expect(botKindOf('Kim'), isNull);
      expect(botKindOf('🤖 Hunter'), isNull);
      expect(botKindOf('Stromius'), isNull); // a human may be called that
      expect(isBot(Member(id: 'b', name: botName(BotKind.player, 1))), isTrue);
    });

    test('enough distinct names for each kind', () {
      final names = {
        for (final kind in BotKind.values)
          for (var n = 1; n <= maxBotsPerKind; n++) botName(kind, n),
      };
      expect(names, hasLength(2 * maxBotsPerKind));
      for (final kind in BotKind.values) {
        for (var n = 1; n <= maxBotsPerKind; n++) {
          expect(botKindOf(botName(kind, n)), kind);
        }
      }
    });
  });

  group('which phone runs which bot (R-BOT-02, R-BOT-03)', () {
    const host = Member(id: 'h', name: 'Alex', role: Role.hunter);
    const kim = Member(id: 'k', name: 'Kim', role: Role.player);
    const sam = Member(id: 's', name: 'Sam', role: Role.player);
    const settings = GameSettings(botHunters: 1, botPlayers: 2);
    Member bot(String id, BotKind kind, int n, {Role? role}) =>
        Member(id: id, name: botName(kind, n), role: role ?? kind.role);

    BotActions plan(
      List<Member> members,
      String me, {
      GameSettings s = settings,
      Set<String> mine = const {},
    }) => botActions(
      settings: s,
      members: members,
      myId: me,
      myBotIds: mine,
      isHost: me == 'h',
    );

    test('the first human of a role carries its bots', () {
      final members = [host, kim, sam];
      expect(botCarrier(BotKind.hunter, members), 'h');
      expect(botCarrier(BotKind.player, members), 'k');
      expect(
        botCarrier(BotKind.player, [host, bot('b', BotKind.player, 1), kim]),
        'k',
      );
    });

    test('without a human of that role, the first human carries them', () {
      // A single phone carries all bots, whatever its role.
      expect(botCarrier(BotKind.player, [host]), 'h');
      expect(botCarrier(BotKind.hunter, [kim]), 'k');
      const unassigned = Member(id: 'u', name: 'Uli');
      expect(botCarrier(BotKind.hunter, [unassigned, kim]), 'u');
      expect(botCarrier(BotKind.hunter, [bot('b', BotKind.hunter, 1)]), isNull);
    });

    test('carriers create the missing bots, numbered uniquely', () {
      expect(plan([host, kim, sam], 'h').create, [
        (kind: BotKind.hunter, name: '🤖 Stromius'),
      ]);
      final members = [host, kim, sam, bot('b1', BotKind.player, 1)];
      expect(plan(members, 'k', mine: {'b1'}).create, [
        (kind: BotKind.player, name: '🤖 Pankratius'),
      ]);
      expect(plan(members, 's').isEmpty, isTrue);
    });

    test('fewer wanted → the carrier removes its extra bots', () {
      final members = [
        host,
        kim,
        bot('b1', BotKind.player, 1),
        bot('b2', BotKind.player, 2),
      ];
      final actions = plan(
        members,
        'k',
        s: const GameSettings(botPlayers: 1),
        mine: {'b1', 'b2'},
      );
      expect(actions.remove, ['b2']);
      expect(actions.create, isEmpty);
    });

    test('a phone that no longer carries removes its bots', () {
      // Kim became a hunter: Sam carries the player bots now.
      final members = [
        host,
        kim.copyWith(role: Role.hunter),
        sam,
        bot('b1', BotKind.player, 1),
      ];
      expect(plan(members, 'k', mine: {'b1'}).remove, ['b1']);
      expect(plan(members, 's').create, [
        (kind: BotKind.player, name: '🤖 Pankratius'),
        (kind: BotKind.player, name: '🤖 Notburga'),
      ]);
    });

    test('no roles yet → the first phone adds all bots right away', () {
      const nobody = [
        Member(id: 'h', name: 'Alex'),
        Member(id: 'k', name: 'Kim'),
      ];
      expect(plan(nobody, 'h').create, [
        (kind: BotKind.hunter, name: '🤖 Stromius'),
        (kind: BotKind.player, name: '🤖 Adelgunde'),
        (kind: BotKind.player, name: '🤖 Pankratius'),
      ]);
      expect(plan(nobody, 'k').isEmpty, isTrue);
    });

    test('the host gives every bot the role of its kind', () {
      final members = [
        host,
        kim,
        bot('b1', BotKind.player, 1, role: Role.unassigned),
        bot('b2', BotKind.hunter, 1, role: Role.player),
        bot('b3', BotKind.player, 2),
      ];
      final assigned = plan(members, 'h', mine: {'b2'}).assign;
      expect(
        {for (final m in assigned) m.id: m.role},
        {'b1': Role.player, 'b2': Role.hunter},
      );
      expect(plan(members, 'k').assign, isEmpty);
    });
  });
}
