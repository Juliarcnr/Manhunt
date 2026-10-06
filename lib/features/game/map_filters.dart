import 'package:flutter/foundation.dart';

/// What the map shows; any combination is allowed (R-HUNT-01). Kept per
/// device while the game screen is open.
@immutable
class MapFilters {
  const MapFilters({
    this.hunters = true,
    this.lastPings = true,
    this.speedhunts = true,
    this.lines = true,
    this.playerHistories = const {},
    this.myPings = true,
    this.hunterJoker = true,
    this.playerJoker = true,
  });

  // Hunters (R-HUNT-02 … R-HUNT-07).
  final bool hunters;
  final bool lastPings;
  final bool speedhunts;

  /// Connect the selected players' pings with arrows (R-HUNT-05).
  final bool lines;

  /// Players whose full, numbered ping history is shown (R-HUNT-04).
  final Set<String> playerHistories;

  // Players (R-PLAY-01, R-PLAY-04). Joker filters only appear once used and
  // are on right after using a joker.
  final bool myPings;
  final bool hunterJoker;
  final bool playerJoker;

  MapFilters copyWith({
    bool? hunters,
    bool? lastPings,
    bool? speedhunts,
    bool? lines,
    Set<String>? playerHistories,
    bool? myPings,
    bool? hunterJoker,
    bool? playerJoker,
  }) => MapFilters(
    hunters: hunters ?? this.hunters,
    lastPings: lastPings ?? this.lastPings,
    speedhunts: speedhunts ?? this.speedhunts,
    lines: lines ?? this.lines,
    playerHistories: playerHistories ?? this.playerHistories,
    myPings: myPings ?? this.myPings,
    hunterJoker: hunterJoker ?? this.hunterJoker,
    playerJoker: playerJoker ?? this.playerJoker,
  );

  MapFilters togglePlayer(String id) => copyWith(
    playerHistories: playerHistories.contains(id)
        ? ({...playerHistories}..remove(id))
        : {...playerHistories, id},
  );
}
