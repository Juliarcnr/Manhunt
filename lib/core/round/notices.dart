import '../history/round_summary.dart';
import '../models/member.dart';
import '../schedule/game_clock.dart';
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

/// The countdown is over: the game officially starts now (R-START-04).
class GameStartedNotice extends GameNotice {
  const GameStartedNotice();
}

/// The round is over – time up or last player caught – and [result] tells
/// who won (R-GAME-08, R-GAME-09).
class RoundOverNotice extends GameNotice {
  const RoundOverNotice(this.result);
  final RoundResult result;
}

/// How long the in-app banner for [notice] stays visible. A speedhunt notice
/// carries more text and matters more, so it stays longer (R-NOTIF-06); who
/// won stays until the round is saved and the group is back in the lobby
/// (R-GAME-09, R-GAME-10).
Duration noticeBannerDuration(GameNotice notice) => switch (notice) {
  SpeedhuntNotice() || RoundOverNotice() => const Duration(seconds: 15),
  _ => const Duration(seconds: 5),
};

/// Whether an open app shows [notice] as its own banner. Not for the own
/// boundary state, which has a permanent banner (R-OUT-06).
bool showsBanner(GameNotice notice) => notice is! OwnBoundaryNotice;

/// Whether [me] is told about [notice] at all. Caught players get no
/// speedhunt notice: it is not on them, and they follow speedhunts in the
/// live view anyway (R-NOTIF-07, R-GM-10).
bool isAnnouncedTo(GameNotice notice, Member? me) => switch (notice) {
  SpeedhuntNotice() => !(me != null && me.isPlayer && me.caught),
  _ => true,
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
  var _countingDown = false;

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

  /// The current [phase]: announced once when the countdown seen by this
  /// tracker runs out (R-START-04); opened after the start there is nothing
  /// to tell.
  List<GameNotice> onPhase(GamePhase phase) {
    if (phase == GamePhase.notStarted) {
      _countingDown = true;
      return const [];
    }
    final ended = _countingDown;
    _countingDown = false;
    return ended && phase != GamePhase.ended
        ? const [GameStartedNotice()]
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
