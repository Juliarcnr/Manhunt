import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/features/game/start_countdown.dart';
import 'package:manhunt/l10n/app_localizations.dart';

void main() {
  group('countdown overlay over the map (R-START-05)', () {
    Future<void> pump(WidgetTester tester, int seconds) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StartCountdownOverlay(secondsLeft: seconds)),
      ),
    );

    double scale(WidgetTester tester) => tester
        .widget<Transform>(
          find
              .ancestor(
                of: find.byKey(const Key('startCountdownText')),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getMaxScaleOnAxis();

    String text(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('startCountdownText'))).data!;

    testWidgets('minutes as mm:ss, under a minute only seconds', (
      tester,
    ) async {
      await pump(tester, 150);
      expect(text(tester), '02:30');
      expect(find.text('DAS SPIEL STARTET IN'), findsOneWidget);
      await pump(tester, 42);
      expect(text(tester), '42');
    });

    testWidgets('no pulse before the last three seconds', (tester) async {
      await pump(tester, 5);
      await tester.pump(const Duration(milliseconds: 350));
      expect(scale(tester), 1);
      await pump(tester, 4);
      await tester.pump(const Duration(milliseconds: 350));
      expect(scale(tester), 1);
    });

    testWidgets('the last three seconds pulse', (tester) async {
      await pump(tester, 4);
      for (final s in [3, 2, 1]) {
        await pump(tester, s);
        await tester.pump(const Duration(milliseconds: 350));
        expect(scale(tester), greaterThan(1.2), reason: '$s');
        await tester.pump(const Duration(milliseconds: 400));
        expect(scale(tester), closeTo(1, 0.01), reason: '$s');
      }
    });

    testWidgets('at 0 "START" pulses once', (tester) async {
      await pump(tester, 1);
      await pump(tester, 0);
      expect(text(tester), 'START');
      await tester.pump(const Duration(milliseconds: 350));
      expect(scale(tester), greaterThan(1.4));
      await tester.pumpAndSettle();
      expect(scale(tester), closeTo(1, 0.01));
    });

    testWidgets('taps go through to the map', (tester) async {
      await pump(tester, 10);
      expect(
        find.ancestor(
          of: find.byKey(const Key('startCountdown')),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });
  });
}
