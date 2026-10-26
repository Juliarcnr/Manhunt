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
  const hunterPhone = GeoPoint(52.520, 13.405);
  const playerPhone = GeoPoint(52.522, 13.410);
  const area = [
    GeoPoint(52.50, 13.38),
    GeoPoint(52.50, 13.43),
    GeoPoint(52.54, 13.43),
    GeoPoint(52.54, 13.38),
  ];

  late FakeFirebaseFirestore db;
  late FirestoreGameRepository games;
  late GroupSession host; // human hunter
  late GroupSession kim; // human player
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
      settings: const GameSettings(botHunters: 1, botPlayers: 2, area: area),
    );
    await games.joinGame(kim, name: 'Kim');
    hostBots = FakeBotBackend(db, owner: 'h');
    kimBots = FakeBotBackend(db, owner: 'k');
    hostSync = BotLobbySync(session: host, games: games, backend: hostBots);
    kimSync = BotLobbySync(session: kim, games: games, backend: kimBots);
  });

  group('bots follow the settings in the lobby (R-BOT-02, R-BOT-03)', () {
    test('no bots while no human has a role', () async {
      await settle();
      expect(bots(await members()), isEmpty);
      expect(hostBots.opened + kimBots.opened, 0);
    });

    test('carriers add their bots, the host assigns the roles', () async {
      await games.setRoles(host, [
        const Member(id: 'h', name: 'Alex', role: Role.hunter),
        const Member(id: 'k', name: 'Kim', role: Role.player),
      ]);
      await settle();
      final all = await members();
      expect(bots(all), {
        '🤖 Hunter 1': Role.hunter,
        '🤖 Player 1': Role.player,
        '🤖 Player 2': Role.player,
      });
      final ids = {for (final m in all) m.name: m.id};
      expect(ids['🤖 Hunter 1'], endsWith('-h'));
      expect(ids['🤖 Player 1'], endsWith('-k'));
      expect(ids['🤖 Player 2'], endsWith('-k'));

      // Fewer computer players: the carrier removes one.
      await games.updateSettings(
        host,
        const GameSettings(botHunters: 1, botPlayers: 1, area: area),
      );
      await settle();
      expect(bots(await members()), {
        '🤖 Hunter 1': Role.hunter,
        '🤖 Player 1': Role.player,
      });

      // Roles swapped: the bots move to the other phone.
      await games.setRoles(host, [
        const Member(id: 'h', name: 'Alex', role: Role.player),
        const Member(id: 'k', name: 'Kim', role: Role.hunter),
      ]);
      await settle();
      final swapped = await members();
      expect(bots(swapped).values, unorderedEquals([Role.hunter, Role.player]));
      for (final m in swapped.where(isBot)) {
        expect(
          m.id,
          endsWith(botKindOf(m.name) == BotKind.hunter ? '-k' : '-h'),
        );
      }

      // Off again: all bots leave.
      await games.updateSettings(host, const GameSettings(area: area));
      await settle();
      expect(bots(await members()), isEmpty);
    });
  });

  group('bots play like phones of their own (R-BOT-04, R-BOT-05)', () {
    late DateTime now;
    late DateTime startAt;
    late BotSquad hunterSquad;
    late BotSquad playerSquad;

    BotSquad squad(GroupSession carrier, FakeBotBackend backend, GeoPoint at) {
      final s = BotSquad(
        session: carrier,
        backend: backend,
        anchor: () => LocationFix(point: at, at: now),
        notice: const TrackingNotice(title: 't', text: 'x'),
        now: () => now,
      );
      addTearDown(s.dispose);
      return s;
    }

    Future<void> tickAll() async {
      for (final s in [hunterSquad, playerSquad]) {
        for (final r in s.runners.values) {
          await r.engine.tick();
        }
      }
      await flush();
    }

    setUp(() async {
      await games.setRoles(host, [
        const Member(id: 'h', name: 'Alex', role: Role.hunter),
        const Member(id: 'k', name: 'Kim', role: Role.player),
      ]);
      await settle();
      await games.startGame(host);
      startAt = (await game()).startAt!;
      now = startAt.add(const Duration(minutes: 1));
      hunterSquad = squad(host, hostBots, hunterPhone);
      playerSquad = squad(kim, kimBots, playerPhone);
      final m = await members();
      await hunterSquad.update(m);
      await playerSquad.update(m);
      await flush();
    });

    test('each phone runs only its own bots', () {
      expect(hunterSquad.runners.keys, everyElement(endsWith('-h')));
      expect(hunterSquad.runners, hasLength(1));
      expect(playerSquad.runners.keys, everyElement(endsWith('-k')));
      expect(playerSquad.runners, hasLength(2));
    });

    test('computer players ping near the player phone', () async {
      now = startAt.add(const Duration(minutes: 20));
      await tickAll();
      final pings = await FirestoreRoundRepository(db)
          .watchAllPings(host)
          .first;
      expect({for (final p in pings) p.playerId}, playerSquad.runners.keys);
      for (final p in pings) {
        expect(p.slotId, 'regular_1');
        expect(
          metres(playerPhone, p.fix.point),
          lessThanOrEqualTo(botRadiusM + 0.5),
        );
      }
    });

    test(
      'computer hunters share their live position near the hunter phone',
      () async {
        await tickAll();
        final live = await FirestoreRoundRepository(db)
            .watchHunterLocations(host)
            .first;
        expect(live.keys, hunterSquad.runners.keys);
        expect(
          metres(hunterPhone, live.values.single.point),
          lessThanOrEqualTo(botRadiusM + 0.5),
        );
      },
    );

    test('a caught computer player stops', () async {
      final id = playerSquad.runners.keys.first;
      await games.recordCatch(host, CatchRecord(playerId: id, at: now));
      await flush();
      await tickAll();
      expect(playerSquad.runners[id]!.engine.isTracking, isFalse);
      expect(playerSquad.runners.values.last.engine.isTracking, isTrue);
    });

    test('computer players answer the joker "player positions"', () async {
      await tickAll(); // first position
      final rounds = FirestoreRoundRepository(db);
      final request = await rounds.requestPlayerPositions(kim);
      await flush();
      await tickAll();
      final answers = await rounds.watchJokerAnswers(kim, request).first;
      expect(answers.keys, unorderedEquals(playerSquad.runners.keys));
    });

    test('bots that left stop running', () async {
      final id = playerSquad.runners.keys.first;
      await games.removeMember(host, id);
      await playerSquad.update(await members());
      expect(playerSquad.runners.keys, isNot(contains(id)));
    });
  });
}
