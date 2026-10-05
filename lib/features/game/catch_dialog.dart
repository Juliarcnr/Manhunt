import 'package:flutter/material.dart';

import '../../core/models/member.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Hunter reports a catch (R-CATCH-01): only who was caught, not by whom
/// (R-CATCH-03). Returns the caught player's id.
Future<String?> showHunterCatchDialog(
  BuildContext context, {
  required List<Member> members,
}) => showDialog<String>(
  context: context,
  builder: (_) => _HunterCatchDialog(members: members),
);

/// A player reports that they were caught themselves (R-CATCH-01).
Future<bool> showSelfCatchDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.back_hand_outlined, color: AppColors.hunter),
      title: Text(l10n.catchSelfTitle),
      content: Text(l10n.catchSelfText),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('confirmSelfCatch'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.catchSelfConfirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _HunterCatchDialog extends StatefulWidget {
  const _HunterCatchDialog({required this.members});

  final List<Member> members;

  @override
  State<_HunterCatchDialog> createState() => _HunterCatchDialogState();
}

class _HunterCatchDialogState extends State<_HunterCatchDialog> {
  late final _players = [
    for (final m in widget.members)
      if (m.isPlayer && !m.caught) m,
  ];
  String? _playerId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      icon: const Icon(Icons.back_hand_outlined, color: AppColors.hunter),
      title: Text(l10n.catchTitle),
      content: DropdownButtonFormField<String>(
        key: const Key('catchPlayer'),
        initialValue: _playerId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.catchWho,
          prefixIcon: const Icon(Icons.directions_run, color: AppColors.player),
        ),
        items: [
          for (final p in _players)
            DropdownMenuItem(value: p.id, child: Text(p.name)),
        ],
        onChanged: (v) => setState(() => _playerId = v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('confirmCatch'),
          onPressed: _playerId == null
              ? null
              : () => Navigator.pop(context, _playerId),
          child: Text(l10n.catchConfirm),
        ),
      ],
    );
  }
}
