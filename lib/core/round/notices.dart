import '../history/round_summary.dart';
import '../schedule/speedhunt.dart';
import 'ping_schedule.dart';

/// Something everyone (or this player) should be told about (R-NOTIF-01).
sealed class GameNotice {
  const GameNotice();
}

/// Someone was caught (R-NOTIF-02).
class CatchNotice extends GameNotice {
  const CatchNotice(this.record);
  final CatchRecord record;
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

/// Turns snapshots of catches/speedhunts into notices for *new* entries only.
/// The first snapshot after opening the app is the baseline and produces
/// nothing, so old events are not announced again.
class NoticeTracker {
  Set<String>? _catches;
  Set<String>? _speedhunts;

  static String _catchKey(CatchRecord c) =>
      '${c.playerId}@${c.at.toUtc().toIso8601String()}';

  static String _speedhuntKey(Speedhunt s) =>
      s.startedAt.toUtc().toIso8601String();

  List<GameNotice> onCatches(List<CatchRecord> catches) {
    final known = _catches;
    _catches = {for (final c in catches) _catchKey(c)};
    if (known == null) return const [];
    // One catch per player, even if hunter and player both reported it.
    final announced = <String>{};
    return [
      for (final c in catches)
        if (!known.contains(_catchKey(c)) && announced.add(c.playerId))
          CatchNotice(c),
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
}
