import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/history/round_map.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/features/history/history_map_screen.dart';
import 'package:manhunt/features/history/history_screen.dart';
import 'package:manhunt/l10n/app_localizations.dart';
import 'package:manhunt/state/providers.dart';

void main() {
  final start = DateTime.utc(2026, 11, 1, 14);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));
  final sh = 'speedhunt_${at(50).millisecondsSinceEpoch}';
  PingRecord ping(String id, String slot, double lat, int minutes) =>
      PingRecord(
        playerId: id,
        kind: slot.startsWith('speedhunt')
            ? PingKind.speedhunt
            : PingKind.regular,
        slotId: slot,
        fix: LocationFix(point: GeoPoint(lat, 13.4), at: at(minutes)),
      );

  // Kim (p0) and Sam (p1), hunters Alex (h0) and Lou (h1); a speedhunt on
  // Sam at minute 50 with one ping; Kim caught at minute 30.
  final map = RoundMap(
    area: const [
      GeoPoint(52.50, 13.39),
      GeoPoint(52.50, 13.41),
      GeoPoint(52.52, 13.41),
    ],
    startedAt: start,
    endedAt: at(60),
    pingInterval: const Duration(minutes: 20),
    players: const ['Kim', 'Sam'],
    hunters: const ['Alex', 'Lou'],
    pings: [
      ping('p0', 'regular_1', 52.501, 20),
      ping('p1', 'regular_1', 52.502, 20),
      ping('p1', 'regular_2', 52.503, 40),
      ping('p1', '${sh}_1', 52.504, 50),
    ],
    hunterSnaps: [
      ping('h0', 'regular_1', 52.511, 20),
      ping('h0', 'regular_2', 52.512, 40),
      ping('h1', 'regular_2', 52.513, 40),
      ping('h0', '${sh}_1', 52.514, 50),
      ping('h1', '${sh}_1', 52.515, 50),
    ],
    lastHunters: {
      'h0': LocationFix(point: const GeoPoint(52.516, 13.4), at: at(59)),
    },
    endPlayers: {
      'p1': LocationFix(point: const GeoPoint(52.506, 13.4), at: at(60)),
    },
    catches: [CatchRecord(playerId: 'p0', at: at(30))],
    speedhunts: [
      RoundMapSpeedhunt(startedAt: at(50), pingTimes: [at(50)], targetId: 'p1'),
    ],
  );

  RoundSummary summary({bool hasMap = true}) => RoundSummary(
    id: 'r1',
    round: 4,
    startedAt: start,
    endedAt: at(60),
    hunters: const ['Alex', 'Lou'],
    players: const ['Kim', 'Sam'],
    catches: const [CatchEntry(player: 'Kim', after: Duration(minutes: 30))],
    hasMap: hasMap,
  );

  Future<void> pumpHistory(
    WidgetTester tester, {
    bool isHost = false,
    bool hasMap = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyProvider.overrideWith(
            (ref) => Stream.value([summary(hasMap: hasMap)]),
          ),
          roundMapProvider('r1').overrideWith((ref) async => map),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HistoryScreen(isHost: isHost),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMap(WidgetTester tester) async {
    await pumpHistory(tester);
    await tester.tap(find.byKey(const Key('showMap_4')));
    await tester.pumpAndSettle();
  }

  Finder chip(String id) => find.byKey(Key('filter_$id'));

  group('history: map and deleting (R-HIST-04, R-HIST-06)', () {
    testWidgets('members cannot delete rounds', (tester) async {
      await pumpHistory(tester);
      expect(find.byKey(const Key('roundMenu_4')), findsNothing);
    });

    testWidgets('rounds with a map can show it', (tester) async {
      await pumpHistory(tester);
      expect(find.text('Show map'), findsOneWidget);
    });

    testWidgets('older rounds without a map have no button', (tester) async {
      await pumpHistory(tester, hasMap: false);
      expect(find.text('Show map'), findsNothing);
    });

    testWidgets('the host deletes a round only after a warning', (
      tester,
    ) async {
      await pumpHistory(tester, isHost: true);
      await tester.tap(find.byKey(const Key('roundMenu_4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete round'));
      await tester.pumpAndSettle();
      expect(find.text('Delete round 4?'), findsOneWidget);
      expect(find.textContaining('deleted permanently'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete round 4?'), findsNothing);
    });
  });

  group('round map chips (R-HIST-04, R-HIST-05)', () {
    testWidgets('a chip per player, per hunter and per speedhunt', (
      tester,
    ) async {
      await openMap(tester);
      expect(find.text('Round 4'), findsOneWidget);
      for (final id in [
        'end',
        'lastPings',
        'player_p0',
        'player_p1',
        'hunter_h0',
        'hunter_h1',
        'speedhunt_p1_${at(50).millisecondsSinceEpoch}',
      ]) {
        expect(chip(id), findsOneWidget, reason: id);
      }
      // Everyone's position at the end (R-HIST-08) instead of the last pings.
      expect(find.byKey(const Key('endPlayer_p1')), findsOneWidget);
      expect(find.byKey(const Key('endHunter_h0')), findsOneWidget);
      expect(find.byKey(const Key('lastPing_p0')), findsNothing);

      await tester.tap(chip('end'));
      await tester.tap(chip('lastPings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('endPlayer_p1')), findsNothing);
      expect(find.byKey(const Key('endHunter_h0')), findsNothing);
      expect(find.byKey(const Key('lastPing_p0')), findsOneWidget);
      expect(find.byKey(const Key('lastPing_p1')), findsOneWidget);
    });

    testWidgets('a hunter chip cycles points → lines → off; player chips '
        'show no hunters', (tester) async {
      await openMap(tester);
      await tester.tap(chip('player_p1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_p1_2')), findsOneWidget);
      expect(find.byKey(const Key('hunterHistory_h0_1')), findsNothing);

      await tester.tap(chip('hunter_h0'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hunterHistory_h0_1')), findsOneWidget);
      expect(find.byKey(const Key('hunterHistory_h0_2')), findsOneWidget);
      expect(find.byKey(const Key('arrow_h0_0')), findsNothing);

      await tester.tap(chip('hunter_h0'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('arrow_h0_0')), findsOneWidget);

      await tester.tap(chip('hunter_h0'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hunterHistory_h0_1')), findsNothing);
    });

    testWidgets('a speedhunt chip shows the hunters at its ping times', (
      tester,
    ) async {
      await openMap(tester);
      final slot = '${sh}_1';
      expect(find.byKey(Key('speedhunt_p1_$slot')), findsOneWidget);
      expect(find.byKey(Key('hunterSnap_h0_$slot')), findsOneWidget);
      expect(find.byKey(Key('hunterSnap_h1_$slot')), findsOneWidget);

      final speedhuntChip = chip(
        'speedhunt_p1_${at(50).millisecondsSinceEpoch}',
      );
      await tester.ensureVisible(speedhuntChip);
      await tester.pumpAndSettle();
      await tester.tap(speedhuntChip);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('speedhunt_p1_$slot')), findsNothing);
      expect(find.byKey(Key('hunterSnap_h0_$slot')), findsNothing);
    });
  });

  group('round map timeline (R-HIST-07)', () {
    Future<void> openTimeline(WidgetTester tester) async {
      await openMap(tester);
      await tester.tap(find.byKey(const Key('historyViewTimeline')));
      await tester.pumpAndSettle();
    }

    String label(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('timelineLabel'))).data!;

    testWidgets('steps through the regular and ⚡ ping times', (tester) async {
      await openTimeline(tester);
      expect(chip('player_p0'), findsNothing);
      expect(find.byKey(const Key('timelineSlider')), findsOneWidget);
      expect(label(tester), startsWith('Ping 1 · '));
      // Everyone at the first ping; Lou sent no position then.
      expect(find.byKey(const Key('timelinePlayer_p0')), findsOneWidget);
      expect(find.byKey(const Key('timelinePlayer_p1')), findsOneWidget);
      expect(find.byKey(const Key('timelineHunter_h0')), findsOneWidget);
      expect(find.byKey(const Key('timelineHunter_h1')), findsNothing);

      // Kim was caught at minute 30: gone at the second ping.
      await tester.tap(find.byKey(const Key('timelineNext')));
      await tester.pumpAndSettle();
      expect(label(tester), startsWith('Ping 2 · '));
      expect(find.byKey(const Key('timelinePlayer_p0')), findsNothing);
      expect(find.byKey(const Key('timelinePlayer_p1')), findsOneWidget);
      expect(find.byKey(const Key('timelineHunter_h1')), findsOneWidget);

      // The speedhunt ping: only its target and the hunters.
      await tester.tap(find.byKey(const Key('timelineNext')));
      await tester.pumpAndSettle();
      expect(label(tester), startsWith('⚡1 Sam · '));
      expect(find.byKey(Key('speedhunt_p1_${sh}_1')), findsOneWidget);
      expect(find.byKey(const Key('timelineHunter_h0')), findsOneWidget);
      expect(find.byKey(const Key('timelineHunter_h1')), findsOneWidget);

      // Last: where everyone was at the end (R-HIST-08).
      await tester.tap(find.byKey(const Key('timelineNext')));
      await tester.pumpAndSettle();
      expect(label(tester), startsWith('End of game · '));
      expect(find.byKey(const Key('timelinePlayer_p1')), findsOneWidget);
      expect(find.byKey(const Key('timelinePlayer_p0')), findsNothing);
      expect(find.byKey(const Key('timelineHunter_h0')), findsOneWidget);
      expect(find.byKey(const Key('timelineHunter_h1')), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('timelineNext')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('timelineBack')));
      await tester.pumpAndSettle();
      expect(label(tester), startsWith('⚡1 Sam · '));
    });
  });
}
