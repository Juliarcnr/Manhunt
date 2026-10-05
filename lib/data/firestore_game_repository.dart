import 'package:cloud_firestore/cloud_firestore.dart' hide GeoPoint;

import '../core/history/round_summary.dart';
import '../core/models/game_settings.dart';
import '../core/models/geo_point.dart';
import '../core/models/member.dart';
import 'game_repository.dart';

/// Firestore layout (see docs/architecture.md):
/// - `games/{groupId}`: adminUid, status, settings + area (encrypted, separate), startAt, createdAt, expiresAt
/// - `games/{groupId}/members/{uid}`: name (encrypted), role, caught, jokerUsed, joinedAt
/// - `games/{groupId}/{pings,hunterLocs,events}/…`: per-round data, deleted when the round ends
/// - `games/{groupId}/history/{auto}`: endedAt, data (encrypted RoundSummary, no locations)
class FirestoreGameRepository implements GameRepository {
  FirestoreGameRepository(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  /// Groups are deleted after nobody opened them for this long (R-PRIV-05).
  static const groupLifetime = Duration(days: 180);

  /// Opening the app extends the lifetime only if the last extension is at
  /// least this old.
  static const touchInterval = Duration(days: 1);

  /// Subcollections with sensitive per-round data (locations etc.).
  static const roundCollections = [
    'pings',
    'hunterLocs',
    'events',
    'speedhuntTargets',
    'jokerRequests',
    'jokerAnswers',
  ];

  /// Firestore allows at most 500 writes per batch.
  static const _batchSize = 400;

  DocumentReference<Map<String, dynamic>> _game(GroupSession s) =>
      _db.collection('games').doc(s.groupId);

  CollectionReference<Map<String, dynamic>> _members(GroupSession s) =>
      _game(s).collection('members');

  Timestamp _newExpiry() => Timestamp.fromDate(_now().add(groupLifetime));

  @override
  Future<void> createGame(
    GroupSession session, {
    required String name,
    required GameSettings settings,
  }) async {
    await _game(session).set({
      'adminUid': session.userId,
      'status': GameStatus.lobby.name,
      ...await _encodeSettings(session, settings, withArea: true),
      'startAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': _newExpiry(),
    });
    await _writeMember(session, name);
  }

  @override
  Future<void> joinGame(GroupSession session, {required String name}) async {
    final snap = await _game(session).get();
    if (!snap.exists) throw const GroupNotFoundException();
    await _writeMember(session, name);
  }

  /// Creates the own member doc, or only renames it when re-joining.
  Future<void> _writeMember(GroupSession session, String name) async {
    final ref = _members(session).doc(session.userId);
    final encName = await session.crypto.encryptJson(name);
    final existing = await ref.get();
    if (existing.exists) {
      await ref.update({'name': encName});
      return;
    }
    await ref.set({
      'name': encName,
      'role': Role.unassigned.name,
      'caught': false,
      'jokerUsed': false,
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<GameInfo?> watchGame(GroupSession session) => _game(session)
      .snapshots()
      .asyncMap((snap) async {
        final data = snap.data();
        if (data == null) return null;
        final settingsJson = await session.crypto.decryptJson(
          data['settings'] as String,
        );
        var settings = GameSettings.fromJson(
          settingsJson! as Map<String, Object?>,
        );
        final areaEnc = data['area'] as String?;
        if (areaEnc != null) {
          final areaJson = await session.crypto.decryptJson(areaEnc);
          settings = settings.copyWith(
            area: [
              for (final p in areaJson! as List<Object?>)
                GeoPoint.fromJson(p! as Map<String, Object?>),
            ],
          );
        }
        return GameInfo(
          adminId: data['adminUid'] as String,
          status: GameStatus.values.byName(data['status'] as String),
          settings: settings,
          startAt: (data['startAt'] as Timestamp?)?.toDate(),
        );
      });

  @override
  Stream<List<Member>> watchMembers(GroupSession session) => _members(session)
      .orderBy('joinedAt')
      .snapshots()
      .asyncMap(
        (query) => Future.wait([
          for (final doc in query.docs) _decodeMember(session, doc),
        ]),
      );

  Future<Member> _decodeMember(
    GroupSession session,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    return Member(
      id: doc.id,
      name: await session.crypto.decryptJson(data['name'] as String) as String,
      role: Role.values.byName(data['role'] as String),
      caught: data['caught'] as bool? ?? false,
      jokerUsed: data['jokerUsed'] as bool? ?? false,
      playerJokerUsed: data['playerJokerUsed'] as bool? ?? false,
    );
  }

  /// The play area is stored separately from the other settings so every
  /// member may edit it (R-SET-10) while the rest stays host-only.
  Future<Map<String, Object?>> _encodeSettings(
    GroupSession session,
    GameSettings settings, {
    bool withArea = false,
  }) async => {
    'settings': await session.crypto.encryptJson(
      settings.copyWith(area: const []).toJson(),
    ),
    if (withArea) 'area': await _encodeArea(session, settings.area),
  };

  Future<String> _encodeArea(GroupSession session, List<GeoPoint> area) =>
      session.crypto.encryptJson([for (final p in area) p.toJson()]);

  @override
  Future<void> updateArea(GroupSession session, List<GeoPoint> area) async {
    await _game(session).update({
      'area': await _encodeArea(session, area),
      'expiresAt': _newExpiry(),
    });
  }

  @override
  Future<void> updateSettings(
    GroupSession session,
    GameSettings settings,
  ) async {
    await _game(session).update({
      ...await _encodeSettings(session, settings),
      'expiresAt': _newExpiry(),
    });
  }

  @override
  Future<void> setRoles(GroupSession session, List<Member> members) async {
    final batch = _db.batch();
    for (final m in members) {
      batch.update(_members(session).doc(m.id), {'role': m.role.name});
    }
    await batch.commit();
  }

  @override
  Future<void> removeMember(GroupSession session, String memberId) =>
      _members(session).doc(memberId).delete();

  @override
  Future<void> startGame(GroupSession session) async {
    // Clear leftovers of an interrupted clean-up so rounds never mix.
    await _deleteRoundData(session);
    await _game(session).update({
      'status': GameStatus.running.name,
      'startAt': FieldValue.serverTimestamp(),
      'expiresAt': _newExpiry(),
    });
  }

  @override
  Future<void> recordCatch(GroupSession session, CatchRecord record) async {
    final batch = _db.batch()
      ..set(_game(session).collection('events').doc(), {
        'type': 'catch',
        'createdAt': FieldValue.serverTimestamp(),
        'data': await session.crypto.encryptJson(record.toJson()),
      })
      ..update(_members(session).doc(record.playerId), {'caught': true});
    await batch.commit();
  }

  @override
  Stream<List<CatchRecord>> watchCatches(GroupSession session) =>
      _game(session)
          .collection('events')
          .where('type', isEqualTo: 'catch')
          .snapshots()
          .asyncMap(
            (snap) => Future.wait([
              for (final doc in snap.docs)
                session.crypto
                    .decryptJson(doc.data()['data'] as String)
                    .then(
                      (json) =>
                          CatchRecord.fromJson(json! as Map<String, Object?>),
                    ),
            ]),
          );

  @override
  Future<void> endRound(GroupSession session) async {
    // History first: if anything below fails, the summary is not lost.
    // Then back to the lobby: only then the rules let the host read (and so
    // delete) the round data. Leftovers are also cleared on the next start.
    await _saveSummary(session);
    final members = await _members(session).get();
    final batch = _db.batch();
    for (final doc in members.docs) {
      batch.update(doc.reference, {
        'caught': false,
        'jokerUsed': false,
        'playerJokerUsed': false,
      });
    }
    batch.update(_game(session), {
      'status': GameStatus.lobby.name,
      'startAt': null,
      'expiresAt': _newExpiry(),
    });
    await batch.commit();
    await _deleteRoundData(session);
  }

  Future<void> _saveSummary(GroupSession session) async {
    final game = (await _game(session).get()).data()!;
    final endedAt = _now();
    final startedAt = (game['startAt'] as Timestamp?)?.toDate() ?? endedAt;
    final settingsJson = await session.crypto.decryptJson(
      game['settings'] as String,
    );
    final settings = GameSettings.fromJson(
      settingsJson! as Map<String, Object?>,
    );
    final members = await Future.wait([
      for (final doc in (await _members(session).get()).docs)
        _decodeMember(session, doc),
    ]);
    final events = await _game(session)
        .collection('events')
        .where('type', isEqualTo: 'catch')
        .get();
    final catches = await Future.wait([
      for (final doc in events.docs)
        session.crypto
            .decryptJson(doc.data()['data'] as String)
            .then(
              (json) => CatchRecord.fromJson(json! as Map<String, Object?>),
            ),
    ]);
    final history = _game(session).collection('history');
    final round = (await history.count().get()).count! + 1;
    final summary = RoundSummary.build(
      round: round,
      startedAt: startedAt,
      endedAt: endedAt,
      members: members,
      catches: catches,
      plannedDuration: settings.duration,
    );
    await history.add({
      'endedAt': Timestamp.fromDate(endedAt),
      'data': await session.crypto.encryptJson(summary.toJson()),
    });
  }

  @override
  Stream<List<RoundSummary>> watchHistory(GroupSession session) =>
      _game(session)
          .collection('history')
          .orderBy('endedAt', descending: true)
          .snapshots()
          .asyncMap(
            (query) => Future.wait([
              for (final doc in query.docs)
                session.crypto
                    .decryptJson(doc.data()['data'] as String)
                    .then(
                      (json) =>
                          RoundSummary.fromJson(json! as Map<String, Object?>),
                    ),
            ]),
          );

  @override
  Future<void> deleteGame(GroupSession session) async {
    // Round data is only readable for the host once no round is running
    // (security rules), so stop a running round first.
    final game = (await _game(session).get()).data();
    if (game?['status'] == GameStatus.running.name &&
        game?['adminUid'] == session.userId) {
      await _game(session)
          .update({'status': GameStatus.lobby.name, 'expiresAt': _newExpiry()});
    }
    await _deleteRoundData(session);
    await _deleteAll(
      (await _game(
        session,
      ).collection('history').get()).docs.map((d) => d.reference),
    );
    // Own member doc last: until then the rules still see us as a member.
    await _deleteAll(
      (await _members(session).get()).docs
          .where((d) => d.id != session.userId)
          .map((d) => d.reference),
    );
    await _members(session).doc(session.userId).delete();
    // Group doc last: the rules read it to authorize all deletes above.
    await _game(session).delete();
  }

  @override
  Future<bool> checkIn(GroupSession session) async {
    final snap = await _game(session).get();
    final data = snap.data();
    if (data == null) return false;
    final expiresAt = (data['expiresAt'] as Timestamp).toDate();
    if (!expiresAt.isAfter(_now())) {
      await deleteGame(session);
      return false;
    }
    // Extend at most once a day per group to keep writes low.
    if (expiresAt.isBefore(_now().add(groupLifetime - touchInterval))) {
      await _game(session).update({'expiresAt': _newExpiry()});
    }
    return true;
  }

  Future<void> _deleteRoundData(GroupSession session) async {
    for (final name in roundCollections) {
      final docs = await _game(session).collection(name).get();
      await _deleteAll(docs.docs.map((d) => d.reference));
    }
  }

  Future<void> _deleteAll(Iterable<DocumentReference<Object?>> refs) async {
    final list = refs.toList();
    for (var i = 0; i < list.length; i += _batchSize) {
      final batch = _db.batch();
      for (final ref in list.skip(i).take(_batchSize)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }
}
