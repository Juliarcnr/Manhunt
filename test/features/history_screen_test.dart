import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/history/round_summary.dart';
import 'package:manhunt/features/history/history_screen.dart';
import 'package:manhunt/l10n/app_localizations.dart';
import 'package:manhunt/state/providers.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<RoundSummary> rounds, {
    Locale locale = const Locale('de'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyProvider.overrideWith((ref) => Stream.value(rounds)),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HistoryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final start = DateTime.utc(2026, 10, 4, 14);

  testWidgets('empty history explains when rounds appear (R-HIST-03)', (
    tester,
  ) async {
    await pump(tester, []);
    expect(find.textContaining('Noch keine beendeten Runden'), findsOneWidget);
  });

  testWidgets('round shows teams, catches with time and hunter, survivors '
      '(R-HIST-01, R-HIST-02)', (tester) async {
    await pump(tester, [
      RoundSummary(
        round: 3,
        startedAt: start,
        endedAt: start.add(const Duration(hours: 3, minutes: 5)),
        hunters: const ['Alex'],
        players: const ['Kim', 'Sam', 'Lou'],
        catches: const [
          CatchEntry(player: 'Kim', after: Duration(minutes: 72)),
          CatchEntry(player: 'Sam', after: Duration(minutes: 140)),
        ],
      ),
    ]);
    expect(find.text('Runde 3'), findsOneWidget);
    expect(find.text('3 h 5 min'), findsOneWidget);
    expect(find.text('1:12 h'), findsOneWidget);
    // Who caught is not shown (R-CATCH-03).
    expect(find.textContaining('von '), findsNothing);
    expect(find.textContaining('Lou'), findsWidgets);
    expect(find.textContaining('Nicht gefangen'), findsOneWidget);
  });

  testWidgets('aborted rounds are marked (R-GAME-07)', (tester) async {
    await pump(tester, [
      RoundSummary(
        round: 2,
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 40)),
        hunters: const ['Alex'],
        players: const ['Kim'],
        catches: const [],
        abortedEarly: true,
      ),
    ]);
    expect(find.text('vorzeitig abgebrochen'), findsOneWidget);
  });

  testWidgets('all caught is celebrated', (tester) async {
    await pump(tester, [
      RoundSummary(
        round: 1,
        startedAt: start,
        endedAt: start.add(const Duration(hours: 1)),
        hunters: const ['Alex'],
        players: const ['Kim'],
        catches: const [CatchEntry(player: 'Kim', after: Duration(minutes: 5))],
      ),
    ], locale: const Locale('en'));
    expect(find.text('All players caught!'), findsOneWidget);
  });
}
