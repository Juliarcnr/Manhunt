/// [gameMaster] (R-GM-01): plays no part, watches everyone live; never
/// shuffled (R-GM-02).
enum Role { unassigned, hunter, player, gameMaster }

/// A participant of a group. [id] is the anonymous device/auth id.
class Member {
  const Member({
    required this.id,
    required this.name,
    this.role = Role.unassigned,
    this.caught = false,
    this.jokersUsed = 0,
    this.playerJokerUsed = false,
  });

  final String id;
  final String name;
  final Role role;
  final bool caught;

  /// How often the joker "hunter positions" was used this round
  /// (R-PLAY-02, R-SET-09).
  final int jokersUsed;

  /// Joker "player positions" used this round (R-PLAY-03).
  final bool playerJokerUsed;

  bool get isHunter => role == Role.hunter;
  bool get isPlayer => role == Role.player;
  bool get isGameMaster => role == Role.gameMaster;

  Member copyWith({
    String? name,
    Role? role,
    bool? caught,
    int? jokersUsed,
    bool? playerJokerUsed,
  }) => Member(
    id: id,
    name: name ?? this.name,
    role: role ?? this.role,
    caught: caught ?? this.caught,
    jokersUsed: jokersUsed ?? this.jokersUsed,
    playerJokerUsed: playerJokerUsed ?? this.playerJokerUsed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'role': role.name,
    'caught': caught,
    'jokersUsed': jokersUsed,
    'playerJokerUsed': playerJokerUsed,
  };

  factory Member.fromJson(Map<String, Object?> json) => Member(
    id: json['id']! as String,
    name: json['name']! as String,
    role: Role.values.byName(json['role']! as String),
    caught: json['caught'] as bool? ?? false,
    jokersUsed: json['jokersUsed'] as int? ?? 0,
    playerJokerUsed: json['playerJokerUsed'] as bool? ?? false,
  );
}
