import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

enum JokerKind { hunters, players }

/// Lets a player pick one of the jokers enabled in the settings
/// (R-PLAY-02, R-PLAY-03). Used jokers are shown but disabled.
Future<JokerKind?> showJokerSheet(
  BuildContext context, {
  required bool huntersEnabled,
  required bool huntersUsed,
  required bool playersEnabled,
  required bool playersUsed,
}) {
  final l10n = AppLocalizations.of(context);
  Widget option(
    JokerKind kind,
    IconData icon,
    String title,
    String hint,
    bool used,
  ) => ListTile(
    key: Key('joker_${kind.name}'),
    enabled: !used,
    leading: Icon(icon, color: used ? AppColors.textMuted : AppColors.player),
    title: Text(title),
    subtitle: Text(used ? l10n.jokerAlreadyUsed : hint),
    onTap: () => Navigator.pop(context, kind),
  );

  return showModalBottomSheet<JokerKind>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (huntersEnabled)
            option(
              JokerKind.hunters,
              Icons.track_changes,
              l10n.jokerHuntersOption,
              l10n.jokerHuntersHint,
              huntersUsed,
            ),
          if (playersEnabled)
            option(
              JokerKind.players,
              Icons.groups_outlined,
              l10n.jokerPlayersOption,
              l10n.jokerPlayersHint,
              playersUsed,
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Confirmation before a joker is used up.
Future<bool> showJokerConfirm(
  BuildContext context, {
  required String title,
  required String text,
}) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.visibility_outlined, color: AppColors.player),
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('confirmJoker'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.jokerConfirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}
