import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/groups/group_list.dart';
import '../../data/game_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../lobby/create_group_screen.dart';
import '../lobby/join_screen.dart';

/// Entry screen: this device's groups, plus create or join one by code
/// (R-LOBBY-01, R-GROUPS-01 … 03). Without groups it is the plain start screen.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final groups = ref.watch(groupListProvider).value ?? const GroupList();

    final actions = [
      if (groups.isFull)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n.groupsLimitReached(GroupList.maxGroups),
            key: const Key('groupLimit'),
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.speedhunt),
          ),
        ),
      FilledButton.icon(
        key: const Key('createButton'),
        onPressed: groups.isFull
            ? null
            : () => _push(context, const CreateGroupScreen()),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(l10n.homeCreateGroup),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('joinButton'),
        onPressed: groups.isFull
            ? null
            : () => _push(context, const JoinScreen()),
        icon: const Icon(Icons.qr_code_2),
        label: Text(l10n.homeJoinGroup),
      ),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.2,
            colors: [Color(0x33FF4D2E), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: groups.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(flex: 2),
                      const Icon(
                        Icons.radar,
                        size: 88,
                        color: AppColors.hunter,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.appTitle.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.homeTagline,
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      const Spacer(flex: 3),
                      ...actions,
                      const SizedBox(height: 24),
                      const _PrivacyNote(),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.radar, color: AppColors.hunter),
                          const SizedBox(width: 8),
                          Text(
                            l10n.appTitle.toUpperCase(),
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.groupsTitle,
                              style: textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            l10n.groupsCount(
                              groups.groups.length,
                              GroupList.maxGroups,
                            ),
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final g in groups.groups) _GroupCard(group: g),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...actions,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        const Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.homePrivacyNote,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _GroupCard extends ConsumerStatefulWidget {
  const _GroupCard({required this.group});

  final SavedGroup group;

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard> {
  /// Opening derives the group key (≈1 s).
  var _opening = false;

  Future<void> _open() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _opening = true);
    try {
      final opened = await ref
          .read(sessionControllerProvider.notifier)
          .select(widget.group.code);
      if (!opened) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.groupsGone)));
      }
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.commonError('$e'))));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final group = widget.group;
    final groupId = group.groupId;
    final status = groupId == null
        ? null
        : ref.watch(groupStatusProvider(groupId));
    final gone = status != null && status.hasValue && status.value == null;
    final running = status?.value == GameStatus.running;
    final name = group.name ?? l10n.groupsUnnamed(group.code);

    return Card(
      key: Key('group_${group.code}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: _opening ? null : _open,
        leading: CircleAvatar(
          backgroundColor: AppColors.hunter.withValues(alpha: 0.18),
          foregroundColor: AppColors.hunter,
          child: Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          gone
              ? l10n.groupsDeleted
              : running
              ? l10n.groupsRunning
              : group.code,
          style: TextStyle(
            color: running ? AppColors.hunter : AppColors.textMuted,
            fontWeight: running ? FontWeight.w700 : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (group.isHost) _Badge(l10n.lobbyAdminBadge),
            if (_opening)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.hunter,
                ),
              )
            else
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
