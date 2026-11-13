import 'dart:math';

import '../models/member.dart';

/// Share of hunters when rolling the roles (R-LOBBY-04).
const hunterShare = 0.3;

/// How many of [count] people become hunters: 30 % (rounded), but at least
/// one hunter and at least one player (R-LOBBY-04).
int hunterCountFor(int count) {
  if (count < 2) throw ArgumentError.value(count, 'count');
  return (count * hunterShare).round().clamp(1, count - 1);
}

/// Rolls everybody in [members] anew – whatever their role, also game masters
/// and unassigned members – into hunters and players, 30/70 (R-LOBBY-04).
List<Member> assignRandomRoles(List<Member> members, {Random? random}) {
  final hunters = hunterCountFor(members.length);
  final shuffled = [...members]..shuffle(random ?? Random.secure());
  final hunterIds = {for (final m in shuffled.take(hunters)) m.id};
  return [
    for (final m in members)
      m.copyWith(role: hunterIds.contains(m.id) ? Role.hunter : Role.player),
  ];
}

/// Gives one member [role]: drag and drop, the role menu and the button back
/// to "unassigned" (R-LOBBY-05, R-LOBBY-12, R-GM-02).
List<Member> setRole(List<Member> members, String id, Role role) => [
  for (final m in members)
    if (m.id == id) m.copyWith(role: role) else m,
];
