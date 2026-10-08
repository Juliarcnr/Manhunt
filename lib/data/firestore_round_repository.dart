import 'package:cloud_firestore/cloud_firestore.dart' hide GeoPoint;

import '../core/round/joker.dart';
import '../core/round/ping_schedule.dart';
import '../core/schedule/speedhunt.dart';
import 'game_repository.dart';
import 'round_repository.dart';

/// Firestore layout (all under `games/{groupId}`, deleted at round end):
/// - `pings/{uid}_{slotId}`: uid, kind, slot, createdAt, data (LocationFix)
/// - `hunterLocs/{uid}`: updatedAt, data (LocationFix)
/// - `events/{id}` type=speedhunt: createdAt, data (startedAt, pings, interval)
/// - `speedhuntTargets/{eventId}`: uid (target), createdAt
/// - `jokerRequests/{id}`: uid (requester), createdAt
/// - `jokerAnswers/{requestId}_{uid}`: request, requester, uid, createdAt, data
class FirestoreRoundRepository implements RoundRepository {
  FirestoreRoundRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _game(GroupSession s) =>
      _db.collection('games').doc(s.groupId);

  @override
  Future<void> sendPing(
    GroupSession session,
    PingSlot slot,
    LocationFix fix,
  ) async {
    await _game(session)
        .collection('pings')
        .doc('${session.userId}_${slot.id}')
        .set({
          'uid': session.userId,
          'kind': slot.kind.name,
          'slot': slot.id,
          'createdAt': FieldValue.serverTimestamp(),
          'data': await session.crypto.encryptJson(fix.toJson()),
        });
  }

  Stream<List<PingRecord>> _decodePings(
    GroupSession session,
    Query<Map<String, dynamic>> query,
  ) => query.snapshots().asyncMap(
    (snap) => Future.wait([
      for (final doc in snap.docs)
        session.crypto
            .decryptJson(doc.data()['data'] as String)
            .then(
              (json) => PingRecord(
                playerId: doc.data()['uid'] as String,
                kind: PingKind.values.byName(doc.data()['kind'] as String),
                slotId: doc.data()['slot'] as String?,
                fix: LocationFix.fromJson(json! as Map<String, Object?>),
              ),
            ),
    ]),
  );

  @override
  Stream<List<PingRecord>> watchAllPings(GroupSession session) =>
      _decodePings(session, _game(session).collection('pings'));

  @override
  Stream<List<PingRecord>> watchMyPings(GroupSession session) => _decodePings(
    session,
    // The uid filter is required by the security rules for players.
    _game(session).collection('pings').where('uid', isEqualTo: session.userId),
  );

  @override
  Stream<List<PingRecord>> watchSharedPings(GroupSession session) =>
      _decodePings(
        session,
        // The kind filter is required by the security rules for players.
        _game(session)
            .collection('pings')
            .where('kind', isEqualTo: PingKind.regular.name),
      );

  @override
  Future<void> updateHunterLocation(
    GroupSession session,
    LocationFix fix,
  ) async {
    await _game(session).collection('hunterLocs').doc(session.userId).set({
      'updatedAt': FieldValue.serverTimestamp(),
      'data': await session.crypto.encryptJson(fix.toJson()),
    });
  }

  Future<Map<String, LocationFix>> _decodeHunterLocs(
    GroupSession session,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async => {
    for (final doc in snap.docs)
      doc.id: LocationFix.fromJson(
        await session.crypto.decryptJson(doc.data()['data'] as String)
            as Map<String, Object?>,
      ),
  };

  @override
  Stream<Map<String, LocationFix>> watchHunterLocations(GroupSession session) =>
      _game(session)
          .collection('hunterLocs')
          .snapshots()
          .asyncMap((snap) => _decodeHunterLocs(session, snap));

  @override
  Future<Map<String, LocationFix>> useJoker(GroupSession session) async {
    // Marking the joker as used first unlocks reading hunterLocs for a short
    // window in the security rules.
    await _game(session)
        .collection('members')
        .doc(session.userId)
        .update({'jokerUsed': true, 'jokerAt': FieldValue.serverTimestamp()});
    final snap = await _game(session).collection('hunterLocs').get();
    return _decodeHunterLocs(session, snap);
  }

  @override
  Future<String> requestPlayerPositions(GroupSession session) async {
    final request = _game(session).collection('jokerRequests').doc();
    // One batch: the rules only accept a request together with marking the
    // joker as used (same server timestamp).
    final batch = _db.batch()
      ..update(_game(session).collection('members').doc(session.userId), {
        'playerJokerUsed': true,
        'playerJokerAt': FieldValue.serverTimestamp(),
      })
      ..set(request, {
        'uid': session.userId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    await batch.commit();
    return request.id;
  }

  @override
  Stream<List<JokerRequest>> watchJokerRequests(GroupSession session) =>
      _game(session)
          .collection('jokerRequests')
          .snapshots()
          .map(
            (snap) => [
              for (final doc in snap.docs)
                JokerRequest(
                  id: doc.id,
                  requesterId: doc.data()['uid'] as String,
                  at:
                      (doc.data()['createdAt'] as Timestamp?)?.toDate() ??
                      DateTime.now(),
                ),
            ],
          );

  @override
  Future<void> answerJokerRequest(
    GroupSession session,
    JokerRequest request,
    LocationFix fix,
  ) async {
    await _game(session)
        .collection('jokerAnswers')
        .doc('${request.id}_${session.userId}')
        .set({
          'request': request.id,
          'requester': request.requesterId,
          'uid': session.userId,
          'createdAt': FieldValue.serverTimestamp(),
          'data': await session.crypto.encryptJson(fix.toJson()),
        });
  }

  @override
  Stream<Map<String, LocationFix>> watchJokerAnswers(
    GroupSession session,
    String requestId,
  ) => _game(session)
      .collection('jokerAnswers')
      // The requester filter is required by the security rules.
      .where('requester', isEqualTo: session.userId)
      .where('request', isEqualTo: requestId)
      .snapshots()
      .asyncMap(
        (snap) async => {
          for (final doc in snap.docs)
            doc.data()['uid'] as String: LocationFix.fromJson(
              await session.crypto.decryptJson(doc.data()['data'] as String)
                  as Map<String, Object?>,
            ),
        },
      );

  @override
  Future<void> startSpeedhunt(GroupSession session, Speedhunt speedhunt) async {
    final event = _game(session).collection('events').doc();
    final public = speedhunt.toJson()..remove('targetId');
    final batch = _db.batch()
      ..set(event, {
        'type': 'speedhunt',
        'createdAt': FieldValue.serverTimestamp(),
        'data': await session.crypto.encryptJson(public),
      })
      ..set(_game(session).collection('speedhuntTargets').doc(event.id), {
        'uid': speedhunt.targetId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    await batch.commit();
  }

  Future<Speedhunt> _decodeSpeedhunt(
    GroupSession session,
    Map<String, dynamic> data, {
    String targetId = '',
  }) async {
    final json = await session.crypto.decryptJson(data['data'] as String);
    return Speedhunt.fromJson({
      ...json! as Map<String, Object?>,
      'targetId': targetId,
    });
  }

  @override
  Stream<List<Speedhunt>> watchSpeedhunts(GroupSession session) =>
      _game(session)
          .collection('events')
          .where('type', isEqualTo: 'speedhunt')
          .snapshots()
          .asyncMap(
            (snap) => Future.wait([
              for (final doc in snap.docs)
                _decodeSpeedhunt(session, doc.data()),
            ]),
          );

  @override
  Stream<List<Speedhunt>> watchSpeedhuntsOnMe(GroupSession session) =>
      _game(session)
          .collection('speedhuntTargets')
          .where('uid', isEqualTo: session.userId)
          .snapshots()
          .asyncMap((targets) async {
            final result = <Speedhunt>[];
            for (final t in targets.docs) {
              final event = await _game(session)
                  .collection('events')
                  .doc(t.id)
                  .get();
              final data = event.data();
              if (data == null) continue;
              result.add(
                await _decodeSpeedhunt(session, data, targetId: session.userId),
              );
            }
            return result;
          });
}
