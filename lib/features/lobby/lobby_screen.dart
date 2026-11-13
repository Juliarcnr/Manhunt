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
/// Unassigned members also see it while a round runs – for them no game is
/// on (R-LOBBY-11).
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, required this.session, required this.game});

  final GroupSession session;
  final GameInfo game;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final _scroll = ScrollController();
  final _listKey = GlobalKey();

  GroupSession get session => widget.session;
  GameInfo get game => widget.game;
  bool get _isAdmin => game.adminId == session.userId;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls while a dragged person is near the top or bottom edge, so every
  /// section can be reached (R-LOBBY-05).
  void _autoScroll(Offset global) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final y = box.globalToLocal(global).dy;
    const edge = 72.0;
    const step = 14.0;
    final delta = y < edge
        ? -step
        : y > box.size.height - edge
        ? step
        : 0.0;
    if (delta == 0) return;
    final p = _scroll.position;
    _scroll.jumpTo(
      (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loadedMembers = ref.watch(membersProvider).value;
    final members = loadedMembers ?? const <Member>[];
    final repo = ref.read(gameRepositoryProvider);
    final check = StartCheck(game.settings, members, adminId: game.adminId);
    // Only seen by members who sit the round out (R-LOBBY-11): nothing can
    // be changed until it is over.
    final running = game.status == GameStatus.running;
    final editRoles = _isAdmin && !running;

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

    // Everybody is rolled anew, 30/70, whatever their role (R-LOBBY-04).
    void assignRandom() {
      if (humans.length < 2) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.errorNotEnoughPlayers)));
        return;
      }
      run(() => repo.setRoles(session, assignRandomRoles(humans)));
    }

    final hunters = members.where((m) => m.isHunter).toList();
    final players = members.where((m) => m.isPlayer).toList();
    final unassigned = members.where((m) => m.role == Role.unassigned).toList();
    final gameMasters = members.where((m) => m.isGameMaster).toList();

    void moveTo(Member m, Role role) {
      if (m.role == role) return;
      run(() => repo.setRoles(session, setRole(members, m.id, role)));
    }

    // Computer members keep their kind's role (R-BOT-03).
    bool movable(Member m) => editRoles && !isBot(m);

    Widget memberTile(Member m) {
      final tile = _MemberTile(
        member: m,
        isAdmin: m.id == game.adminId,
        draggable: movable(m),
        onRename: m.id == session.userId
            ? () async {
                final newName = await _askMyName(context, m.name);
                if (newName != null && newName != m.name) {
                  await run(() => repo.renameMe(session, newName));
                }
              }
            : null,
        // Alternative to drag and drop (R-LOBBY-05).
        onTap: movable(m)
            ? () async {
                final role = await _pickRole(context, m);
                if (role != null) moveTo(m, role);
              }
            : null,
        // Not for the host themself: they must have a role (R-LOBBY-13).
        onUnassign:
            movable(m) && m.role != Role.unassigned && m.id != game.adminId
            ? () => moveTo(m, Role.unassigned)
            : null,
        onRemove: _isAdmin && !running && m.id != session.userId
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
      if (!movable(m)) return tile;
      return LongPressDraggable<Member>(
        key: Key('drag_${m.id}'),
        data: m,
        onDragUpdate: (d) => _autoScroll(d.globalPosition),
        feedback: _DragFeedback(member: m),
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        child: tile,
      );
    }

    Widget section({
      required Key key,
      required Role role,
      required String title,
      required Color color,
      required IconData icon,
      required List<Member> list,
      List<Widget> footer = const [],
    }) => _RoleSection(
      key: key,
      title: title,
      color: color,
      icon: icon,
      footer: footer,
      onDrop: editRoles ? (m) => moveTo(m, role) : null,
      acceptsFrom: (m) => m.role != role,
      children: list.map(memberTile).toList(),
    );

    Widget hint(String text, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Text(text, style: const TextStyle(color: AppColors.textMuted)),
    );

    final problems = [
      ...check.settingsErrors.map((e) => settingsErrorText(l10n, e)),
      if (check.hostUnassigned) l10n.errorHostUnassigned,
      if (check.noHunter) l10n.errorHunterCountInvalid,
      if (check.noPlayer) l10n.errorNotEnoughPlayers,
    ];

    // The host confirms who plays before the round starts (R-LOBBY-06).
    Future<void> start() async {
      if (await _confirmStart(context, members)) {
        await run(() => repo.startGame(session));
      }
    }

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
            key: _listKey,
            controller: _scroll,
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
                onChanged: running
                    ? null
                    : (area) => run(() => repo.updateArea(session, area)),
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
                  if (editRoles)
                    TextButton.icon(
                      key: const Key('randomButton'),
                      onPressed: assignRandom,
                      icon: const Icon(Icons.casino_outlined),
                      label: Text(l10n.lobbyAssignRandom),
                    ),
                ],
              ),
              if (editRoles)
                Padding(
                  key: const Key('dragHint'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.lobbyDragHint,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
              // The host always sees all four sections as drop targets;
              // others only the filled ones of "unassigned" and "game
              // master" (R-LOBBY-05, R-GM-02).
              if (editRoles || unassigned.isNotEmpty)
                section(
                  key: const Key('unassignedSection'),
                  role: Role.unassigned,
                  title: l10n.roleUnassigned,
                  color: AppColors.textMuted,
                  icon: Icons.help_outline,
                  list: unassigned,
                  footer: [
                    hint(
                      l10n.lobbyUnassignedHint,
                      key: const Key('unassignedHint'),
                    ),
                  ],
                ),
              section(
                key: const Key('playerSection'),
                role: Role.player,
                title: l10n.rolePlayers,
                color: AppColors.player,
                icon: Icons.directions_run,
                list: players,
              ),
              section(
                key: const Key('hunterSection'),
                role: Role.hunter,
                title: l10n.roleHunters,
                color: AppColors.hunter,
                icon: Icons.track_changes,
                list: hunters,
              ),
              if (editRoles || gameMasters.isNotEmpty)
                section(
                  key: const Key('gameMasterSection'),
                  role: Role.gameMaster,
                  title: l10n.roleGameMaster,
                  color: AppColors.gameMaster,
                  icon: Icons.visibility_outlined,
                  list: gameMasters,
                  footer: [if (editRoles) hint(l10n.lobbyGameMasterHint)],
                ),
              if (editRoles && problems.isNotEmpty) ...[
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
              if (editRoles &&
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
                    onPressed: check.canStart && !running ? start : null,
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

/// Role menu of one person, the alternative to drag and drop (R-LOBBY-05).
/// Returns null if cancelled.
Future<Role?> _pickRole(BuildContext context, Member member) =>
    showModalBottomSheet<Role>(
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
                  l10n.lobbyRoleMenuTitle(member.name),
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              for (final role in _roleOrder)
                ListTile(
                  key: Key('roleOption_${role.name}'),
                  leading: Icon(_roleIcon(role), color: _roleColor(role)),
                  title: Text(_roleTitle(l10n, role)),
                  trailing: role == member.role
                      ? const Icon(Icons.check, color: AppColors.textMuted)
                      : null,
                  onTap: () => Navigator.pop(ctx, role),
                ),
            ],
          ),
        );
      },
    );

/// The order of the lobby sections (R-LOBBY-05).
const _roleOrder = [Role.unassigned, Role.player, Role.hunter, Role.gameMaster];

Color _roleColor(Role role) => switch (role) {
  Role.hunter => AppColors.hunter,
  Role.player => AppColors.player,
  Role.unassigned => AppColors.textMuted,
  Role.gameMaster => AppColors.gameMaster,
};

IconData _roleIcon(Role role) => switch (role) {
  Role.hunter => Icons.track_changes,
  Role.player => Icons.directions_run,
  Role.unassigned => Icons.help_outline,
  Role.gameMaster => Icons.visibility_outlined,
};

String _roleTitle(AppLocalizations l10n, Role role) => switch (role) {
  Role.hunter => l10n.roleHunters,
  Role.player => l10n.rolePlayers,
  Role.unassigned => l10n.roleUnassigned,
  Role.gameMaster => l10n.roleGameMaster,
};

/// Before the round starts, the host sees who plays in which role and who
/// sits out, and confirms (R-LOBBY-06, R-LOBBY-11).
Future<bool> _confirmStart(BuildContext context, List<Member> members) async {
  final l10n = AppLocalizations.of(context);
  final sitOut = members.where((m) => m.role == Role.unassigned).toList();
  Widget group(Role role) {
    final names = [
      for (final m in members)
        if (m.role == role) m.name,
    ];
    if (names.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: Key('startConfirm_${role.name}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_roleIcon(role), color: _roleColor(role), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_roleTitle(l10n, role).toUpperCase()} · ${names.length}',
                  style: TextStyle(
                    color: _roleColor(role),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(names.join(', ')),
        ],
      ),
    );
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('startConfirmDialog'),
      title: Text(l10n.lobbyStartConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            group(Role.player),
            group(Role.hunter),
            group(Role.gameMaster),
            if (sitOut.isNotEmpty) ...[
              const Divider(),
              Text(
                l10n.lobbyStartConfirmSitOut(sitOut.length),
                key: const Key('startConfirmSitOut'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                sitOut.map((m) => m.name).join(', '),
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('startConfirmButton'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.lobbyStart),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// One role's card; with [onDrop] also a drop target for dragged people
/// (R-LOBBY-05).
class _RoleSection extends StatelessWidget {
  const _RoleSection({
    super.key,
    required this.title,
    required this.color,
    required this.icon,
    required this.children,
    required this.acceptsFrom,
    this.onDrop,
    this.footer = const [],
  });

  final String title;
  final Color color;
  final IconData icon;
  final List<Widget> children;
  final ValueChanged<Member>? onDrop;
  final bool Function(Member) acceptsFrom;

  /// Below the members, not counted (e.g. a hint).
  final List<Widget> footer;

  Widget _card({required bool highlight}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: color, width: 2),
            )
          : null,
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

  @override
  Widget build(BuildContext context) {
    final drop = onDrop;
    if (drop == null) return _card(highlight: false);
    return DragTarget<Member>(
      onWillAcceptWithDetails: (d) => acceptsFrom(d.data),
      onAcceptWithDetails: (d) => drop(d.data),
      builder: (context, candidates, _) =>
          _card(highlight: candidates.isNotEmpty),
    );
  }
}

/// What follows the finger while a person is dragged (R-LOBBY-05).
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.drag_indicator,
              color: _roleColor(member.role),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              member.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isAdmin,
    this.draggable = false,
    this.onRename,
    this.onTap,
    this.onUnassign,
    this.onRemove,
  });

  final Member member;
  final bool isAdmin;

  /// Host only: can be moved to another role by drag and drop (R-LOBBY-05).
  final bool draggable;

  /// Only for oneself: change the own display name (R-LOBBY-10).
  final VoidCallback? onRename;

  /// Host only: opens the role menu (R-LOBBY-05).
  final VoidCallback? onTap;

  /// Host only: back to "unassigned", i.e. sit out (R-LOBBY-12).
  final VoidCallback? onUnassign;

  /// Host only, not for oneself: remove from the group (R-LOBBY-09).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _roleColor(member.role);
    return ListTile(
      onTap: onTap,
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
          // No "You" badge: the pencil marks the own name (R-LOBBY-10).
          if (onUnassign != null)
            IconButton(
              key: Key('unassign_${member.id}'),
              tooltip: l10n.lobbyUnassign,
              onPressed: onUnassign,
              icon: const Icon(
                Icons.person_off_outlined,
                color: AppColors.textMuted,
              ),
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
          if (draggable)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.drag_indicator, color: AppColors.textMuted),
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
