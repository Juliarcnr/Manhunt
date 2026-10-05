enum Role { unassigned, hunter, player }

/// A participant of a group. [id] is the anonymous device/auth id.
class Member {
  const Member({
    required this.id,
    required this.name,
    this.role = Role.unassigned,
    this.caught = false,
    this.jokerUsed = false,
    this.playerJokerUsed = false,
  });

  final String id;
  final String name;
  final Role role;
  final bool caught;

  /// Joker "hunter positions" used this round (R-PLAY-02).
  final bool jokerUsed;

  /// Joker "player positions" used this round (R-PLAY-03).
  final bool playerJokerUsed;

  bool get isHunter => role == Role.hunter;
  bool get isPlayer => role == Role.player;

  Member copyWith({
    String? name,
    Role? role,
    bool? caught,
    bool? jokerUsed,
    bool? playerJokerUsed,
  }) => Member(
    id: id,
    name: name ?? this.name,
    role: role ?? this.role,
    caught: caught ?? this.caught,
    jokerUsed: jokerUsed ?? this.jokerUsed,
    playerJokerUsed: playerJokerUsed ?? this.playerJokerUsed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'role': role.name,
    'caught': caught,
    'jokerUsed': jokerUsed,
    'playerJokerUsed': playerJokerUsed,
  };

  factory Member.fromJson(Map<String, Object?> json) => Member(
    id: json['id']! as String,
    name: json['name']! as String,
    role: Role.values.byName(json['role']! as String),
    caught: json['caught'] as bool? ?? false,
    jokerUsed: json['jokerUsed'] as bool? ?? false,
    playerJokerUsed: json['playerJokerUsed'] as bool? ?? false,
  );
}
