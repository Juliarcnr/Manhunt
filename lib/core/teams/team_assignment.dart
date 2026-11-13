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

/// The members of [after] whose role differs from [before] – only these are
/// written, so someone who just left cannot fail the whole batch.
List<Member> changedRoles(List<Member> before, List<Member> after) {
  final old = {for (final m in before) m.id: m.role};
  return [
    for (final m in after)
      if (old[m.id] != m.role) m,
  ];
}

/// Gives one member [role]: drag and drop and the role menu (R-LOBBY-05,
/// R-GM-02).
List<Member> setRole(List<Member> members, String id, Role role) => [
  for (final m in members)
    if (m.id == id) m.copyWith(role: role) else m,
];
