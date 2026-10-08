import 'package:flutter/material.dart';

import '../../core/models/game_settings.dart';
import '../../core/models/member.dart';
import '../../core/schedule/speedhunt.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Hunter picks the player for a speedhunt (R-SPEED-02). Returns the player id.
/// [names] overrides the shown names, e.g. "Player 3" for anonymous players
/// (R-ANON-01).
Future<String?> showSpeedhuntDialog(
  BuildContext context, {
  required List<Member> members,
  Map<String, String> names = const {},
  required GameSettings settings,
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _SpeedhuntDialog(members: members, names: names, settings: settings),
);

String speedhuntDenialText(
  AppLocalizations l10n,
  SpeedhuntDenial d,
  GameSettings settings,
) => switch (d) {
  SpeedhuntDenial.notHunting => l10n.speedhuntNotHunting,
  SpeedhuntDenial.tooEarly => l10n.speedhuntTooEarly(
    settings.speedhuntEarliest.inMinutes,
  ),
  SpeedhuntDenial.noneLeft => l10n.speedhuntNoneLeft,
  SpeedhuntDenial.alreadyRunning => l10n.speedhuntAlreadyRunning,
  SpeedhuntDenial.invalidTarget => l10n.speedhuntInvalidTarget,
};

class _SpeedhuntDialog extends StatefulWidget {
  const _SpeedhuntDialog({
    required this.members,
    required this.names,
    required this.settings,
  });

  final List<Member> members;
  final Map<String, String> names;
  final GameSettings settings;

  @override
  State<_SpeedhuntDialog> createState() => _SpeedhuntDialogState();
}

class _SpeedhuntDialogState extends State<_SpeedhuntDialog> {
  String? _playerId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final players = [
      for (final m in widget.members)
        if (m.isPlayer && !m.caught) m,
    ];
    return AlertDialog(
      icon: const Icon(Icons.bolt, color: AppColors.speedhunt),
      title: Text(l10n.speedhuntTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('speedhuntPlayer'),
            initialValue: _playerId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.speedhuntWho,
              prefixIcon: const Icon(
                Icons.directions_run,
                color: AppColors.player,
              ),
            ),
            items: [
              for (final p in players)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(widget.names[p.id] ?? p.name),
                ),
            ],
            onChanged: (v) => setState(() => _playerId = v),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.speedhuntInfo(
              widget.settings.speedhuntPings,
              widget.settings.speedhuntInterval.inMinutes,
            ),
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (widget.settings.speedhuntFirstDelay > Duration.zero) ...[
            const SizedBox(height: 6),
            Text(
              l10n.speedhuntInfoDelay(
                widget.settings.speedhuntFirstDelay.inMinutes,
              ),
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('confirmSpeedhunt'),
          onPressed: _playerId == null
              ? null
              : () => Navigator.pop(context, _playerId),
          child: Text(l10n.speedhuntConfirm),
        ),
      ],
    );
  }
}
