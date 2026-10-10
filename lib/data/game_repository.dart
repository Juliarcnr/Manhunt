import '../core/crypto/group_crypto.dart';
import '../core/history/round_summary.dart';
import '../core/models/game_settings.dart';
import '../core/models/geo_point.dart';
import '../core/models/member.dart';

/// A group lives across many rounds: lobby → running → (host ends) → lobby …
enum GameStatus { lobby, running }

/// Decrypted view of the shared group document.
class GameInfo {
  const GameInfo({
    required this.adminId,
    required this.status,
    required this.settings,
    this.startAt,
    this.name,
    this.aliases = const {},
  });

  final String adminId;
  final GameStatus status;
  final GameSettings settings;

  /// Start of the current round; null in the lobby.
  final DateTime? startAt;

  /// Group name (R-GROUPS-04); null for groups created before names existed.
  final String? name;

  /// Anonymous player numbers of the current round by player id (R-ANON-01);
  /// empty in the lobby and without [GameSettings.anonymousPlayers].
  final Map<String, int> aliases;
}

/// What a device needs to talk to its group: the derived crypto and its own id.
class GroupSession {
  const GroupSession({
    required this.code,
    required this.crypto,
    required this.userId,
  });

  final String code;
  final GroupCrypto crypto;
  final String userId;

  String get groupId => crypto.groupId;
}

class GroupNotFoundException implements Exception {
  const GroupNotFoundException();
}

/// Backend access for groups and rounds. Implemented with Firestore; faked in tests.
abstract interface class GameRepository {
  Future<void> createGame(
    GroupSession session, {
    required String name,
    required GameSettings settings,
    String? groupName,
  });

  /// Throws [GroupNotFoundException]. Joining a running round is allowed
  /// (lost phone, R-LOBBY-07); the host assigns the role.
  Future<void> joinGame(GroupSession session, {required String name});

  Stream<GameInfo?> watchGame(GroupSession session);
  Stream<List<Member>> watchMembers(GroupSession session);

  /// Status of any group by its public id, without the key – for the group
  /// overview (R-GROUPS-03). Emits null if the group no longer exists.
  Stream<GameStatus?> watchStatus(String groupId);

  /// Host only. Does not touch the play area (see [updateArea]).
  Future<void> updateSettings(GroupSession session, GameSettings settings);

  /// Host only (R-GROUPS-04).
  Future<void> renameGroup(GroupSession session, String name);

  /// Any member, in the lobby (R-SET-10).
  Future<void> updateArea(GroupSession session, List<GeoPoint> area);
  Future<void> setRoles(GroupSession session, List<Member> members);
  Future<void> removeMember(GroupSession session, String memberId);

  /// With [GameSettings.anonymousPlayers] also shuffles the players' anonymous
  /// numbers for the round (R-ANON-01).
  Future<void> startGame(GroupSession session);

  /// Records a catch in the current round and marks the player as caught
  /// (R-CATCH-01, R-CATCH-02). Who reported it is not stored (R-CATCH-03).
  Future<void> recordCatch(GroupSession session, CatchRecord record);

  /// Catches of the current round, for notifications (R-NOTIF-02).
  Stream<List<CatchRecord>> watchCatches(GroupSession session);

  /// Host only: takes back a wrongly reported catch (R-CATCH-04). Deletes the
  /// player's catch events – so history and speedhunt forget it – and marks
  /// them as not caught; they play on as usual.
  Future<void> undoCatch(GroupSession session, String playerId);

  /// Host ends the round (R-GAME-06): saves a [RoundSummary] to the history
  /// (R-HIST-02), deletes all locations and round events (R-PRIV-03), resets
  /// caught/joker and returns the group to the lobby.
  Future<void> endRound(GroupSession session);

  /// Finished rounds, newest first (R-HIST-03).
  Stream<List<RoundSummary>> watchHistory(GroupSession session);

  /// Host deletes the whole group with everything in it.
  Future<void> deleteGame(GroupSession session);

  /// Called when a member opens the group (R-PRIV-05): deletes it if nobody
  /// opened it for 180 days, otherwise extends its lifetime. Returns false if
  /// the group is gone afterwards.
  Future<bool> checkIn(GroupSession session);
}
