import 'dart:math';

import '../models/member.dart';

/// Randomly assigns exactly [hunterCount] hunters, everyone else becomes a player (R-LOBBY-04).
/// Game masters keep their role and do not count (R-GM-02).
List<Member> assignRandomRoles(
  List<Member> members,
  int hunterCount, {
  Random? random,
}) {
  final playing = members.where((m) => !m.isGameMaster).toList();
  if (hunterCount < 0 || hunterCount > playing.length) {
    throw ArgumentError.value(hunterCount, 'hunterCount');
  }
  final shuffled = playing..shuffle(random ?? Random.secure());
  final hunterIds = {for (final m in shuffled.take(hunterCount)) m.id};
  return [
    for (final m in members)
      if (m.isGameMaster)
        m
      else
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

/// Flips a single member between hunter and player; a game master becomes a
/// player again (R-GM-02).
List<Member> toggleRole(List<Member> members, String id) => [
  for (final m in members)
    if (m.id == id)
      m.copyWith(
        role: switch (m.role) {
          Role.hunter || Role.gameMaster => Role.player,
          Role.player || Role.unassigned => Role.hunter,
        },
      )
    else
      m,
];

/// Gives one member [role], e.g. makes them game master (R-GM-02).
List<Member> setRole(List<Member> members, String id, Role role) => [
  for (final m in members)
    if (m.id == id) m.copyWith(role: role) else m,
];
