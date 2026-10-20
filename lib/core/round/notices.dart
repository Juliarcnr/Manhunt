import '../history/round_summary.dart';
import '../schedule/speedhunt.dart';
import 'boundary_watch.dart';
import 'ping_schedule.dart';
import 'round_result.dart';

/// Something everyone (or this player) should be told about (R-NOTIF-01).
sealed class GameNotice {
  const GameNotice();
}

/// Someone was caught (R-NOTIF-02).
class CatchNotice extends GameNotice {
  const CatchNotice(this.record);
  final CatchRecord record;
}

/// The host took back [playerId]'s catch; they play on (R-CATCH-05).
class ReleaseNotice extends GameNotice {
  const ReleaseNotice(this.playerId);
  final String playerId;
}

/// A speedhunt started – deliberately without target (R-NOTIF-04, R-SPEED-04).
class SpeedhuntNotice extends GameNotice {
  const SpeedhuntNotice(this.speedhunt);
  final Speedhunt speedhunt;
}

/// This player's location was just sent to the hunters (R-NOTIF-03).
class PingSentNotice extends GameNotice {
  const PingSentNotice(this.kind);
  final PingKind kind;
}

/// The round is over – time up or last player caught – and [result] tells
/// who won (R-GAME-08, R-GAME-09).
class RoundOverNotice extends GameNotice {
  const RoundOverNotice(this.result);
  final RoundResult result;
}

/// How long the in-app banner for [notice] stays visible. A speedhunt notice
/// carries more text and matters more, so it stays longer (R-NOTIF-06); so
/// do the names of the players who won. "Hunters won" is also in the
/// permanent header, so a short banner is enough (R-GAME-09).
Duration noticeBannerDuration(GameNotice notice) => switch (notice) {
  SpeedhuntNotice() ||
  RoundOverNotice(result: PlayersWon()) => const Duration(seconds: 15),
  _ => const Duration(seconds: 5),
};

/// A player left the play area; the hunters see their live location
/// (R-OUT-05). For hunters only.
class PlayerOutsideNotice extends GameNotice {
  const PlayerOutsideNotice(this.playerId);
  final String playerId;
}

/// This player left the play area or their live location is shared or no
/// longer shared (R-OUT-06).
class OwnBoundaryNotice extends GameNotice {
  const OwnBoundaryNotice(this.event);
  final BoundaryEvent event;
}

/// Turns snapshots of catches/speedhunts into notices for *new* entries only.
/// The first snapshot after opening the app is the baseline and produces
/// nothing, so old events are not announced again.
class NoticeTracker {
  Set<String>? _catches;
  Set<String> _caught = const {};
  Set<String>? _speedhunts;
  Set<String>? _outside;
  var _resultKnown = false;
  RoundResult? _result;

  static String _catchKey(CatchRecord c) =>
      '${c.playerId}@${c.at.toUtc().toIso8601String()}';

  static String _speedhuntKey(Speedhunt s) =>
      s.startedAt.toUtc().toIso8601String();

  List<GameNotice> onCatches(List<CatchRecord> catches) {
    final known = _catches;
    final knownCaught = _caught;
    _catches = {for (final c in catches) _catchKey(c)};
    _caught = {for (final c in catches) c.playerId};
    if (known == null) return const [];
    // One catch per player, even if hunter and player both reported it.
    final announced = <String>{};
    return [
      for (final c in catches)
        if (!known.contains(_catchKey(c)) && announced.add(c.playerId))
          CatchNotice(c),
      // All catches of a player gone: the host undid them (R-CATCH-04). At
      // round end they vanish too – the caller must not announce those.
      for (final id in knownCaught)
        if (!_caught.contains(id)) ReleaseNotice(id),
    ];
  }

  List<GameNotice> onSpeedhunts(List<Speedhunt> speedhunts) {
    final known = _speedhunts;
    _speedhunts = {for (final s in speedhunts) _speedhuntKey(s)};
    if (known == null) return const [];
    return [
      for (final s in speedhunts)
        if (!known.contains(_speedhuntKey(s))) SpeedhuntNotice(s),
    ];
  }

  /// The round's [result], null while the game is on (R-GAME-09): announced
  /// once when the round becomes over; already over at the first call (app
  /// reopened) it is not announced again.
  List<GameNotice> onRoundOver(RoundResult? result) {
    final known = _resultKnown;
    final before = _result;
    _resultKnown = true;
    _result = result;
    return known && before == null && result != null
        ? [RoundOverNotice(result)]
        : const [];
  }

  /// Players outside the play area (ids of the live positions). Unlike the
  /// others, the first snapshot is announced too: being outside is a state,
  /// not a past event. Leaving again later is announced again (R-OUT-05).
  List<GameNotice> onOutside(Iterable<String> playerIds) {
    final known = _outside ?? const <String>{};
    _outside = playerIds.toSet();
    return [
      for (final id in _outside!)
        if (!known.contains(id)) PlayerOutsideNotice(id),
    ];
  }
}
