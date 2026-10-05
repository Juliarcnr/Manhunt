import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/teams/team_assignment.dart';

void main() {
  final members = [
    for (var i = 0; i < 7; i++) Member(id: 'm$i', name: 'Name $i'),
  ];

  group('assignRandomRoles (R-LOBBY-04)', () {
    test('exactly hunterCount hunters, rest players', () {
      final result = assignRandomRoles(members, 3, random: Random(1));
      expect(result.where((m) => m.isHunter), hasLength(3));
      expect(result.where((m) => m.isPlayer), hasLength(4));
      expect(result.map((m) => m.id), members.map((m) => m.id));
    });

    test('is random', () {
      final hunterSets = {
        for (var seed = 0; seed < 20; seed++)
          assignRandomRoles(
            members,
            3,
            random: Random(seed),
          ).where((m) => m.isHunter).map((m) => m.id).join(','),
      };
      expect(hunterSets.length, greaterThan(1));
    });

    test('rejects invalid count', () {
      expect(() => assignRandomRoles(members, 8), throwsArgumentError);
    });
  });

  group('swap / toggle (R-LOBBY-05)', () {
    final assigned = [
      const Member(id: 'a', name: 'A', role: Role.hunter),
      const Member(id: 'b', name: 'B', role: Role.player),
      const Member(id: 'c', name: 'C', role: Role.player),
    ];

    test('swapRoles exchanges roles', () {
      final r = swapRoles(assigned, 'a', 'b');
      expect(r[0].role, Role.player);
      expect(r[1].role, Role.hunter);
      expect(r[2].role, Role.player);
    });

    test('toggleRole flips one member', () {
      expect(toggleRole(assigned, 'c')[2].role, Role.hunter);
      expect(toggleRole(assigned, 'a')[0].role, Role.player);
    });
  });
}
