import '../core/round/joker.dart';
import '../core/round/ping_schedule.dart';
import '../core/schedule/speedhunt.dart';
import 'game_repository.dart';

/// Data of a running round: pings, hunter positions, speedhunts, joker.
/// Everything location-related is end-to-end encrypted (R-PRIV-02) and
/// deleted when the round ends (R-PRIV-03).
abstract interface class RoundRepository {
  /// Player sends one scheduled ping (R-PING-01). Idempotent per slot.
  Future<void> sendPing(GroupSession session, PingSlot slot, LocationFix fix);

  /// All players' pings – hunters only (R-HUNT-03, R-HUNT-04).
  Stream<List<PingRecord>> watchAllPings(GroupSession session);

  /// The player's own sent pings (R-PLAY-01).
  Stream<List<PingRecord>> watchMyPings(GroupSession session);

  /// Hunter shares their live position with the other hunters (R-HUNT-02).
  Future<void> updateHunterLocation(GroupSession session, LocationFix fix);

  /// Live hunter positions by hunter id – hunters only.
  Stream<Map<String, LocationFix>> watchHunterLocations(GroupSession session);

  /// Player uses their single joker (R-PLAY-02) and gets the hunters'
  /// current positions once.
  Future<Map<String, LocationFix>> useJoker(GroupSession session);

  /// Player uses their joker "player positions" (R-PLAY-03): marks it as used
  /// and asks all other players' devices for their position. Returns the
  /// request id to watch the answers.
  Future<String> requestPlayerPositions(GroupSession session);

  /// Open joker requests – players only.
  Stream<List<JokerRequest>> watchJokerRequests(GroupSession session);

  /// This player's device answers a request with its current position.
  Future<void> answerJokerRequest(
    GroupSession session,
    JokerRequest request,
    LocationFix fix,
  );

  /// Answers to the own request, by player id – readable only by the requester.
  Stream<Map<String, LocationFix>> watchJokerAnswers(
    GroupSession session,
    String requestId,
  );

  /// Hunter starts a speedhunt (R-SPEED-02). The target is stored apart from
  /// the public event so players don't learn who it is (R-SPEED-04).
  Future<void> startSpeedhunt(GroupSession session, Speedhunt speedhunt);

  /// All speedhunts of the round, without target ([Speedhunt.targetId] is
  /// empty) – visible to everyone (R-SPEED-05).
  Stream<List<Speedhunt>> watchSpeedhunts(GroupSession session);

  /// Speedhunts targeting this device's player, with target set.
  Stream<List<Speedhunt>> watchSpeedhuntsOnMe(GroupSession session);
}
