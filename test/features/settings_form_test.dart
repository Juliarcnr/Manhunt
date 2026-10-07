import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/features/settings/settings_form.dart';
import 'package:manhunt/l10n/app_localizations.dart';

void main() {
  Future<void> pumpForm(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SettingsForm(
            settings: const GameSettings(),
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );

  group('speedhunt timing settings are explained (R-SET-11, R-SET-13)', () {
    testWidgets('both settings show a distinguishing hint', (tester) async {
      await pumpForm(tester);
      expect(find.text('Speedhunts erlaubt ab'), findsOneWidget);
      expect(
        find.textContaining('Ab Spielstart (inkl. Vorlauf)'),
        findsOneWidget,
      );
      expect(find.text('Verzögerung bis zum 1. Ping'), findsOneWidget);
      expect(find.textContaining('Auslösen eines Speedhunts'), findsOneWidget);
    });

    testWidgets('lock period comes before the per-speedhunt delay', (
      tester,
    ) async {
      await pumpForm(tester);
      final earliest = tester.getTopLeft(find.text('Speedhunts erlaubt ab'));
      final delay = tester.getTopLeft(find.text('Verzögerung bis zum 1. Ping'));
      expect(earliest.dy, lessThan(delay.dy));
    });
  });

  group('read-only form (R-SET-14)', () {
    testWidgets('without onChanged there are no controls to edit', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: SettingsForm(settings: GameSettings(), onChanged: null),
            ),
          ),
        ),
      );
      expect(find.byType(IconButton), findsNothing);
      expect(find.text('20 min'), findsOneWidget);
      for (final key in ['jokerSwitch', 'playerJokerSwitch']) {
        final tile = tester.widget<SwitchListTile>(find.byKey(Key(key)));
        expect(tile.onChanged, isNull);
      }
    });
  });
}
