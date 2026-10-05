/// A player used the joker "player positions" (R-PLAY-03) and asks all other
/// players' devices for their current position. Answers are only readable by
/// the requester, so positions exist on the server only when asked for.
class JokerRequest {
  const JokerRequest({
    required this.id,
    required this.requesterId,
    required this.at,
  });

  final String id;
  final String requesterId;

  /// Server time of the request (local time while the write is pending).
  final DateTime at;
}

/// How long devices answer a joker request; older ones are ignored, e.g. when
/// a phone was offline for a while.
const jokerAnswerWindow = Duration(minutes: 2);

/// Requests this player's device should answer now: fresh, not own, not yet
/// answered.
List<JokerRequest> requestsToAnswer(
  List<JokerRequest> requests, {
  required String myId,
  required DateTime now,
  required Set<String> answered,
}) => [
  for (final r in requests)
    if (r.requesterId != myId &&
        !answered.contains(r.id) &&
        now.difference(r.at) <= jokerAnswerWindow)
      r,
];
