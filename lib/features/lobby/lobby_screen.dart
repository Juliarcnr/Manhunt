import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/member.dart';
import '../../core/teams/start_check.dart';
import '../../core/teams/team_assignment.dart';
import '../../data/game_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_form.dart';
import '../history/history_button.dart';
import '../map/area_card.dart';
import '../settings/settings_screen.dart';

/// Waiting room: code, participants, team assignment, start (R-LOBBY-02 … 06).
class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key, required this.session, required this.game});

  final GroupSession session;
  final GameInfo game;

  bool get _isAdmin => game.adminId == session.userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final repo = ref.read(gameRepositoryProvider);
    final check = StartCheck(game.settings, members);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } on Exception catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.commonError('$e'))));
        }
      }
    }

    void assignRandom() {
      if (members.length <= game.settings.hunterCount) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.errorNotEnoughPlayers)));
        return;
      }
      run(
        () => repo.setRoles(
          session,
          assignRandomRoles(members, game.settings.hunterCount),
        ),
      );
    }

    final hunters = members.where((m) => m.isHunter).toList();
    final players = members.where((m) => m.isPlayer).toList();
    final unassigned = members.where((m) => m.role == Role.unassigned).toList();

    Widget memberTile(Member m) => _MemberTile(
      member: m,
      isAdmin: m.id == game.adminId,
      isMe: m.id == session.userId,
      onTap: _isAdmin
          ? () => run(() => repo.setRoles(session, toggleRole(members, m.id)))
          : null,
      onRemove: _isAdmin && m.id != session.userId
          ? () async {
              final ok = await _confirm(
                context,
                l10n.lobbyRemoveMember(m.name),
                l10n.lobbyRemove,
              );
              if (ok) await run(() => repo.removeMember(session, m.id));
            }
          : null,
    );

    final problems = [
      ...check.settingsErrors.map((e) => settingsErrorText(l10n, e)),
      if (check.hasUnassigned) l10n.errorUnassigned,
      if (!check.hasUnassigned && check.noHunter) l10n.errorHunterCountInvalid,
      if (!check.hasUnassigned && check.noPlayer) l10n.errorNotEnoughPlayers,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.lobbyTitle),
        actions: [
          const HistoryButton(),
          if (_isAdmin)
            IconButton(
              key: const Key('settingsButton'),
              icon: const Icon(Icons.tune),
              tooltip: l10n.settingsTitle,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SettingsScreen(session: session, initial: game.settings),
                ),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              final controller = ref.read(sessionControllerProvider.notifier);
              if (value == 'leave') {
                await run(controller.leave);
              } else if (value == 'delete' &&
                  await _confirm(
                    context,
                    l10n.lobbyDeleteConfirm,
                    l10n.lobbyDelete,
                  )) {
                await run(controller.deleteGroup);
              }
            },
            itemBuilder: (_) => [
              if (!_isAdmin)
                PopupMenuItem(value: 'leave', child: Text(l10n.lobbyLeave)),
              if (_isAdmin)
                PopupMenuItem(value: 'delete', child: Text(l10n.lobbyDelete)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CodeCard(code: session.code),
          const SizedBox(height: 16),
          AreaCard(
            area: game.settings.area,
            onChanged: (area) => run(() => repo.updateArea(session, area)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.lobbyParticipants(members.length),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_isAdmin)
                TextButton.icon(
                  key: const Key('randomButton'),
                  onPressed: assignRandom,
                  icon: const Icon(Icons.casino_outlined),
                  label: Text(l10n.lobbyAssignRandom),
                ),
            ],
          ),
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.lobbyTapToSwitch,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          if (unassigned.isNotEmpty)
            _RoleSection(
              title: l10n.roleUnassigned,
              color: AppColors.textMuted,
              icon: Icons.help_outline,
              children: unassigned.map(memberTile).toList(),
            ),
          _RoleSection(
            title: l10n.roleHunters,
            color: AppColors.hunter,
            icon: Icons.track_changes,
            children: hunters.map(memberTile).toList(),
          ),
          _RoleSection(
            title: l10n.rolePlayers,
            color: AppColors.player,
            icon: Icons.directions_run,
            children: players.map(memberTile).toList(),
          ),
          if (_isAdmin && problems.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final p in problems)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.speedhunt,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p)),
                  ],
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isAdmin
              ? FilledButton.icon(
                  key: const Key('startButton'),
                  onPressed: check.canStart
                      ? () => run(() => repo.startGame(session))
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(l10n.lobbyStart),
                )
              : Text(
                  l10n.lobbyWaitingForAdmin,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
        ),
      ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String text, String action) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.lobbyCodeCopied)));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                l10n.lobbyCodeLabel.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(
                      child: Text(
                        code,
                        key: const Key('groupCode'),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy_rounded, color: AppColors.textMuted),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.lobbyShareHint,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleSection extends StatelessWidget {
  const _RoleSection({
    required this.title,
    required this.color,
    required this.icon,
    required this.children,
  });

  final String title;
  final Color color;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '${title.toUpperCase()} · ${children.length}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isAdmin,
    required this.isMe,
    this.onTap,
    this.onRemove,
  });

  final Member member;
  final bool isAdmin;
  final bool isMe;
  final VoidCallback? onTap;

  /// Host only, not for oneself: remove from the group (R-LOBBY-09).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = switch (member.role) {
      Role.hunter => AppColors.hunter,
      Role.player => AppColors.player,
      Role.unassigned => AppColors.textMuted,
    };
    return ListTile(
      onTap: onTap,
      onLongPress: onRemove,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        foregroundColor: color,
        child: Text(
          member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(member.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAdmin) _Badge(l10n.lobbyAdminBadge),
          if (isMe) _Badge(l10n.lobbyYouBadge),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.swap_horiz, color: AppColors.textMuted),
            ),
          if (onRemove != null)
            IconButton(
              key: Key('remove_${member.id}'),
              tooltip: l10n.lobbyRemove,
              onPressed: onRemove,
              icon: const Icon(
                Icons.person_remove_outlined,
                color: AppColors.textMuted,
              ),
            ),
        ],
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
