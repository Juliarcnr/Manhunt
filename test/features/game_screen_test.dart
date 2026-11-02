import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/game_settings.dart';
import 'package:manhunt/data/game_repository.dart';
import 'package:manhunt/features/game/game_screen.dart';
import 'package:manhunt/l10n/app_localizations.dart';

import '../helpers.dart';

void main() {
  final start = DateTime.utc(2026, 10, 4, 14);
  GameInfo running(String adminId, {DateTime? finishedAt}) => GameInfo(
    adminId: adminId,
    status: GameStatus.running,
    settings: const GameSettings(),
    startAt: start,
    finishedAt: finishedAt,
  );

  Future<(FakeFirebaseFirestore, GroupSession)> pumpGame(
    WidgetTester tester, {
    required String userId,
    required DateTime now,
    String adminId = 'admin',
    DateTime? finishedAt,
  }) async {
    final db = FakeFirebaseFirestore();
    final session = (await tester.runAsync(
      () => testSession('ABCDE-FGHJK', userId),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: deviceOverrides(db: db, userId: userId),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GameScreen(
            session: session,
            game: running(adminId, finishedAt: finishedAt),
            now: () => now,
          ),
        ),
      ),
    );
    await tester.pump();
    return (db, session);
  }

  testWidgets('shows head start countdown with a short title', (tester) async {
    await pumpGame(
      tester,
      userId: 'admin',
      now: start.add(const Duration(minutes: 5)),
    );
    // Short label so it isn't truncated in the compact header.
    expect(find.text('HEAD START'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
  });

  testWidgets('time up: nothing to end, the round is saved by itself '
      '(R-GAME-06, R-GAME-10)', (tester) async {
    await pumpGame(
      tester,
      userId: 'admin',
      now: start.add(const Duration(hours: 3, seconds: 30)),
    );
    expect(find.text('TIME IS UP'), findsOneWidget);
    expect(find.byKey(const Key('endRoundButton')), findsNothing);
    // No extra info line: the winner banner says it (R-GAME-09).
    expect(find.textContaining('saved in a moment'), findsNothing);
  });

  testWidgets('only the host can end the game', (tester) async {
    await pumpGame(
      tester,
      userId: 'guest',
      now: start.add(const Duration(hours: 1)),
    );
    expect(find.byKey(const Key('endRoundButton')), findsNothing);
  });

  testWidgets('aborting early needs two confirmations (R-GAME-07)', (
    tester,
  ) async {
    final (db, session) = await pumpGame(
      tester,
      userId: 'admin',
      now: start.add(const Duration(hours: 1)), // 2 h left
    );
    final repo = deviceRepo(db);
    await tester.runAsync(() async {
      await repo.createGame(session, name: 'Julia', settings: defaultSettings);
      await repo.startGame(session);
    });
    Future<GameStatus> status() async =>
        (await tester.runAsync(() => repo.watchGame(session).first))!.status;

    // 1st dialog, cancel.
    await tester.tap(find.byKey(const Key('endRoundButton')));
    await tester.pumpAndSettle();
    expect(find.text('Abort the game early?'), findsOneWidget);
    expect(find.textContaining('2:00:00 left'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await status(), GameStatus.running);

    // 1st confirmed, 2nd cancelled.
    await tester.tap(find.byKey(const Key('endRoundButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmAbortFirst')));
    await tester.pumpAndSettle();
    expect(find.text('Really abort?'), findsOneWidget);
    expect(find.textContaining('saved with its map'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await status(), GameStatus.running);

    // Both confirmed.
    await tester.tap(find.byKey(const Key('endRoundButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmAbortFirst')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmEndRound')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(await status(), GameStatus.lobby);

    final history = await tester.runAsync(
      () => repo.watchHistory(session).first,
    );
    expect(history!.single.abortedEarly, isTrue);
    expect(history.single.hasMap, isTrue);
  });

  testWidgets('after the hunters won there is nothing to end (R-GAME-08, '
      'R-GAME-10)', (tester) async {
    final finishedAt = start.add(const Duration(hours: 1));
    await pumpGame(
      tester,
      userId: 'admin',
      now: finishedAt.add(const Duration(seconds: 30)),
      finishedAt: finishedAt,
    );
    expect(find.text('HUNTERS WON'), findsOneWidget);
    expect(find.byKey(const Key('endRoundButton')), findsNothing);
  });
}
