import '../core/crypto/group_crypto.dart';
import '../core/history/round_map.dart';
import '../core/history/round_summary.dart';
import '../core/models/game_settings.dart';
import '../core/models/geo_point.dart';
import '../core/models/member.dart';
import '../core/round/read_budget.dart';

/// A group lives across many rounds: lobby → running → (host ends) → lobby …
enum GameStatus { lobby, running }

/// Decrypted view of the shared group document.
class GameInfo {
  const GameInfo({
    required this.adminId,
    required this.status,
    required this.settings,
    this.startAt,
    this.finishedAt,
    this.confirmedAt,
    this.name,
    this.aliases = const {},
    this.hunterLiveInterval = const Duration(seconds: 5),
  });

  final String adminId;
  final GameStatus status;
  final GameSettings settings;

  /// Start of the current round; null in the lobby.
  final DateTime? startAt;

  /// When the last player was caught and the hunters won (R-GAME-08); null
  /// otherwise and in the lobby.
  final DateTime? finishedAt;

  /// When someone still in the game confirmed, after the time was up, who
  /// else was caught (R-GAME-11); null before and in the lobby.
  final DateTime? confirmedAt;

  /// Group name (R-GROUPS-04); null for groups created before names existed.
  final String? name;

  /// Anonymous player numbers of the current round by player id (R-ANON-01);
  /// empty in the lobby and without [GameSettings.anonymousPlayers].
  final Map<String, int> aliases;

  /// How often hunters share their live position this round: 5 s, or 15 s
  /// if the host's estimate said the round would use too many reads
  /// (R-QUOTA-01). Set at the start; 5 s for older rounds.
  final Duration hunterLiveInterval;

  /// Live positions are shared less often this round: hunters see each
  /// other every 15 s, game masters and caught players everyone every 30 s
  /// (R-QUOTA-01).
  bool get hunterLiveThrottled => hunterLiveInterval.inSeconds > 5;

  /// How often game masters and caught players see everyone live this round,
  /// and how often players share their live position for them: 15 s, or
  /// 30 s in a throttled round (R-GM-05, R-QUOTA-01).
  Duration get watcherLiveInterval =>
      watcherLiveIntervalFor(hunterLiveInterval);
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

  /// Any member, own display name only (R-LOBBY-10).
  Future<void> renameMe(GroupSession session, String name);

  /// Any member, in the lobby (R-SET-10).
  Future<void> updateArea(GroupSession session, List<GeoPoint> area);
  Future<void> setRoles(GroupSession session, List<Member> members);
  Future<void> removeMember(GroupSession session, String memberId);

  /// With [GameSettings.anonymousPlayers] also shuffles the players' anonymous
  /// numbers for the round (R-ANON-01).
  Future<void> startGame(GroupSession session);

  /// Records a catch in the current round and marks the player as caught
  /// (R-CATCH-01, R-CATCH-02). Who reported it is not stored (R-CATCH-03).
  /// [finishes]: it is the last player – the hunters have won and the round
  /// is over as if the time were up (R-GAME-08).
  Future<void> recordCatch(
    GroupSession session,
    CatchRecord record, {
    bool finishes = false,
  });

  /// Hunter or player still in the game, once the time is up: confirms who
  /// else was caught – [catches], possibly none (R-GAME-11). Catches and
  /// confirmation are written together, so everyone sees the same result.
  /// Only the first confirmation of a round counts; a later one is refused.
  Future<void> confirmTimeUp(GroupSession session, List<CatchRecord> catches);

  /// Catches of the current round, for notifications (R-NOTIF-02).
  Stream<List<CatchRecord>> watchCatches(GroupSession session);

  /// Host only: takes back a wrongly reported catch (R-CATCH-04). Deletes the
  /// player's catch events – so history and speedhunt forget it – and marks
  /// them as not caught; they play on as usual.
  Future<void> undoCatch(GroupSession session, String playerId);

  /// Host aborts the round (R-GAME-07): saves a [RoundSummary] and a
  /// [RoundMap] to the history (R-HIST-02, R-HIST-04), deletes all round data
  /// incl. locations (R-PRIV-03), resets caught/joker and returns the group
  /// to the lobby.
  Future<void> endRound(GroupSession session);

  /// Any member: ends the round like [endRound] once it has been over for
  /// `GameClock.autoEndDelay` (R-GAME-10); otherwise does nothing. Safe to
  /// call from several devices at once: the round is saved to the history
  /// only once. Returns whether it ended the round.
  Future<bool> autoEndRound(GroupSession session);

  /// Finished rounds, newest first (R-HIST-03).
  Stream<List<RoundSummary>> watchHistory(GroupSession session);

  /// The map saved with history entry [historyId] (R-HIST-04), loaded once;
  /// null for rounds without one.
  Future<RoundMap?> loadRoundMap(GroupSession session, String historyId);

  /// Host only: deletes a round from the history with its map, for good
  /// (R-HIST-06).
  Future<void> deleteHistoryEntry(GroupSession session, String historyId);

  /// Host deletes the whole group with everything in it.
  Future<void> deleteGame(GroupSession session);

  /// Called when a member opens the group (R-PRIV-05): deletes it if nobody
  /// opened it for 180 days, otherwise extends its lifetime and ends a round
  /// left running too long (R-GAME-10). Returns false if the group is gone
  /// afterwards.
  Future<bool> checkIn(GroupSession session);
}
