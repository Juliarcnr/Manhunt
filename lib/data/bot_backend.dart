import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/bots/bot_plan.dart';
import '../firebase_options.dart';
import 'firestore_game_repository.dart';
import 'firestore_round_repository.dart';
import 'game_repository.dart';
import 'round_repository.dart';

/// One computer member as its own "device": own anonymous account, own
/// backend access – so it uses exactly the flows and security rules of a
/// real phone (R-BOT-05, R-BOT-06).
class BotDevice {
  const BotDevice({
    required this.id,
    required this.games,
    required this.rounds,
  });

  final String id;
  final GameRepository games;
  final RoundRepository rounds;
}

abstract interface class BotBackend {
  /// Bot slots per phone (enough for the settings' maximum).
  static const slots = 2 * maxBotsPerKind;

  /// Ids of the slots this phone used before, by slot (1 … [slots]) –
  /// without signing in.
  Future<Map<int, String>> knownIds();

  /// Opens [slot], signing in its own anonymous account on first use.
  Future<BotDevice> open(int slot);
}

/// Each slot is a separate FirebaseApp `bot-<slot>`; Firebase keeps its
/// anonymous account per app name, so a slot keeps its id across restarts.
class FirebaseBotBackend implements BotBackend {
  final _devices = <int, Future<BotDevice>>{};

  Future<FirebaseApp> _app(int slot) async {
    final name = 'bot-$slot';
    for (final app in Firebase.apps) {
      if (app.name == name) return app;
    }
    return Firebase.initializeApp(
      name: name,
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  @override
  Future<Map<int, String>> knownIds() async {
    final ids = <int, String>{};
    for (var slot = 1; slot <= BotBackend.slots; slot++) {
      final auth = FirebaseAuth.instanceFor(app: await _app(slot));
      // The persisted account is restored asynchronously.
      final user = auth.currentUser ?? await auth.authStateChanges().first;
      if (user != null) ids[slot] = user.uid;
    }
    return ids;
  }

  @override
  Future<BotDevice> open(int slot) async {
    final pending = _devices.putIfAbsent(slot, () => _open(slot));
    try {
      return await pending;
    } on Object {
      _devices.remove(slot)?.ignore(); // retried on the next call
      rethrow;
    }
  }

  Future<BotDevice> _open(int slot) async {
    final app = await _app(slot);
    final auth = FirebaseAuth.instanceFor(app: app);
    final user =
        auth.currentUser ??
        await auth.authStateChanges().first ??
        (await auth.signInAnonymously()).user!;
    final db = FirebaseFirestore.instanceFor(app: app);
    return BotDevice(
      id: user.uid,
      games: FirestoreGameRepository(db),
      rounds: FirestoreRoundRepository(db),
    );
  }
}
