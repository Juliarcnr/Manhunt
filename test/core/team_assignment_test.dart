import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/teams/team_assignment.dart';

void main() {
  List<Member> people(int n) => [
    for (var i = 0; i < n; i++) Member(id: 'm$i', name: 'Name $i'),
  ];

  group('hunterCountFor: 30 % hunters, 70 % players (R-LOBBY-04)', () {
    test('rounded, at least one hunter and one player', () {
      expect(
        {for (var n = 2; n <= 12; n++) n: hunterCountFor(n)},
        {2: 1, 3: 1, 4: 1, 5: 2, 6: 2, 7: 2, 8: 2, 9: 3, 10: 3, 11: 3, 12: 4},
      );
    });

    test('needs at least two people', () {
      expect(() => hunterCountFor(1), throwsArgumentError);
    });
  });

  group('assignRandomRoles (R-LOBBY-04)', () {
    test('30/70 split, order kept', () {
      final members = people(10);
      final result = assignRandomRoles(members, random: Random(1));
      expect(result.where((m) => m.isHunter), hasLength(3));
      expect(result.where((m) => m.isPlayer), hasLength(7));
      expect(result.map((m) => m.id), members.map((m) => m.id));
    });

    test('is random', () {
      final hunterSets = {
        for (var seed = 0; seed < 20; seed++)
          assignRandomRoles(
            people(7),
            random: Random(seed),
          ).where((m) => m.isHunter).map((m) => m.id).join(','),
      };
      expect(hunterSets.length, greaterThan(1));
    });

    test('rolls everybody anew, whatever their role – also game masters '
        'and unassigned members (R-LOBBY-04, R-GM-02)', () {
      final mixed = [
        const Member(id: 'u', name: 'U'),
        const Member(id: 'g', name: 'G', role: Role.gameMaster),
        const Member(id: 'h', name: 'H', role: Role.hunter),
        const Member(id: 'p', name: 'P', role: Role.player),
        const Member(id: 'q', name: 'Q', role: Role.player),
      ];
      for (var seed = 0; seed < 20; seed++) {
        final r = assignRandomRoles(mixed, random: Random(seed));
        expect(r.where((m) => m.isHunter), hasLength(2));
        expect(r.where((m) => m.isPlayer), hasLength(3));
      }
    });

    test('rejects fewer than two people', () {
      expect(() => assignRandomRoles(people(1)), throwsArgumentError);
    });
  });

  group('setRole (R-LOBBY-05, R-LOBBY-12, R-GM-02)', () {
    test('moves one member to any of the four roles', () {
      final members = people(3);
      for (final role in Role.values) {
        final r = setRole(members, 'm1', role);
        expect(r[1].role, role);
        expect(r[0].role, Role.unassigned);
        expect(r[2].role, Role.unassigned);
      }
    });

    test('changedRoles keeps only the members whose role differs, so a '
        'stale member cannot fail the whole write', () {
      final before = people(3);
      final after = setRole(before, 'm1', Role.hunter);
      expect(changedRoles(before, after).map((m) => m.id), ['m1']);
      expect(changedRoles(before, before), isEmpty);
    });

    test('back to unassigned', () {
      const hunter = Member(id: 'h', name: 'H', role: Role.hunter);
      expect(
        setRole([hunter], 'h', Role.unassigned).single.role,
        Role.unassigned,
      );
    });
  });
}
