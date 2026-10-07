import 'package:flutter/foundation.dart';

/// How a hunter sees one player's ping history (R-HUNT-04, R-HUNT-05). A tap
/// on the player's chip cycles off → points → points with lines → off.
enum HistoryMode {
  off,
  points,
  lines;

  HistoryMode get next => values[(index + 1) % values.length];
}

/// What the map shows; any combination is allowed (R-HUNT-01). Kept per
/// device while the game screen is open.
@immutable
class MapFilters {
  const MapFilters({
    this.hunters = true,
    this.lastPings = true,
    this.playerHistories = const {},
    this.hiddenSpeedhunts = const {},
    this.caught = false,
    this.myPings = true,
    this.hunterJoker = true,
    this.playerJoker = true,
  });

  // Hunters (R-HUNT-02 … R-HUNT-07).
  final bool hunters;
  final bool lastPings;

  /// Players whose numbered ping history is shown, with or without lines
  /// (R-HUNT-04, R-HUNT-05). Missing means [HistoryMode.off].
  final Map<String, HistoryMode> playerHistories;

  /// Speedhunts (`SpeedhuntPings.id`) switched off; a new speedhunt is shown
  /// right away (R-HUNT-07).
  final Set<String> hiddenSpeedhunts;

  /// Regular history and speedhunt pings of all caught players in one chip;
  /// caught players lose their own chips (R-HUNT-09).
  final bool caught;

  // Players (R-PLAY-01, R-PLAY-04). Joker filters only appear once used and
  // are on right after using a joker.
  final bool myPings;
  final bool hunterJoker;
  final bool playerJoker;

  HistoryMode historyOf(String playerId) =>
      playerHistories[playerId] ?? HistoryMode.off;

  MapFilters copyWith({
    bool? hunters,
    bool? lastPings,
    Map<String, HistoryMode>? playerHistories,
    Set<String>? hiddenSpeedhunts,
    bool? caught,
    bool? myPings,
    bool? hunterJoker,
    bool? playerJoker,
  }) => MapFilters(
    hunters: hunters ?? this.hunters,
    lastPings: lastPings ?? this.lastPings,
    playerHistories: playerHistories ?? this.playerHistories,
    hiddenSpeedhunts: hiddenSpeedhunts ?? this.hiddenSpeedhunts,
    caught: caught ?? this.caught,
    myPings: myPings ?? this.myPings,
    hunterJoker: hunterJoker ?? this.hunterJoker,
    playerJoker: playerJoker ?? this.playerJoker,
  );

  /// Next step of the player's chip: off → points → lines → off.
  MapFilters cyclePlayer(String id) {
    final next = historyOf(id).next;
    return copyWith(
      playerHistories: next == HistoryMode.off
          ? ({...playerHistories}..remove(id))
          : {...playerHistories, id: next},
    );
  }

  MapFilters toggleSpeedhunt(String id) => copyWith(
    hiddenSpeedhunts: hiddenSpeedhunts.contains(id)
        ? ({...hiddenSpeedhunts}..remove(id))
        : {...hiddenSpeedhunts, id},
  );
}
