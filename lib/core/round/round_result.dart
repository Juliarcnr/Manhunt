import '../models/member.dart';
import '../schedule/game_clock.dart';

/// Who won a round that is over but not yet ended by the host (R-GAME-09).
sealed class RoundResult {
  const RoundResult();
}

/// All players were caught – by the last catch (R-GAME-08) or by the time.
class HuntersWon extends RoundResult {
  const HuntersWon();
}

/// The time is up and [playerIds] were never caught: they won.
class PlayersWon extends RoundResult {
  const PlayersWon(this.playerIds);
  final List<String> playerIds;
}

/// The result once the round is over, null while the game is on, while
/// waiting for the confirmation after the time was up (R-GAME-11) or while
/// the start time is still missing. Also null without any players – e.g. while
/// the members are still loading – unless the hunters' win is recorded.
RoundResult? roundResult({
  required GameClock? clock,
  required DateTime now,
  required List<Member> members,
}) {
  if (clock == null || clock.phaseAt(now) != GamePhase.ended) return null;
  if (clock.awaitingConfirmation(now)) return null;
  if (clock.huntersWon) return const HuntersWon();
  if (!members.any((m) => m.isPlayer)) return null;
  final free = [
    for (final m in members)
      if (m.isPlayer && !m.caught) m.id,
  ];
  return free.isEmpty ? const HuntersWon() : PlayersWon(free);
}

/// Ids of everyone who won: all hunters or the players never caught.
Set<String> winnerIds(RoundResult result, List<Member> members) =>
    switch (result) {
      HuntersWon() => {
        for (final m in members)
          if (m.isHunter) m.id,
      },
      PlayersWon(:final playerIds) => playerIds.toSet(),
    };

/// Whether [me] is asked, once the time is up, who else was caught: hunters
/// and players still in the game (R-GAME-11). Not game masters, caught or
/// unassigned members – they only see that the time is up.
bool confirmsTimeUp(Member? me) =>
    me != null && (me.isHunter || (me.isPlayer && !me.caught));
