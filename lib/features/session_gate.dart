import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/member.dart';
import '../data/game_repository.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'game/game_screen.dart';
import 'home/home_screen.dart';
import 'lobby/lobby_screen.dart';

/// Root widget: picks home, lobby or game based on the stored group and its status.
class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    return session.when(
      loading: () => const _Loading(),
      error: (e, _) => _ErrorView(
        message: '$e',
        onRetry: () => ref.invalidate(sessionControllerProvider),
      ),
      data: (session) {
        if (session == null) return const HomeScreen();
        final game = ref.watch(gameProvider);
        return game.when(
          loading: () => const _Loading(),
          error: (e, _) => _ErrorView(
            message: '$e',
            onRetry: () => ref.invalidate(gameProvider),
          ),
          data: (game) {
            if (game == null) return const _GroupGone();
            if (_wasRemoved(ref.watch(membersProvider), session.userId)) {
              return const _GroupGone(removed: true);
            }
            return switch (game.status) {
              GameStatus.lobby => LobbyScreen(session: session, game: game),
              GameStatus.running => GameScreen(session: session, game: game),
            };
          },
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: AppColors.hunter)),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.commonError(message), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the stored group was deleted (by the host or the TTL cleanup).
class _GroupGone extends ConsumerWidget {
  const _GroupGone({this.removed = false});

  /// Removed by the host instead of the whole group being deleted.
  final bool removed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                removed ? l10n.removedTitle : l10n.lobbyGroupGone,
                key: const Key('groupGone'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    ref.read(sessionControllerProvider.notifier).forget(),
                child: Text(l10n.lobbyBackHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The host removed this device's member (R-LOBBY-09): either the list no
/// longer contains it, or the rules now deny reading the member list.
bool _wasRemoved(AsyncValue<List<Member>> members, String myId) {
  final error = members.error;
  if (error is FirebaseException && error.code == 'permission-denied') {
    return true;
  }
  final list = members.value;
  return list != null && list.isNotEmpty && !list.any((m) => m.id == myId);
}
