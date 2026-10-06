import 'package:cloud_firestore/cloud_firestore.dart' hide GeoPoint;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/data/firestore_game_repository.dart';
import 'package:manhunt/data/game_repository.dart';

import '../helpers.dart';

void main() {
  const code = 'ABCDE-FGHJK';
  const area = [
    GeoPoint(52.50, 13.40),
    GeoPoint(52.50, 13.41),
    GeoPoint(52.51, 13.41),
  ];
  late FakeFirebaseFirestore db;
  late FirestoreGameRepository repo;
  late GroupSession admin;
  late GroupSession guest;
  late DateTime now;

  setUp(() async {
    db = FakeFirebaseFirestore();
    now = DateTime.utc(2026, 10, 4);
    repo = FirestoreGameRepository(db, now: () => now);
    admin = await testSession(code, 'admin');
    guest = await testSession(code, 'guest');
  });

  Future<void> createDefault() => repo.createGame(
    admin,
    name: 'Julia',
    settings: const GameSettings(hunterCount: 2),
  );

  DocumentReference<Map<String, dynamic>> gameDoc() =>
      db.collection('games').doc(admin.groupId);

  Future<DateTime> expiresAt() async =>
      ((await gameDoc().get()).data()!['expiresAt'] as Timestamp)
          .toDate()
          .toUtc();

  /// Simulates round data written during a game (phase 5).
  Future<void> addRoundData() async {
    for (final name in FirestoreGameRepository.roundCollections) {
      await gameDoc().collection(name).add({'data': 'encrypted-location'});
    }
  }

  Future<int> roundDocCount() async {
    var count = 0;
    for (final name in FirestoreGameRepository.roundCollections) {
      count += (await gameDoc().collection(name).get()).docs.length;
    }
    return count;
  }

  group('create & join (R-SET-01, R-LOBBY-01 … 03)', () {
    test('creator becomes admin and first member', () async {
      await createDefault();
      final game = await repo.watchGame(admin).first;
      expect(game!.adminId, 'admin');
      expect(game.status, GameStatus.lobby);
      expect(game.settings.hunterCount, 2);
      final members = await repo.watchMembers(admin).first;
      expect(members.single.name, 'Julia');
      expect(members.single.role, Role.unassigned);
    });

    test('guest joins with the same code', () async {
      await createDefault();
      await repo.joinGame(guest, name: 'Kim');
      final names = (await repo.watchMembers(guest).first).map((m) => m.name);
      expect(names, containsAll(['Julia', 'Kim']));
    });

    test('joining twice keeps one entry and updates the name', () async {
      await createDefault();
      await repo.joinGame(guest, name: 'Kim');
      await repo.joinGame(guest, name: 'Kimi');
      final members = await repo.watchMembers(guest).first;
      expect(members, hasLength(2));
      expect(members.map((m) => m.name), contains('Kimi'));
    });

    test('joining a running round is possible (R-LOBBY-07)', () async {
      await createDefault();
      await repo.startGame(admin);
      await repo.joinGame(guest, name: 'Kim');
      expect(await repo.watchMembers(admin).first, hasLength(2));
    });

    test('unknown code → GroupNotFoundException', () async {
      final other = await testSession('ZZZZZ-ZZZZZ', 'guest');
      expect(
        () => repo.joinGame(other, name: 'Kim'),
        throwsA(isA<GroupNotFoundException>()),
      );
    });
  });

  group('lobby actions (R-SET-08, R-LOBBY-04 … 06)', () {
    test('settings can be edited later', () async {
      await createDefault();
      await repo.updateSettings(
        admin,
        const GameSettings(pingInterval: Duration(minutes: 30)),
      );
      final game = await repo.watchGame(admin).first;
      expect(game!.settings.pingInterval, const Duration(minutes: 30));
    });

    test('any member can edit the play area (R-SET-10)', () async {
      await createDefault();
      await repo.joinGame(guest, name: 'Kim');
      await repo.updateArea(guest, area);
      final game = await repo.watchGame(admin).first;
      expect(game!.settings.area, area);
    });

    test('host settings do not overwrite the area edited by others', () async {
      await createDefault();
      await repo.updateArea(guest, area);
      // Host saves settings with a stale (empty) area.
      await repo.updateSettings(
        admin,
        const GameSettings(pingInterval: Duration(minutes: 30)),
      );
      final game = await repo.watchGame(admin).first;
      expect(game!.settings.area, area);
      expect(game.settings.pingInterval, const Duration(minutes: 30));
    });

    test('area given at creation is stored separately and encrypted', () async {
      await repo.createGame(
        admin,
        name: 'Julia',
        settings: const GameSettings(area: area),
      );
      final data = (await gameDoc().get()).data()!;
      expect(data['area'], isA<String>());
      expect(data.toString(), isNot(contains('52.5')));
      expect((await repo.watchGame(admin).first)!.settings.area, area);
    });

    test('roles are saved', () async {
      await createDefault();
      await repo.joinGame(guest, name: 'Kim');
      final members = await repo.watchMembers(admin).first;
      await repo.setRoles(admin, [
        for (final m in members)
          m.copyWith(role: m.id == 'admin' ? Role.hunter : Role.player),
      ]);
      final after = await repo.watchMembers(admin).first;
      expect(after.firstWhere((m) => m.id == 'admin').role, Role.hunter);
      expect(after.firstWhere((m) => m.id == 'guest').role, Role.player);
    });

    test('remove member', () async {
      await createDefault();
      await repo.joinGame(guest, name: 'Kim');
      await repo.removeMember(admin, 'guest');
      expect(await repo.watchMembers(admin).first, hasLength(1));
    });

    test('start sets status and start time', () async {
      await createDefault();
      await repo.startGame(admin);
      final game = await repo.watchGame(admin).first;
      expect(game!.status, GameStatus.running);
      expect(game.startAt, isNotNull);
    });
  });

  group('end round (R-GAME-06, R-PRIV-03)', () {
    test('deletes all round data, keeps group and members', () async {
      await createDefault();
      await repo.joinGame(guest, name: 'Kim');
      await repo.startGame(admin);
      await addRoundData();
      expect(
        await roundDocCount(),
        FirestoreGameRepository.roundCollections.length,
      );

      await repo.endRound(admin);

      expect(await roundDocCount(), 0);
      final game = await repo.watchGame(admin).first;
      expect(game!.status, GameStatus.lobby);
      expect(game.startAt, isNull);
      expect(await repo.watchMembers(admin).first, hasLength(2));
    });

    test('resets caught and joker, keeps roles for the next round', () async {
      await createDefault();
      await gameDoc().collection('members').doc('admin').update({
        'role': 'player',
        'caught': true,
        'jokerUsed': true,
      });
      await repo.endRound(admin);
      final me = (await repo.watchMembers(admin).first).single;
      expect(me.caught, isFalse);
      expect(me.jokerUsed, isFalse);
      expect(me.role, Role.player);
    });
  });

  group('history (R-HIST-01 … 03)', () {
    Future<void> playRound({required List<CatchRecord> catches}) async {
      final start = now;
      await repo.startGame(admin);
      // Fake Firestore stores serverTimestamp as real time; pin it.
      await gameDoc().update({'startAt': Timestamp.fromDate(start)});
      for (final c in catches) {
        await repo.recordCatch(admin, c);
      }
      now = start.add(const Duration(hours: 3, minutes: 5));
      await repo.endRound(admin);
    }

    setUp(() async {
      await createDefault();
      await repo.joinGame(guest, name: 'Kim');
      final members = await repo.watchMembers(admin).first;
      await repo.setRoles(admin, [
        for (final m in members)
          m.copyWith(role: m.id == 'admin' ? Role.hunter : Role.player),
      ]);
    });

    test('ending a round saves a summary with catches', () async {
      final start = now;
      await playRound(
        catches: [
          CatchRecord(
            playerId: 'guest',
            at: start.add(const Duration(minutes: 72)),
          ),
        ],
      );
      final history = await repo.watchHistory(admin).first;
      final round = history.single;
      expect(round.round, 1);
      expect(round.hunters, ['Julia']);
      expect(round.players, ['Kim']);
      expect(round.duration, const Duration(hours: 3, minutes: 5));
      expect(round.catches.single.player, 'Kim');
      expect(round.catches.single.after, const Duration(minutes: 72));
      expect(round.survivors, isEmpty);
      expect(round.abortedEarly, isFalse); // ended after the planned 3 h
    });

    test('history survives "end game", catch events do not', () async {
      await playRound(
        catches: [CatchRecord(playerId: 'guest', at: now)],
      );
      expect(await roundDocCount(), 0);
      expect(await repo.watchHistory(guest).first, hasLength(1));
    });

    test('rounds are numbered, newest first', () async {
      await playRound(catches: []);
      await playRound(catches: []);
      final history = await repo.watchHistory(admin).first;
      expect(history.map((r) => r.round), [2, 1]);
      expect(history.first.survivors, ['Kim']);
    });

    test('history is encrypted', () async {
      await playRound(catches: []);
      final docs = await gameDoc().collection('history').get();
      expect(docs.docs.single.data().toString(), isNot(contains('Kim')));
    });

    test('deleting the group deletes the history', () async {
      await playRound(catches: []);
      await repo.deleteGame(admin);
      expect((await gameDoc().collection('history').get()).docs, isEmpty);
    });
  });

  group('privacy & expiry (R-PRIV-02, R-PRIV-05)', () {
    test('names and settings are stored encrypted, not the code', () async {
      await createDefault();
      final dump = db.dump();
      expect(dump, isNot(contains('Julia')));
      expect(dump, isNot(contains('hunterCount')));
      expect(dump, isNot(contains('ABCDE')));
    });

    const lifetime = Duration(days: 180);

    test('host actions extend the lifetime to 180 days', () async {
      await createDefault();
      expect(await expiresAt(), now.add(lifetime));
      now = DateTime.utc(2026, 11, 1);
      await repo.startGame(admin);
      expect(await expiresAt(), now.add(lifetime));
      now = DateTime.utc(2026, 11, 2);
      await repo.endRound(admin);
      expect(await expiresAt(), now.add(lifetime));
    });

    test('opening the group (any member) extends the lifetime', () async {
      await createDefault();
      await repo.joinGame(guest, name: 'Kim');
      now = DateTime.utc(2027, 3, 1);
      expect(await repo.checkIn(guest), isTrue);
      expect(await expiresAt(), now.add(lifetime));
    });

    test('opening several times a day writes only once', () async {
      await createDefault();
      final first = await expiresAt();
      now = now.add(const Duration(hours: 20));
      await repo.checkIn(guest);
      expect(await expiresAt(), first);
      now = now.add(const Duration(hours: 5));
      await repo.checkIn(guest);
      expect(await expiresAt(), now.add(lifetime));
    });

    test('opening after 180 days of silence deletes everything', () async {
      await createDefault();
      await repo.joinGame(guest, name: 'Kim');
      await addRoundData();
      now = now.add(lifetime);
      expect(await repo.checkIn(guest), isFalse);
      expect(await repo.watchGame(admin).first, isNull);
      expect(await roundDocCount(), 0);
      expect((await gameDoc().collection('members').get()).docs, isEmpty);
    });

    test('a missing group is reported as gone', () async {
      expect(await repo.checkIn(guest), isFalse);
    });

    test(
      'deleting during a running round works (round stopped first)',
      () async {
        await createDefault();
        await repo.startGame(admin);
        await addRoundData();
        await repo.deleteGame(admin);
        expect(await repo.watchGame(admin).first, isNull);
        expect(await roundDocCount(), 0);
      },
    );

    test('start clears leftovers of an interrupted clean-up', () async {
      await createDefault();
      await addRoundData(); // e.g. app closed during "end game"
      await repo.startGame(admin);
      expect(await roundDocCount(), 0);
    });

    test('delete removes group, members and round data', () async {
      await createDefault();
      await repo.joinGame(guest, name: 'Kim');
      await addRoundData();
      await repo.deleteGame(admin);
      expect(await repo.watchGame(admin).first, isNull);
      expect(await roundDocCount(), 0);
      expect((await gameDoc().collection('members').get()).docs, isEmpty);
    });
  });

  group('group name & status (R-GROUPS-03, R-GROUPS-04)', () {
    test('name is stored encrypted and can be renamed', () async {
      await repo.createGame(
        admin,
        name: 'Julia',
        settings: defaultSettings,
        groupName: 'Friday crew',
      );
      final raw = (await gameDoc().get()).data()!['name'] as String;
      expect(raw, isNot(contains('Friday')));
      expect((await repo.watchGame(guest).first)!.name, 'Friday crew');

      now = now.add(const Duration(days: 10));
      await repo.renameGroup(admin, 'Night crew');
      expect((await repo.watchGame(guest).first)!.name, 'Night crew');
      expect(await expiresAt(), now.add(FirestoreGameRepository.groupLifetime));
    });

    test('groups without a name still load', () async {
      await createDefault();
      expect((await repo.watchGame(admin).first)!.name, isNull);
    });

    test('status by group id, without the key; null once deleted', () async {
      await createDefault();
      expect(await repo.watchStatus(admin.groupId).first, GameStatus.lobby);
      await repo.startGame(admin);
      expect(await repo.watchStatus(admin.groupId).first, GameStatus.running);
      await repo.deleteGame(admin);
      expect(await repo.watchStatus(admin.groupId).first, isNull);
    });
  });
}
