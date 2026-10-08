import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/core/schedule/speedhunt.dart';
import 'package:manhunt/data/firestore_game_repository.dart';
import 'package:manhunt/data/firestore_round_repository.dart';
import 'package:manhunt/data/game_repository.dart';

import '../helpers.dart';

void main() {
  const code = 'ABCDE-FGHJK';
  late FakeFirebaseFirestore db;
  late FirestoreGameRepository games;
  late FirestoreRoundRepository rounds;
  late GroupSession hunter;
  late GroupSession kim;
  late GroupSession sam;
  final t0 = DateTime.utc(2026, 10, 4, 14, 20);

  LocationFix fix(double lat, [int minute = 0]) => LocationFix(
    point: GeoPoint(lat, 13.4),
    at: t0.add(Duration(minutes: minute)),
    accuracyM: 5,
  );

  setUp(() async {
    db = FakeFirebaseFirestore();
    games = FirestoreGameRepository(db);
    rounds = FirestoreRoundRepository(db);
    hunter = await testSession(code, 'hunter');
    kim = await testSession(code, 'kim');
    sam = await testSession(code, 'sam');
    await games.createGame(
      hunter,
      name: 'Alex',
      settings: const GameSettings(),
    );
    await games.joinGame(kim, name: 'Kim');
    await games.joinGame(sam, name: 'Sam');
  });

  group('pings (R-PING-01, R-HUNT-03, R-PLAY-01)', () {
    final slot = PingSlot(id: 'regular_1', kind: PingKind.regular, at: t0);

    test('hunters see all pings, players only their own', () async {
      await rounds.sendPing(kim, slot, fix(52.5));
      await rounds.sendPing(sam, slot, fix(52.6));

      final all = await rounds.watchAllPings(hunter).first;
      expect(all.map((p) => p.playerId).toSet(), {'kim', 'sam'});

      final mine = await rounds.watchMyPings(kim).first;
      expect(mine.single.playerId, 'kim');
      expect(mine.single.fix.point, const GeoPoint(52.5, 13.4));
      expect(mine.single.kind, PingKind.regular);
    });

    test('shared pings: all regular pings, no speedhunt pings (R-PLAY-05, '
        'R-SPEED-04)', () async {
      await rounds.sendPing(kim, slot, fix(52.5));
      await rounds.sendPing(sam, slot, fix(52.6));
      await rounds.sendPing(
        sam,
        PingSlot(id: 'speedhunt_1_1', kind: PingKind.speedhunt, at: t0),
        fix(52.7),
      );
      final shared = await rounds.watchSharedPings(kim).first;
      expect(shared.map((p) => p.playerId).toSet(), {'kim', 'sam'});
      expect(shared.every((p) => p.kind == PingKind.regular), isTrue);
    });

    test('same slot is stored once (idempotent)', () async {
      await rounds.sendPing(kim, slot, fix(52.5));
      await rounds.sendPing(kim, slot, fix(52.5));
      expect(await rounds.watchAllPings(hunter).first, hasLength(1));
    });

    test('locations are encrypted', () async {
      await rounds.sendPing(kim, slot, fix(52.123456));
      expect(db.dump(), isNot(contains('52.123456')));
    });

    test('pings are deleted when the round ends (R-PRIV-03)', () async {
      await games.startGame(hunter);
      await rounds.sendPing(kim, slot, fix(52.5));
      await rounds.updateHunterLocation(hunter, fix(52.4));
      await games.endRound(hunter);
      expect(await rounds.watchAllPings(hunter).first, isEmpty);
      expect(await rounds.watchHunterLocations(hunter).first, isEmpty);
    });
  });

  group('hunter positions & joker (R-HUNT-02, R-PLAY-02)', () {
    test('live position is overwritten, not accumulated', () async {
      await rounds.updateHunterLocation(hunter, fix(52.4));
      await rounds.updateHunterLocation(hunter, fix(52.41, 1));
      final locs = await rounds.watchHunterLocations(hunter).first;
      expect(locs.keys, ['hunter']);
      expect(locs['hunter']!.point.lat, 52.41);
    });

    test('joker reveals hunters once and is marked as used', () async {
      await rounds.updateHunterLocation(hunter, fix(52.4));
      final revealed = await rounds.useJoker(kim);
      expect(revealed['hunter']!.point.lat, 52.4);
      final me = (await games.watchMembers(kim).first).firstWhere(
        (m) => m.id == 'kim',
      );
      expect(me.jokerUsed, isTrue);
    });
  });

  group('player joker (R-PLAY-03)', () {
    test('request marks the joker, answers reach only the requester', () async {
      final requestId = await rounds.requestPlayerPositions(kim);
      final kimMember = (await games.watchMembers(kim).first).firstWhere(
        (m) => m.id == 'kim',
      );
      expect(kimMember.playerJokerUsed, isTrue);

      final request = (await rounds.watchJokerRequests(sam).first).single;
      expect(request.id, requestId);
      expect(request.requesterId, 'kim');
      await rounds.answerJokerRequest(sam, request, fix(52.7123456));

      final answers = await rounds.watchJokerAnswers(kim, requestId).first;
      expect(answers['sam']!.point.lat, 52.7123456);
      expect(await rounds.watchJokerAnswers(sam, requestId).first, isEmpty);
      expect(db.dump(), isNot(contains('52.7123456')));
    });

    test('round end deletes requests/answers and resets the joker', () async {
      await games.startGame(hunter);
      final requestId = await rounds.requestPlayerPositions(kim);
      final request = (await rounds.watchJokerRequests(sam).first).single;
      await rounds.answerJokerRequest(sam, request, fix(52.7));
      await games.endRound(hunter);

      expect(await rounds.watchJokerRequests(sam).first, isEmpty);
      expect(await rounds.watchJokerAnswers(kim, requestId).first, isEmpty);
      final kimMember = (await games.watchMembers(kim).first).firstWhere(
        (m) => m.id == 'kim',
      );
      expect(kimMember.playerJokerUsed, isFalse);
    });
  });

  group('speedhunt (R-SPEED-02, R-SPEED-04, R-SPEED-05)', () {
    final sh = Speedhunt.fromSettings(
      targetId: 'kim',
      startedAt: t0,
      settings: const GameSettings(),
    );

    test('everyone sees that a speedhunt runs, but not the target', () async {
      await rounds.startSpeedhunt(hunter, sh);
      final public = await rounds.watchSpeedhunts(sam).first;
      expect(public.single.startedAt, t0);
      expect(public.single.pings, 3);
      expect(public.single.targetId, isEmpty);
      // The public event does not contain the target, not even encrypted.
      final events = await db
          .collection('games')
          .doc(hunter.groupId)
          .collection('events')
          .get();
      final decrypted = await hunter.crypto.decryptJson(
        events.docs.single.data()['data'] as String,
      );
      expect((decrypted! as Map).containsKey('targetId'), isFalse);
    });

    test('only the target learns it is targeted', () async {
      await rounds.startSpeedhunt(hunter, sh);
      final onKim = await rounds.watchSpeedhuntsOnMe(kim).first;
      expect(onKim.single.targetId, 'kim');
      expect(onKim.single.pingTimes(), sh.pingTimes());
      expect(await rounds.watchSpeedhuntsOnMe(sam).first, isEmpty);
    });

    test('a catch of the target ends the speedhunt for everyone '
        '(R-SPEED-10)', () async {
      await rounds.startSpeedhunt(hunter, sh);
      // Hunter and the caught player themself can find the speedhunt.
      final onKim = await rounds.speedhuntsOn(hunter, 'kim');
      expect(onKim.single.targetId, 'kim');
      expect((await rounds.speedhuntsOn(kim, 'kim')).single.startedAt, t0);
      expect(await rounds.speedhuntsOn(hunter, 'sam'), isEmpty);

      final caughtAt = t0.add(const Duration(minutes: 7));
      await games.recordCatch(
        hunter,
        CatchRecord(
          playerId: 'kim',
          at: caughtAt,
          endsSpeedhunt: speedhuntEndedByCatch(onKim, caughtAt),
        ),
      );
      final ended = applyCatches(
        await rounds.watchSpeedhunts(sam).first,
        await games.watchCatches(sam).first,
      );
      expect(ended.single.endedAt, caughtAt);
      expect(ended.single.pingTimes(), sh.pingTimes().take(2));
    });
  });

  group('catches (R-CATCH-01, R-CATCH-02, R-NOTIF-02)', () {
    test('catch marks the player and is visible to everyone', () async {
      await games.recordCatch(hunter, CatchRecord(playerId: 'kim', at: t0));
      final kimMember = (await games.watchMembers(sam).first).firstWhere(
        (m) => m.id == 'kim',
      );
      expect(kimMember.caught, isTrue);
      final catches = await games.watchCatches(sam).first;
      expect(catches.single.playerId, 'kim');
    });
  });
}
