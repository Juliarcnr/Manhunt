import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bots/bot_plan.dart';
import '../../core/history/round_summary.dart';
import '../../core/models/member.dart';
import '../../core/round/read_budget.dart';
import '../../core/teams/start_check.dart';
import '../../core/teams/team_assignment.dart';
import '../../data/game_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_form.dart';
import '../history/history_button.dart';
import '../history/history_map_screen.dart';
import '../map/area_card.dart';
import '../settings/settings_screen.dart';
import 'bot_lobby_keeper.dart';
import 'name_field.dart';

/// Waiting room: code, participants, team assignment, start (R-LOBBY-02 … 06).
class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key, required this.session, required this.game});

  final GroupSession session;
  final GameInfo game;

  bool get _isAdmin => game.adminId == session.userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final loadedMembers = ref.watch(membersProvider).value;
    final members = loadedMembers ?? const <Member>[];
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

    // Computer members keep the role of their kind (R-BOT-03).
    final humans = members.where((m) => !isBot(m)).toList();

    void assignRandom() {
      // Game masters keep their role (R-GM-02).
      final playing = humans.where((m) => !m.isGameMaster).length;
      if (playing <= game.settings.hunterCount) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.errorNotEnoughPlayers)));
        return;
      }
      run(
        () => repo.setRoles(
          session,
          assignRandomRoles(humans, game.settings.hunterCount),
        ),
      );
    }

    final hunters = members.where((m) => m.isHunter).toList();
    final players = members.where((m) => m.isPlayer).toList();
    final unassigned = members.where((m) => m.role == Role.unassigned).toList();
    final gameMasters = members.where((m) => m.isGameMaster).toList();

    // Host picks who becomes game master (R-GM-02); computer members keep
    // their kind's role.
    Future<void> addGameMaster() async {
      final picked = await _pickGameMaster(context, [
        for (final m in humans)
          if (!m.isGameMaster) m,
      ]);
      if (picked != null) {
        await run(
          () => repo.setRoles(
            session,
            setRole(members, picked.id, Role.gameMaster),
          ),
        );
      }
    }

    Widget memberTile(Member m) => _MemberTile(
      member: m,
      isAdmin: m.id == game.adminId,
      isMe: m.id == session.userId,
      onRename: m.id == session.userId
          ? () async {
              final newName = await _askMyName(context, m.name);
              if (newName != null && newName != m.name) {
                await run(() => repo.renameMe(session, newName));
              }
            }
          : null,
      onTap: _isAdmin && !isBot(m)
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

    final controller = ref.read(sessionControllerProvider.notifier);
    final name = game.name;

    // Back (button or system gesture) leads to the group overview; the group
    // stays on this device (R-GROUPS-03).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('groupsBackButton'),
            icon: const Icon(Icons.arrow_back),
            tooltip: l10n.groupsBack,
            onPressed: controller.close,
          ),
          title: name == null
              ? Text(l10n.lobbyTitle)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, key: const Key('groupName')),
                    Text(
                      l10n.lobbyTitle,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
          actions: [
            HistoryButton(isHost: _isAdmin),
            // Everyone sees the settings, only the host edits (R-SET-14).
            IconButton(
              key: const Key('settingsButton'),
              icon: const Icon(Icons.tune),
              tooltip: l10n.settingsTitle,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    session: session,
                    initial: game.settings,
                    readOnly: !_isAdmin,
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              key: const Key('lobbyMenu'),
              onSelected: (value) async {
                if (value == 'leave') {
                  await run(controller.leave);
                } else if (value == 'rename') {
                  final newName = await _askGroupName(context, name ?? '');
                  if (newName != null) {
                    await run(() => repo.renameGroup(session, newName));
                  }
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
                  PopupMenuItem(value: 'rename', child: Text(l10n.lobbyRename)),
                if (_isAdmin)
                  PopupMenuItem(value: 'delete', child: Text(l10n.lobbyDelete)),
              ],
            ),
          ],
        ),
        body: BotLobbyKeeper(
          session: session,
          game: game,
          members: loadedMembers,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _CodeCard(code: session.code),
              const SizedBox(height: 16),
              // Who won the last round and its map (R-GAME-09, R-HIST-04).
              if (ref.watch(historyProvider).value case [final last, ...]) ...[
                _LastRoundCard(summary: last),
                const SizedBox(height: 16),
              ],
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
              // Optional (R-GM-01): others only see it when someone has it.
              if (_isAdmin || gameMasters.isNotEmpty)
                _RoleSection(
                  key: const Key('gameMasterSection'),
                  title: l10n.roleGameMaster,
                  color: AppColors.gameMaster,
                  icon: Icons.visibility_outlined,
                  footer: [
                    if (_isAdmin) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Text(
                          l10n.lobbyGameMasterHint,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TextButton.icon(
                            key: const Key('addGameMasterButton'),
                            onPressed: addGameMaster,
                            icon: const Icon(Icons.add),
                            label: Text(l10n.lobbyAddGameMaster),
                          ),
                        ),
                      ),
                    ],
                  ],
                  children: gameMasters.map(memberTile).toList(),
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
              // Before the start the host learns that hunters will see each
              // other less often (R-QUOTA-02).
              if (_isAdmin &&
                  hunterLiveIntervalFor(game.settings, members) !=
                      hunterLiveNormal)
                Padding(
                  key: const Key('hunterLiveThrottledHint'),
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.speed,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.lobbyHunterLiveThrottled(
                            (estimatedQuotaShare(game.settings, members) * 100)
                                .round(),
                          ),
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
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
      ),
    );
  }
}

/// Host renames the group (R-GROUPS-04). Returns null if cancelled.
Future<String?> _askGroupName(BuildContext context, String current) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(
        title: AppLocalizations.of(ctx).lobbyRename,
        current: current,
        field: (controller, submit) => GroupNameField(
          controller: controller,
          autofocus: true,
          onSubmitted: (_) => submit(),
        ),
      ),
    );

/// Anyone changes their own display name (R-LOBBY-10). Returns null if
/// cancelled.
Future<String?> _askMyName(BuildContext context, String current) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(
        title: AppLocalizations.of(ctx).lobbyRenameMe,
        current: current,
        field: (controller, submit) => NameField(
          controller: controller,
          autofocus: true,
          onSubmitted: (_) => submit(),
        ),
      ),
    );

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.title,
    required this.current,
    required this.field,
  });

  final String title;
  final String current;
  final Widget Function(TextEditingController controller, VoidCallback submit)
  field;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Form(key: _formKey, child: widget.field(_controller, _submit)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('renameSave'),
          onPressed: _submit,
          child: Text(l10n.commonSave),
        ),
      ],
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

/// The newest round of the history: who won, with its map (R-GAME-09,
/// R-HIST-04) – the round ends by itself, so the lobby says how it went.
class _LastRoundCard extends StatelessWidget {
  const _LastRoundCard({required this.summary});

  final RoundSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final survivors = summary.survivors;
    final huntersWon = survivors.isEmpty;
    final names = survivors.length < 2
        ? survivors.join()
        : l10n.nameList(
            survivors.sublist(0, survivors.length - 1).join(', '),
            survivors.last,
          );
    return Card(
      key: const Key('lastRoundCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.lobbyLastRound(summary.round).toUpperCase(),
              style: const TextStyle(
                color: AppColors.textMuted,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  color: huntersWon ? AppColors.hunter : AppColors.speedhunt,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    huntersWon
                        ? l10n.lobbyLastRoundHuntersWon
                        : l10n.lobbyLastRoundPlayersWon(
                            names,
                            survivors.length,
                          ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (summary.abortedEarly)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.historyAborted,
                  style: const TextStyle(color: AppColors.speedhunt),
                ),
              ),
            if (summary.hasMap) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('lastRoundMap'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HistoryMapScreen(summary: summary),
                  ),
                ),
                icon: const Icon(Icons.map_outlined),
                label: Text(l10n.historyShowMap),
              ),
            ],
          ],
        ),
      ),
    );
  }
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

/// Host chooses a member to become game master (R-GM-02). Returns null if
/// cancelled.
Future<Member?> _pickGameMaster(
  BuildContext context,
  List<Member> candidates,
) => showModalBottomSheet<Member>(
  context: context,
  showDragHandle: true,
  builder: (ctx) {
    final l10n = AppLocalizations.of(ctx);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.lobbyPickGameMaster,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.lobbyNobodyToPick,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          for (final m in candidates)
            ListTile(
              key: Key('pickGameMaster_${m.id}'),
              leading: const Icon(
                Icons.visibility_outlined,
                color: AppColors.gameMaster,
              ),
              title: Text(m.name),
              onTap: () => Navigator.pop(ctx, m),
            ),
        ],
      ),
    );
  },
);

class _RoleSection extends StatelessWidget {
  const _RoleSection({
    super.key,
    required this.title,
    required this.color,
    required this.icon,
    required this.children,
    this.footer = const [],
  });

  final String title;
  final Color color;
  final IconData icon;
  final List<Widget> children;

  /// Below the members, not counted (e.g. hint and add button).
  final List<Widget> footer;

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
              ...footer,
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
    this.onRename,
    this.onTap,
    this.onRemove,
  });

  final Member member;
  final bool isAdmin;
  final bool isMe;

  /// Only for oneself: change the own display name (R-LOBBY-10).
  final VoidCallback? onRename;
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
      Role.gameMaster => AppColors.gameMaster,
    };
    return ListTile(
      onTap: onTap,
      onLongPress: onRemove,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        foregroundColor: color,
        child: Text(
          member.name.isEmpty
              ? '?'
              : member.name.characters.first.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(member.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Right next to the badges, not after the name (R-LOBBY-10).
          if (onRename != null)
            IconButton(
              key: const Key('renameMeButton'),
              tooltip: l10n.lobbyRenameMe,
              onPressed: onRename,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
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
