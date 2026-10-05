import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/history/round_summary.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_form.dart';

/// All finished rounds of the group with catches (R-HIST-01 … 03).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.commonError('$e'))),
        data: (rounds) => rounds.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    l10n.historyEmpty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rounds.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => RoundCard(summary: rounds[i]),
              ),
      ),
    );
  }
}

class RoundCard extends StatelessWidget {
  const RoundCard({super.key, required this.summary});

  final RoundSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMd(locale)
        .add_Hm()
        .format(summary.startedAt.toLocal());
    final survivors = summary.survivors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.historyRound(summary.round),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  formatDuration(l10n, summary.duration),
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
            Text(date, style: const TextStyle(color: AppColors.textMuted)),
            if (summary.abortedEarly)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.stop_circle_outlined,
                      size: 16,
                      color: AppColors.speedhunt,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.historyAborted,
                      key: const Key('abortedEarly'),
                      style: const TextStyle(color: AppColors.speedhunt),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _Team(
              icon: Icons.track_changes,
              color: AppColors.hunter,
              label: l10n.roleHunters,
              names: summary.hunters,
            ),
            _Team(
              icon: Icons.directions_run,
              color: AppColors.player,
              label: l10n.rolePlayers,
              names: summary.players,
            ),
            const Divider(height: 24),
            Text(
              l10n.historyCatches.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            if (summary.catches.isEmpty)
              Text(l10n.historyNoCatches)
            else
              for (final c in summary.catches)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          _clock(c.after),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          c.player,
                          style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            if (survivors.isEmpty)
              Text(
                l10n.historyAllCaught,
                style: const TextStyle(
                  color: AppColors.hunter,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              _Team(
                icon: Icons.emoji_events_outlined,
                color: AppColors.speedhunt,
                label: l10n.historySurvivors,
                names: survivors,
              ),
          ],
        ),
      ),
    );
  }
}

/// `1:12 h` style time since round start.
String _clock(Duration d) =>
    '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')} h';

class _Team extends StatelessWidget {
  const _Team({
    required this.icon,
    required this.color,
    required this.label,
    required this.names,
  });

  final IconData icon;
  final Color color;
  final String label;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: names.join(', ')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
