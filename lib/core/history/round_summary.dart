import '../models/member.dart';

/// One catch during a round (R-HIST-01): who and when – deliberately not by
/// whom (R-CATCH-03). Reported by a hunter or the player themself (R-CATCH-01).
class CatchRecord {
  const CatchRecord({required this.playerId, required this.at});

  final String playerId;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'playerId': playerId,
    'at': at.toUtc().toIso8601String(),
  };

  factory CatchRecord.fromJson(Map<String, Object?> json) => CatchRecord(
    playerId: json['playerId']! as String,
    at: DateTime.parse(json['at']! as String),
  );
}

/// A catch as shown in the history, with the name frozen at round end so the
/// entry stays readable after people leave the group.
class CatchEntry {
  const CatchEntry({required this.player, required this.after});

  final String player;

  /// Time since round start.
  final Duration after;

  Map<String, Object?> toJson() => {
    'player': player,
    'afterSec': after.inSeconds,
  };

  factory CatchEntry.fromJson(Map<String, Object?> json) => CatchEntry(
    player: json['player']! as String,
    after: Duration(seconds: json['afterSec']! as int),
  );
}

/// Summary of a finished round, kept in the group history (R-HIST-02).
/// Contains no locations.
class RoundSummary {
  const RoundSummary({
    required this.round,
    required this.startedAt,
    required this.endedAt,
    required this.hunters,
    required this.players,
    required this.catches,
    this.abortedEarly = false,
  });

  final int round;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<String> hunters;
  final List<String> players;

  /// Chronological.
  final List<CatchEntry> catches;

  /// The host ended the round before its time was up (R-GAME-07).
  final bool abortedEarly;

  Duration get duration => endedAt.difference(startedAt);

  /// Players who were not caught.
  List<String> get survivors {
    final caught = {for (final c in catches) c.player};
    return [
      for (final p in players)
        if (!caught.contains(p)) p,
    ];
  }

  Map<String, Object?> toJson() => {
    'round': round,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'hunters': hunters,
    'players': players,
    'catches': [for (final c in catches) c.toJson()],
    'abortedEarly': abortedEarly,
  };

  factory RoundSummary.fromJson(Map<String, Object?> json) => RoundSummary(
    round: json['round']! as int,
    startedAt: DateTime.parse(json['startedAt']! as String),
    endedAt: DateTime.parse(json['endedAt']! as String),
    hunters: (json['hunters']! as List<Object?>).cast<String>(),
    players: (json['players']! as List<Object?>).cast<String>(),
    catches: [
      for (final c in json['catches']! as List<Object?>)
        CatchEntry.fromJson(c! as Map<String, Object?>),
    ],
    abortedEarly: json['abortedEarly'] as bool? ?? false,
  );

  /// Builds the summary at round end from the members and recorded catches.
  /// A player caught twice (e.g. reported by hunter and self) counts once,
  /// with the earliest time.
  factory RoundSummary.build({
    required int round,
    required DateTime startedAt,
    required DateTime endedAt,
    required List<Member> members,
    required List<CatchRecord> catches,

    /// The configured round duration; ending before it counts as aborted.
    Duration? plannedDuration,
  }) {
    final names = {for (final m in members) m.id: m.name};
    final sorted = [...catches]..sort((a, b) => a.at.compareTo(b.at));
    final seen = <String>{};
    final entries = <CatchEntry>[];
    for (final c in sorted) {
      final player = names[c.playerId];
      if (player == null || !seen.add(c.playerId)) continue;
      entries.add(
        CatchEntry(player: player, after: c.at.difference(startedAt)),
      );
    }
    return RoundSummary(
      round: round,
      startedAt: startedAt,
      endedAt: endedAt,
      hunters: [for (final m in members.where((m) => m.isHunter)) m.name],
      players: [for (final m in members.where((m) => m.isPlayer)) m.name],
      catches: entries,
      abortedEarly:
          plannedDuration != null &&
          endedAt.isBefore(startedAt.add(plannedDuration)),
    );
  }
}
