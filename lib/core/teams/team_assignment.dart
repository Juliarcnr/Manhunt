import 'dart:math';

import '../models/member.dart';

/// Randomly assigns exactly [hunterCount] hunters, everyone else becomes a player (R-LOBBY-04).
List<Member> assignRandomRoles(
  List<Member> members,
  int hunterCount, {
  Random? random,
}) {
  if (hunterCount < 0 || hunterCount > members.length) {
    throw ArgumentError.value(hunterCount, 'hunterCount');
  }
  final shuffled = [...members]..shuffle(random ?? Random.secure());
  final hunterIds = {for (final m in shuffled.take(hunterCount)) m.id};
  return [
    for (final m in members)
      m.copyWith(role: hunterIds.contains(m.id) ? Role.hunter : Role.player),
  ];
}

/// Swaps the roles of two members (R-LOBBY-05).
List<Member> swapRoles(List<Member> members, String idA, String idB) {
  final a = members.firstWhere((m) => m.id == idA);
  final b = members.firstWhere((m) => m.id == idB);
  return [
    for (final m in members)
      if (m.id == idA)
        m.copyWith(role: b.role)
      else if (m.id == idB)
        m.copyWith(role: a.role)
      else
        m,
  ];
}

/// Flips a single member between hunter and player.
List<Member> toggleRole(List<Member> members, String id) => [
  for (final m in members)
    if (m.id == id)
      m.copyWith(role: m.role == Role.hunter ? Role.player : Role.hunter)
    else
      m,
];
