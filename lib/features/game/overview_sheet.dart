import 'package:flutter/material.dart';

import '../../core/models/member.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Overview during a round (R-OVER-01 … 03): all hunters and players, caught
/// players struck through (R-CATCH-02), and whether a speedhunt runs.
Future<void> showOverviewSheet(
  BuildContext context, {
  required List<Member> members,
  required String myId,
  required bool speedhuntRunning,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => OverviewSheet(
    members: members,
    myId: myId,
    speedhuntRunning: speedhuntRunning,
  ),
);

class OverviewSheet extends StatelessWidget {
  const OverviewSheet({
    super.key,
    required this.members,
    required this.myId,
    required this.speedhuntRunning,
  });

  final List<Member> members;
  final String myId;
  final bool speedhuntRunning;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hunters = [
      for (final m in members)
        if (m.isHunter) m,
    ];
    final players = [
      for (final m in members)
        if (m.isPlayer) m,
    ]..sort((a, b) => (a.caught ? 1 : 0) - (b.caught ? 1 : 0));
    final free = players.where((p) => !p.caught).length;

    Widget section(String title, Color color, IconData icon) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );

    Widget tile(Member m, Color color) => ListTile(
      key: Key('overview_${m.id}'),
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: m.caught ? 0.08 : 0.18),
        foregroundColor: m.caught ? AppColors.textMuted : color,
        child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase()),
      ),
      title: Text(
        m.id == myId ? '${m.name} (${l10n.lobbyYouBadge})' : m.name,
        style: TextStyle(
          fontSize: 16,
          decoration: m.caught ? TextDecoration.lineThrough : null,
          color: m.caught ? AppColors.textMuted : null,
        ),
      ),
      trailing: m.caught
          ? const Icon(Icons.back_hand_outlined, color: AppColors.textMuted)
          : null,
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                l10n.overviewTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                key: const Key('overviewSpeedhunt'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: speedhuntRunning
                      ? AppColors.speedhunt
                      : AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bolt,
                      color: speedhuntRunning
                          ? Colors.black
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      speedhuntRunning
                          ? l10n.speedhuntActive
                          : l10n.overviewNoSpeedhunt,
                      style: TextStyle(
                        color: speedhuntRunning ? Colors.black : null,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            section(
              '${l10n.roleHunters} · ${hunters.length}',
              AppColors.hunter,
              Icons.track_changes,
            ),
            for (final h in hunters) tile(h, AppColors.hunter),
            section(
              '${l10n.rolePlayers} · ${l10n.overviewStillFree(free, players.length)}',
              AppColors.player,
              Icons.directions_run,
            ),
            for (final p in players) tile(p, AppColors.player),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
