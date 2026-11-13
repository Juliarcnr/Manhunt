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

  group('pauses between speedhunts (R-SET-18, R-SET-19)', () {
    /// Editable form; returns the current settings.
    Future<GameSettings Function()> pumpEditable(WidgetTester tester) async {
      var settings = const GameSettings();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => SettingsForm(
                  settings: settings,
                  onChanged: (s) => setState(() => settings = s),
                ),
              ),
            ),
          ),
        ),
      );
      return () => settings;
    }

    Finder button(String tile, String tooltip) => find.descendant(
      of: find.byKey(Key(tile)),
      matching: find.byTooltip(tooltip),
    );

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('both 30 min by default, repeats allowed', (tester) async {
      await pumpEditable(tester);
      expect(find.text('Pause zwischen Speedhunts'), findsOneWidget);
      expect(find.text('Pause für dieselbe Person'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('speedhuntRepeatSwitch')),
            )
            .value,
        isTrue,
      );
    });

    testWidgets('the per-player pause cannot go below the general one', (
      tester,
    ) async {
      final current = await pumpEditable(tester);
      await tap(tester, button('speedhuntRepeatCooldown', '−'));
      expect(current().speedhuntRepeatCooldown, const Duration(minutes: 30));
      expect(find.textContaining('Verkürze zuerst diese'), findsOneWidget);

      // Lowering the general pause first makes room.
      await tap(tester, button('speedhuntCooldown', '−'));
      await tap(tester, button('speedhuntRepeatCooldown', '−'));
      expect(current().speedhuntCooldown, const Duration(minutes: 25));
      expect(current().speedhuntRepeatCooldown, const Duration(minutes: 25));
    });

    testWidgets('raising the general pause raises the per-player one', (
      tester,
    ) async {
      final current = await pumpEditable(tester);
      await tap(tester, button('speedhuntCooldown', '+'));
      expect(current().speedhuntCooldown, const Duration(minutes: 35));
      expect(current().speedhuntRepeatCooldown, const Duration(minutes: 35));
    });

    testWidgets('number of hunter jokers: 1 by default, 0 … 5 (R-SET-09)', (
      tester,
    ) async {
      final current = await pumpEditable(tester);
      const tile = 'hunterJokersStepper';
      expect(
        find.descendant(
          of: find.byKey(const Key(tile)),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('0 = aus'), findsOneWidget);
      await tap(tester, button(tile, '−'));
      expect(current().hunterJokers, 0);
      expect(current().jokerEnabled, isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: button(tile, '−'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      for (var i = 0; i < GameSettings.maxHunterJokers; i++) {
        await tap(tester, button(tile, '+'));
      }
      expect(current().hunterJokers, 5);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: button(tile, '+'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('without repeats there is no per-player pause', (tester) async {
      final current = await pumpEditable(tester);
      await tap(tester, find.byKey(const Key('speedhuntRepeatSwitch')));
      expect(current().speedhuntRepeatTarget, isFalse);
      expect(find.byKey(const Key('speedhuntRepeatCooldown')), findsNothing);
      expect(
        find.textContaining('Ziel des letzten Speedhunts'),
        findsOneWidget,
      );
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
      for (final key in ['playerJokerSwitch', 'sharedPingsSwitch']) {
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
      expect(find.text('Reguläre Pings an alle Spieler:innen'), findsOneWidget);
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
      expect(find.text('Anonyme Spieler:innen'), findsOneWidget);
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

  group('number of computer members, debug only (R-BOT-01, R-BOT-02)', () {
    Future<GameSettings Function()> pump(
      WidgetTester tester, {
      required bool showBots,
    }) async {
      var settings = const GameSettings();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => SettingsForm(
                  settings: settings,
                  onChanged: (s) => setState(() => settings = s),
                  showBots: showBots,
                ),
              ),
            ),
          ),
        ),
      );
      return () => settings;
    }

    testWidgets('hidden unless enabled', (tester) async {
      await pump(tester, showBots: false);
      expect(find.byKey(const Key('botSettings')), findsNothing);
      expect(find.text('Computer-Mitspieler:innen'), findsNothing);
    });

    testWidgets('only one setting: the number of computer players', (
      tester,
    ) async {
      final settings = await pump(tester, showBots: true);
      expect(find.text('Computer-Hunter:innen'), findsNothing);
      Finder plus(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
        matching: find.byTooltip('+'),
      );
      await tester.ensureVisible(find.text('Computer-Mitspieler:innen'));
      await tester.tap(plus('Computer-Mitspieler:innen'));
      await tester.pump();
      await tester.tap(plus('Computer-Mitspieler:innen'));
      await tester.pump();
      expect(settings().botCount, 2);
    });
  });

  group('skip the countdown when testing (R-BOT-09)', () {
    Future<GameSettings Function()> pump(
      WidgetTester tester, {
      required bool testing,
    }) async {
      var settings = const GameSettings();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => SettingsForm(
                  settings: settings,
                  onChanged: (s) => setState(() => settings = s),
                  showBots: testing,
                ),
              ),
            ),
          ),
        ),
      );
      return () => settings;
    }

    const key = Key('skipCountdownSwitch');

    testWidgets('hidden in normal builds', (tester) async {
      await pump(tester, testing: false);
      expect(find.byKey(key), findsNothing);
    });

    testWidgets('below the start time, off by default, can be switched on', (
      tester,
    ) async {
      final settings = await pump(tester, testing: true);
      expect(find.text('Countdown überspringen'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(key)).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('startTimeTile'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(key)).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('durationStepper'))).dy,
        ),
      );
      expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isFalse);
      await tester.tap(find.byKey(key));
      await tester.pump();
      expect(settings().skipCountdown, isTrue);
    });
  });

  group('very short rounds when testing (R-BOT-08)', () {
    Future<GameSettings Function()> pump(
      WidgetTester tester, {
      required bool testing,
      GameSettings initial = const GameSettings(
        duration: Duration(minutes: 30),
      ),
    }) async {
      var settings = initial;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => SettingsForm(
                  settings: settings,
                  onChanged: (s) => setState(() => settings = s),
                  showBots: testing,
                ),
              ),
            ),
          ),
        ),
      );
      return () => settings;
    }

    Finder button(String stepper, String tooltip) => find.ancestor(
      of: find.descendant(
        of: find.byKey(Key(stepper)),
        matching: find.byTooltip(tooltip),
      ),
      matching: find.byType(IconButton),
    );

    test('choices', () {
      expect(durationChoices(testing: false).first, 30);
      expect(durationChoices(testing: true).take(3), [1, 5, 30]);
      expect(durationChoices(testing: true).last, 600);
      expect(headStartChoices(testing: false).take(2), [0, 5]);
      expect(headStartChoices(testing: true).take(6), [0, 1, 2, 3, 4, 5]);
    });

    testWidgets('not below 30 minutes in normal builds', (tester) async {
      await pump(tester, testing: false);
      expect(
        tester.widget<IconButton>(button('durationStepper', '−')).onPressed,
        isNull,
      );
    });

    testWidgets('5 and 1 minute, head start cut back', (tester) async {
      final settings = await pump(tester, testing: true);
      await tester.tap(button('durationStepper', '−'));
      await tester.pump();
      expect(settings().duration, const Duration(minutes: 5));
      expect(settings().headStart, Duration.zero);
      await tester.tap(button('headStartStepper', '+'));
      await tester.pump();
      expect(settings().headStart, const Duration(minutes: 1));
      await tester.tap(button('durationStepper', '−'));
      await tester.pump();
      expect(settings().duration, const Duration(minutes: 1));
      expect(settings().headStart, Duration.zero);
      expect(
        tester.widget<IconButton>(button('durationStepper', '−')).onPressed,
        isNull,
      );
      expect(
        settings().validate().contains(SettingsError.headStartInvalid),
        isFalse,
      );
      await tester.tap(button('durationStepper', '+'));
      await tester.pump();
      expect(settings().duration, const Duration(minutes: 5));
    });

    testWidgets('a value between the choices still steps', (tester) async {
      final settings = await pump(
        tester,
        testing: false,
        initial: const GameSettings(duration: Duration(minutes: 37)),
      );
      await tester.tap(button('durationStepper', '+'));
      await tester.pump();
      expect(settings().duration, const Duration(minutes: 45));
    });
  });

  group('start time (R-SET-21)', () {
    Future<GameSettings Function()> pumpEditable(WidgetTester tester) async {
      var settings = const GameSettings();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => SettingsForm(
                  settings: settings,
                  onChanged: (s) => setState(() => settings = s),
                ),
              ),
            ),
          ),
        ),
      );
      return () => settings;
    }

    testWidgets('none by default, explained', (tester) async {
      await pumpEditable(tester);
      expect(find.text('Startzeit'), findsOneWidget);
      expect(find.textContaining('Ohne Uhrzeit'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('startTimeValue'))).data,
        'keine',
      );
      expect(find.byKey(const Key('startTimeClear')), findsNothing);
    });

    testWidgets('typed in as hours and minutes and removed again', (
      tester,
    ) async {
      final current = await pumpEditable(tester);
      await tester.tap(find.byKey(const Key('startTimeTile')));
      await tester.pumpAndSettle();
      // No clock dial: two number fields with the number pad.
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      expect(
        tester.widget<TextField>(fields.first).keyboardType,
        TextInputType.number,
      );
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsNothing);
      await tester.enterText(fields.first, '15');
      await tester.enterText(fields.last, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(current().startTime, const Duration(hours: 15, minutes: 30));
      expect(
        tester.widget<Text>(find.byKey(const Key('startTimeValue'))).data,
        '15:30',
      );

      await tester.tap(find.byKey(const Key('startTimeClear')));
      await tester.pump();
      expect(current().startTime, isNull);
    });

    testWidgets('read-only: only the value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: SettingsForm(
                settings: GameSettings(startTime: Duration(hours: 9)),
                onChanged: null,
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('startTimeValue'))).data,
        '09:00',
      );
      expect(find.byKey(const Key('startTimeClear')), findsNothing);
      await tester.tap(find.byKey(const Key('startTimeTile')));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsNothing);
    });
  });
}
