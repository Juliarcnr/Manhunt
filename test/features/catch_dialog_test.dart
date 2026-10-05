import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/features/game/catch_dialog.dart';
import 'package:manhunt/l10n/app_localizations.dart';

void main() {
  const members = [
    Member(id: 'me', name: 'Julia', role: Role.hunter),
    Member(id: 'h2', name: 'Alex', role: Role.hunter),
    Member(id: 'p1', name: 'Kim', role: Role.player),
    Member(id: 'p2', name: 'Sam', role: Role.player, caught: true),
  ];

  /// Opens the hunter dialog and returns a getter for its result.
  Future<String? Function()> openDialog(WidgetTester tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showHunterCatchDialog(context, members: members),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('no "caught by" field (R-CATCH-03)', (tester) async {
    await openDialog(tester);
    expect(find.text('Wer wurde gefangen?'), findsOneWidget);
    expect(find.text('Gefangen von'), findsNothing);
    expect(find.text('Alex'), findsNothing);
  });

  testWidgets('only uncaught players can be selected', (tester) async {
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('catchPlayer')));
    await tester.pumpAndSettle();
    expect(find.text('Kim'), findsWidgets);
    expect(find.text('Sam'), findsNothing);
  });

  testWidgets('submit needs a player and returns it', (tester) async {
    final result = await openDialog(tester);
    final confirm = find.byKey(const Key('confirmCatch'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.byKey(const Key('catchPlayer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kim').last);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(result(), 'p1');
  });

  testWidgets('cancel returns nothing', (tester) async {
    final result = await openDialog(tester);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });
}
