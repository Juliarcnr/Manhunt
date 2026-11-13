import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/bots/bot_plan.dart';
import 'package:manhunt/core/bots/bot_walk.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/data/firestore_game_repository.dart';
import 'package:manhunt/data/firestore_round_repository.dart';
import 'package:manhunt/data/game_repository.dart';
import 'package:manhunt/data/location_service.dart';
import 'package:manhunt/state/bots.dart';

import '../core/bots_test.dart' show metres;
import '../helpers.dart';

void main() {
  const code = 'ABCDE-FGHJK';
  const hostPhone = GeoPoint(52.520, 13.405);
  const kimPhone = GeoPoint(52.522, 13.410);
  const area = [
    GeoPoint(52.50, 13.38),
    GeoPoint(52.50, 13.43),
    GeoPoint(52.54, 13.43),
    GeoPoint(52.54, 13.38),
  ];

  late FakeFirebaseFirestore db;
  late FirestoreGameRepository games;
  late GroupSession host;
  late GroupSession kim;
  late BotLobbySync hostSync;
  late BotLobbySync kimSync;
  late FakeBotBackend hostBots;
  late FakeBotBackend kimBots;

  Future<void> flush() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<List<Member>> members() => games.watchMembers(host).first;
  Future<GameInfo> game() async => (await games.watchGame(host).first)!;

  /// Both phones sync a few times, as the member list changes.
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      final g = await game();
      final m = await members();
      await hostSync.update(g, m);
      await kimSync.update(g, m);
    }
  }

  Map<String, Role> bots(List<Member> members) => {
    for (final m in members)
      if (isBot(m)) m.name: m.role,
  };

  setUp(() async {
    db = FakeFirebaseFirestore();
    games = FirestoreGameRepository(db);
    host = await testSession(code, 'h');
    kim = await testSession(code, 'k');
    await games.createGame(
      host,
      name: 'Alex',
      settings: const GameSettings(botCount: 3, area: area),
    );
    await games.joinGame(kim, name: 'Kim');
    hostBots = FakeBotBackend(db, owner: 'h');
    kimBots = FakeBotBackend(db, owner: 'k');
    hostSync = BotLobbySync(session: host, games: games, backend: hostBots);
    kimSync = BotLobbySync(session: kim, games: games, backend: kimBots);
  });

  group('bots follow the settings in the lobby (R-BOT-02, R-BOT-03)', () {
    test('the host phone gets all bots, unassigned – whatever the roles of '
        'the people', () async {
      await settle();
      final all = await members();
      expect(bots(all), {
        '🤖 Adelgunde': Role.unassigned,
        '🤖 Stromius': Role.unassigned,
        '🤖 Pankratius': Role.unassigned,
      });
      expect(all.where(isBot).map((m) => m.id), everyElement(endsWith('-h')));
      expect(kimBots.opened, 0);

      // Kim plays, Alex leads: still all on the host's phone.
      await games.setRoles(host, [
        const Member(id: 'h', name: 'Alex', role: Role.gameMaster),
        const Member(id: 'k', name: 'Kim', role: Role.player),
      ]);
      await settle();
      expect(
        (await members()).where(isBot).map((m) => m.id),
        everyElement(endsWith('-h')),
      );
      expect(kimBots.opened, 0);
    });

    test('bots keep the roles the host gives them', () async {
      await settle();
      final all = await members();
      final ids = [for (final m in all.where(isBot)) m.id];
      await games.setRoles(host, [
        for (final (i, id) in ids.indexed)
          Member(id: id, name: '', role: i == 0 ? Role.hunter : Role.player),
      ]);
      await games.setRoles(host, [
        const Member(id: 'h', name: 'Alex', role: Role.player),
      ]);
      await settle();
      expect(
        bots(await members()).values,
        unorderedEquals([Role.hunter, Role.player, Role.player]),
      );
    });

    test('fewer wanted: the host removes some; off: all leave', () async {
      await settle();
      await games.updateSettings(
        host,
        const GameSettings(botCount: 1, area: area),
      );
      await settle();
      expect(bots(await members()), {'🤖 Adelgunde': Role.unassigned});

      await games.updateSettings(host, const GameSettings(area: area));
      await settle();
      expect(bots(await members()), isEmpty);
    });
  });

  group('bots play like phones of their own, around the host '
      '(R-BOT-04, R-BOT-05)', () {
    late DateTime now;
    late DateTime startAt;
    late BotSquad squad;
    late String hunterBot;
    late List<String> playerBots;

    BotSquad squadOf(
      GroupSession carrier,
      FakeBotBackend backend, {
      GeoPoint? tracked,
      GeoPoint? asked,
    }) {
      final s = BotSquad(
        session: carrier,
        backend: backend,
        anchor: () =>
            tracked == null ? null : LocationFix(point: tracked, at: now),
        hostPosition: () async =>
            asked == null ? null : LocationFix(point: asked, at: now),
        notice: const TrackingNotice(title: 't', text: 'x'),
        now: () => now,
      );
      addTearDown(s.dispose);
      return s;
    }

    Future<void> tickAll() async {
      for (final r in squad.runners.values) {
        await r.engine.tick();
      }
      await flush();
    }

    /// Bots: one hunter, two players; the host plays with [hostRole].
    Future<void> start({Role hostRole = Role.hunter}) async {
      await settle();
      final ids = [
        for (final m in await members())
          if (isBot(m)) m.id,
      ];
      hunterBot = ids.first;
      playerBots = ids.skip(1).toList();
      await games.setRoles(host, [
        Member(id: 'h', name: 'Alex', role: hostRole),
        const Member(id: 'k', name: 'Kim', role: Role.player),
        Member(id: hunterBot, name: '', role: Role.hunter),
        for (final id in playerBots)
          Member(id: id, name: '', role: Role.player),
      ]);
      await games.startGame(host);
      startAt = (await game()).startAt!;
      now = startAt.add(const Duration(minutes: 1));
    }

    Future<void> run(BotSquad s) async {
      squad = s;
      await s.update(await members());
      await flush();
    }

    test('the host runs all bots; other phones none', () async {
      await start();
      await run(squadOf(host, hostBots, tracked: hostPhone));
      final other = squadOf(kim, kimBots, tracked: kimPhone);
      await other.update(await members());
      await flush();
      expect(squad.runners.keys, unorderedEquals([hunterBot, ...playerBots]));
      expect(other.runners, isEmpty);
    });

    test('computer players ping near the host', () async {
      await start();
      await run(squadOf(host, hostBots, tracked: hostPhone));
      now = startAt.add(const Duration(minutes: 20));
      await tickAll();
      final pings = await FirestoreRoundRepository(db)
          .watchAllPings(host)
          .first;
      expect({for (final p in pings) p.playerId}, playerBots.toSet());
      for (final p in pings) {
        expect(p.slotId, 'regular_1');
        expect(
          metres(hostPhone, p.fix.point),
          lessThanOrEqualTo(botRadiusM + 0.5),
        );
      }
    });

    test('computer hunters share their live position near the host', () async {
      await start();
      await run(squadOf(host, hostBots, tracked: hostPhone));
      await tickAll();
      final live = await FirestoreRoundRepository(db)
          .watchHunterLocations(host)
          .first;
      expect(live.keys, [hunterBot]);
      expect(
        metres(hostPhone, live.values.single.point),
        lessThanOrEqualTo(botRadiusM + 0.5),
      );
    });

    test('a host who does not track (game master) still anchors the bots: '
        'its phone is asked for its position', () async {
      await start(hostRole: Role.gameMaster);
      await run(squadOf(host, hostBots, asked: hostPhone));
      await tickAll();
      final live = await FirestoreRoundRepository(db)
          .watchHunterLocations(host)
          .first;
      expect(live.keys, [hunterBot]);
      expect(
        metres(hostPhone, live.values.single.point),
        lessThanOrEqualTo(botRadiusM + 0.5),
      );
    });

    test('unassigned bots sit out', () async {
      await start();
      await games.setRoles(host, [
        Member(id: hunterBot, name: '', role: Role.unassigned),
      ]);
      await run(squadOf(host, hostBots, tracked: hostPhone));
      await tickAll();
      expect(squad.runners[hunterBot]!.engine.isTracking, isFalse);
      expect(squad.runners[playerBots.first]!.engine.isTracking, isTrue);
    });

    test('a caught computer player stops', () async {
      await start();
      await run(squadOf(host, hostBots, tracked: hostPhone));
      final id = playerBots.first;
      await games.recordCatch(host, CatchRecord(playerId: id, at: now));
      await flush();
      await tickAll();
      expect(squad.runners[id]!.engine.isTracking, isFalse);
      expect(squad.runners[playerBots.last]!.engine.isTracking, isTrue);
    });

    test('computer players answer the joker "player positions"', () async {
      await start();
      await run(squadOf(host, hostBots, tracked: hostPhone));
      await tickAll(); // first position
      final rounds = FirestoreRoundRepository(db);
      final request = await rounds.requestPlayerPositions(kim);
      await flush();
      await tickAll();
      final answers = await rounds.watchJokerAnswers(kim, request).first;
      expect(answers.keys, unorderedEquals(playerBots));
    });

    test('bots that left stop running', () async {
      await start();
      await run(squadOf(host, hostBots, tracked: hostPhone));
      final id = playerBots.first;
      await games.removeMember(host, id);
      await squad.update(await members());
      expect(squad.runners.keys, isNot(contains(id)));
    });
  });
}
