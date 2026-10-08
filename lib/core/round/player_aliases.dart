import 'dart:math';

import '../schedule/game_clock.dart';

/// Anonymous numbers "Player 1 … n" that hunters see instead of the players'
/// names (R-ANON-01). Shuffled by the host at the start of a round and stored
/// with the game, so every device shows the same numbers.
Map<String, int> shuffleAliases(List<String> playerIds, Random random) {
  final numbers = [for (var i = 1; i <= playerIds.length; i++) i]
    ..shuffle(random);
  return {for (final (i, id) in playerIds.indexed) id: numbers[i]};
}

/// [aliases] for [playerIds], plus the next free numbers for players without
/// one, in the given order – the same on every device, and existing numbers
/// never move.
Map<String, int> completeAliases(
  Map<String, int> aliases,
  List<String> playerIds,
) {
  var next = aliases.values.fold(0, max) + 1;
  return {for (final id in playerIds) id: aliases[id] ?? next++};
}

/// [playerIds] ordered by their number – chips and colours follow this order,
/// so the join order does not give anyone away (R-ANON-01).
List<String> byAlias(Map<String, int> aliases, List<String> playerIds) {
  final complete = completeAliases(aliases, playerIds);
  return [...playerIds]..sort((a, b) => complete[a]!.compareTo(complete[b]!));
}

/// Hunters see numbers instead of names while the round runs; once the time
/// is up, the real names are revealed (R-ANON-02). Players always see names
/// (R-ANON-03).
bool showAliases({
  required bool enabled,
  required bool isHunter,
  required GamePhase phase,
}) => enabled && isHunter && phase != GamePhase.ended;
