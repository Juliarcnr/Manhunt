import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/member.dart';
import '../data/game_repository.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'game/game_screen.dart';
import 'groups/groups_screen.dart';
import 'lobby/lobby_screen.dart';

/// Root widget: picks group overview, lobby or game based on the open group
/// and its status.
class SessionGate extends ConsumerStatefulWidget {
  const SessionGate({super.key});

  @override
  ConsumerState<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends ConsumerState<SessionGate> {
  @override
  void initState() {
    super.initState();
    unawaited(_requestPermissions());
  }

  /// Asks for location and notification permission right when the app opens
  /// (R-PERM-01): iOS lists "Location" in the app's settings only after the
  /// first request, and the checklist should be done before the game starts.
  /// Location first, then notifications: Android drops a permission dialog
  /// requested while another one is open.
  Future<void> _requestPermissions() async {
    await ref.read(locationServiceProvider).ensurePermission();
    await ref.read(notificationServiceProvider).init();
  }

  @override
  Widget build(BuildContext context) {
    // Keeps name and host flag in the group overview current (R-GROUPS-03).
    ref.listen(gameProvider, (_, next) {
      final game = next.value;
      if (game != null) {
        ref.read(sessionControllerProvider.notifier).rememberInfo(game);
      }
    });
    final session = ref.watch(sessionControllerProvider);
    return session.when(
      loading: () => const _Loading(),
      error: (e, _) => _ErrorView(
        message: '$e',
        onRetry: () => ref.invalidate(sessionControllerProvider),
      ),
      data: (session) {
        if (session == null) return const GroupsScreen();
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
