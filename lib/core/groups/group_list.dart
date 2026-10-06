/// A group this device belongs to, remembered locally (R-GROUPS-01).
///
/// Lives in the OS keystore only: the [code] is the group's secret.
class SavedGroup {
  const SavedGroup({
    required this.code,
    this.groupId,
    this.name,
    this.isHost = false,
  });

  final String code;

  /// Public document id; null until the group was opened once (groups
  /// migrated from the single-group version only know their code).
  final String? groupId;

  /// Group name as last seen; null for groups without a name.
  final String? name;

  /// This device created the group.
  final bool isHost;

  SavedGroup copyWith({String? groupId, String? name, bool? isHost}) =>
      SavedGroup(
        code: code,
        groupId: groupId ?? this.groupId,
        name: name ?? this.name,
        isHost: isHost ?? this.isHost,
      );

  Map<String, Object?> toJson() => {
    'code': code,
    if (groupId != null) 'groupId': groupId,
    if (name != null) 'name': name,
    if (isHost) 'isHost': true,
  };

  factory SavedGroup.fromJson(Map<String, Object?> json) => SavedGroup(
    code: json['code']! as String,
    groupId: json['groupId'] as String?,
    name: json['name'] as String?,
    isHost: json['isHost'] as bool? ?? false,
  );
}

/// Creating or joining one more group than [GroupList.maxGroups] allows.
class GroupLimitException implements Exception {
  const GroupLimitException();
}

/// The groups of this device, in the order they were added (R-GROUPS-01, -02).
class GroupList {
  const GroupList([this.groups = const []]);

  /// Created and joined groups together (R-GROUPS-02).
  static const maxGroups = 5;

  final List<SavedGroup> groups;

  bool get isEmpty => groups.isEmpty;
  bool get isFull => groups.length >= maxGroups;

  SavedGroup? find(String code) {
    for (final g in groups) {
      if (g.code == code) return g;
    }
    return null;
  }

  /// Adds [group], or updates the entry with the same code in place (so
  /// re-joining a known group never counts against the limit).
  /// Throws [GroupLimitException] if a new group does not fit.
  GroupList add(SavedGroup group) {
    if (find(group.code) != null) {
      return GroupList([
        for (final g in groups) g.code == group.code ? group : g,
      ]);
    }
    if (isFull) throw const GroupLimitException();
    return GroupList([...groups, group]);
  }

  GroupList remove(String code) => GroupList([
    for (final g in groups)
      if (g.code != code) g,
  ]);

  /// Updates details of a known group; unknown codes are ignored.
  GroupList update(
    String code, {
    String? groupId,
    String? name,
    bool? isHost,
  }) => GroupList([
    for (final g in groups)
      g.code == code
          ? g.copyWith(groupId: groupId, name: name, isHost: isHost)
          : g,
  ]);

  List<Object?> toJson() => [for (final g in groups) g.toJson()];

  factory GroupList.fromJson(List<Object?> json) => GroupList([
    for (final g in json) SavedGroup.fromJson(g! as Map<String, Object?>),
  ]);
}
