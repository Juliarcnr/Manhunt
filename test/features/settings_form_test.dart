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
      for (final key in [
        'jokerSwitch',
        'playerJokerSwitch',
        'sharedPingsSwitch',
      ]) {
        final tile = tester.widget<SwitchListTile>(find.byKey(Key(key)));
        expect(tile.onChanged, isNull);
      }
    });
  });

  group('player joker or pings to all players (R-SET-15)', () {
    testWidgets('switching one on switches the other off', (tester) async {
      var settings = const GameSettings();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: SettingsForm(
                  settings: settings,
                  onChanged: (s) => setState(() => settings = s),
                ),
              ),
            ),
          ),
        ),
      );
      bool on(String key) =>
          tester.widget<SwitchListTile>(find.byKey(Key(key))).value;
      expect(find.text('Reguläre Pings an alle Spieler'), findsOneWidget);
      expect(on('playerJokerSwitch'), isTrue);
      expect(on('sharedPingsSwitch'), isFalse);

      await tester.ensureVisible(find.byKey(const Key('sharedPingsSwitch')));
      await tester.tap(find.byKey(const Key('sharedPingsSwitch')));
      await tester.pumpAndSettle();
      expect(settings.sharedPings, isTrue);
      expect(on('playerJokerSwitch'), isFalse);

      await tester.tap(find.byKey(const Key('playerJokerSwitch')));
      await tester.pumpAndSettle();
      expect(settings.playerJokerAvailable, isTrue);
      expect(on('sharedPingsSwitch'), isFalse);
    });
  });

  group('anonymous players (R-SET-16)', () {
    testWidgets('on by default, can be switched off', (tester) async {
      var settings = const GameSettings();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: SettingsForm(
                  settings: settings,
                  onChanged: (s) => setState(() => settings = s),
                ),
              ),
            ),
          ),
        ),
      );
      const key = Key('anonymousPlayersSwitch');
      expect(find.text('Anonyme Spieler'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isTrue);
      await tester.ensureVisible(find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(settings.anonymousPlayers, isFalse);
      expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isFalse);
    });
  });

  group('live location outside the area (R-SET-17)', () {
    testWidgets('on by default, can be switched off', (tester) async {
      var settings = const GameSettings();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: SettingsForm(
                  settings: settings,
                  onChanged: (s) => setState(() => settings = s),
                ),
              ),
            ),
          ),
        ),
      );
      const key = Key('outsideLiveLocationSwitch');
      expect(
        find.text('Live-Standort beim Verlassen des Spielfelds'),
        findsOneWidget,
      );
      expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isTrue);
      await tester.ensureVisible(find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(settings.outsideLiveLocation, isFalse);
      expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isFalse);
    });
  });
}
