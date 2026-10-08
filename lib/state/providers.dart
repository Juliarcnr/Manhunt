import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/group_crypto.dart';
import '../core/groups/group_list.dart';
import '../core/history/round_summary.dart';
import '../core/models/member.dart';
import '../core/round/joker.dart';
import '../core/round/ping_schedule.dart';
import '../core/schedule/speedhunt.dart';
import '../data/firestore_game_repository.dart';
import '../data/firestore_round_repository.dart';
import '../data/game_repository.dart';
import '../data/joker_store.dart';
import '../data/location_service.dart';
import '../data/notification_service.dart';
import '../data/round_repository.dart';
import '../data/session_store.dart';
import 'session_controller.dart';

// Infrastructure – overridden in tests.

final gameRepositoryProvider = Provider<GameRepository>(
  (ref) => FirestoreGameRepository(FirebaseFirestore.instance),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

/// Returns the anonymous user id, signing in on first use (no account, R-LOBBY-01).
final userIdProvider = Provider<Future<String> Function()>((ref) {
  return () async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
    return user.uid;
  };
});

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);

final cryptoFactoryProvider = Provider<CryptoFactory>(
  (ref) => GroupCrypto.derive,
);

// App state.

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, GroupSession?>(
      SessionController.new,
    );

/// This device's groups for the overview (R-GROUPS-01).
final groupListProvider = FutureProvider<GroupList>(
  (ref) => ref.read(sessionStoreProvider).loadGroups(),
);

/// Lobby/running/deleted per group, by public group id (R-GROUPS-03).
final groupStatusProvider = StreamProvider.family<GameStatus?, String>(
  (ref, groupId) => ref.watch(gameRepositoryProvider).watchStatus(groupId),
);

final gameProvider = StreamProvider<GameInfo?>((ref) {
  final session = ref.watch(sessionControllerProvider).value;
  if (session == null) return Stream.value(null);
  return ref.watch(gameRepositoryProvider).watchGame(session);
});

final historyProvider = StreamProvider<List<RoundSummary>>((ref) {
  final session = ref.watch(sessionControllerProvider).value;
  if (session == null) return Stream.value(const []);
  return ref.watch(gameRepositoryProvider).watchHistory(session);
});

final membersProvider = StreamProvider<List<Member>>((ref) {
  final session = ref.watch(sessionControllerProvider).value;
  if (session == null) return Stream.value(const []);
  return ref.watch(gameRepositoryProvider).watchMembers(session);
});

// Running round (phase 5). Hunter-only streams must only be watched by
// hunters – the security rules reject them for players.

final roundRepositoryProvider = Provider<RoundRepository>(
  (ref) => FirestoreRoundRepository(FirebaseFirestore.instance),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => LocalNotificationService(),
);

Stream<T> _sessionStream<T>(
  Ref ref,
  T empty,
  Stream<T> Function(GroupSession session) build,
) {
  final session = ref.watch(sessionControllerProvider).value;
  if (session == null) return Stream.value(empty);
  return build(session);
}

final catchesProvider = StreamProvider<List<CatchRecord>>(
  (ref) => _sessionStream(
    ref,
    const [],
    ref.watch(gameRepositoryProvider).watchCatches,
  ),
);

final _storedSpeedhuntsProvider = StreamProvider<List<Speedhunt>>(
  (ref) => _sessionStream(
    ref,
    const [],
    ref.watch(roundRepositoryProvider).watchSpeedhunts,
  ),
);

final _storedSpeedhuntsOnMeProvider = StreamProvider<List<Speedhunt>>(
  (ref) => _sessionStream(
    ref,
    const [],
    ref.watch(roundRepositoryProvider).watchSpeedhuntsOnMe,
  ),
);

/// Public speedhunts without target (everyone), ended by catches
/// (R-SPEED-10).
final speedhuntsProvider = Provider<AsyncValue<List<Speedhunt>>>(
  (ref) => ref
      .watch(_storedSpeedhuntsProvider)
      .whenData(
        (all) => applyCatches(all, ref.watch(catchesProvider).value ?? []),
      ),
);

/// Speedhunts targeting this device's player, ended by catches
/// (R-SPEED-10).
final speedhuntsOnMeProvider = Provider<AsyncValue<List<Speedhunt>>>(
  (ref) => ref
      .watch(_storedSpeedhuntsOnMeProvider)
      .whenData(
        (all) => applyCatches(all, ref.watch(catchesProvider).value ?? []),
      ),
);

/// Hunters only.
final allPingsProvider = StreamProvider<List<PingRecord>>(
  (ref) => _sessionStream(
    ref,
    const [],
    ref.watch(roundRepositoryProvider).watchAllPings,
  ),
);

/// The player's own pings.
final myPingsProvider = StreamProvider<List<PingRecord>>(
  (ref) => _sessionStream(
    ref,
    const [],
    ref.watch(roundRepositoryProvider).watchMyPings,
  ),
);

/// All players' regular pings – players only, and only when the regular pings
/// go to everyone (R-SET-15); the rules reject it otherwise.
final sharedPingsProvider = StreamProvider<List<PingRecord>>(
  (ref) => _sessionStream(
    ref,
    const [],
    ref.watch(roundRepositoryProvider).watchSharedPings,
  ),
);

/// Hunters only.
final hunterLocationsProvider = StreamProvider<Map<String, LocationFix>>(
  (ref) => _sessionStream(
    ref,
    const {},
    ref.watch(roundRepositoryProvider).watchHunterLocations,
  ),
);

/// Joker "player positions" requests – players only (R-PLAY-03).
final jokerRequestsProvider = StreamProvider<List<JokerRequest>>(
  (ref) => _sessionStream(
    ref,
    const [],
    ref.watch(roundRepositoryProvider).watchJokerRequests,
  ),
);

/// Answers to the own joker request, by player id.
final jokerAnswersProvider =
    StreamProvider.family<Map<String, LocationFix>, String>(
      (ref, requestId) => _sessionStream(
        ref,
        const {},
        (s) =>
            ref.watch(roundRepositoryProvider).watchJokerAnswers(s, requestId),
      ),
    );

/// Joker results kept on this device (R-PLAY-04).
final jokerStoreProvider = Provider<JokerStore>((ref) => SecureJokerStore());
