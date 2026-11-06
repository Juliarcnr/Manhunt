import 'package:flutter/material.dart';

import '../../core/models/member.dart';
import '../../core/schedule/game_clock.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Once the time is up, hunters and players still in the game confirm who
/// else was caught (R-GAME-11). Cannot be dismissed: it closes when
/// [onConfirm] succeeds, or when someone else confirmed – then the caller
/// removes the returned route.
///
/// [players]: the players still in the game, with their real names (the
/// round is over, R-ANON-02). [onConfirm] gets the ids of those caught,
/// empty for "nobody else", and returns whether the dialog may close.
DialogRoute<void> timeUpDialogRoute(
  BuildContext context, {
  required List<Member> players,
  required Future<bool> Function(List<String> caughtIds) onConfirm,
}) => DialogRoute<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => PopScope(
    canPop: false,
    child: TimeUpDialog(players: players, onConfirm: onConfirm),
  ),
);

class TimeUpDialog extends StatefulWidget {
  const TimeUpDialog({
    super.key,
    required this.players,
    required this.onConfirm,
  });

  final List<Member> players;
  final Future<bool> Function(List<String> caughtIds) onConfirm;

  @override
  State<TimeUpDialog> createState() => _TimeUpDialogState();
}

class _TimeUpDialogState extends State<TimeUpDialog> {
  final _caught = <String>{};
  var _nobody = false;
  var _busy = false;

  bool get _chosen => _nobody || _caught.isNotEmpty;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final ok = await widget.onConfirm([
      for (final p in widget.players)
        if (_caught.contains(p.id)) p.id,
    ]);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      icon: const Icon(Icons.timer_off_outlined, color: AppColors.speedhunt),
      title: Text(l10n.timeUpTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.timeUpQuestion),
            const SizedBox(height: 8),
            for (final p in widget.players)
              CheckboxListTile(
                key: Key('timeUpCaught_${p.id}'),
                contentPadding: EdgeInsets.zero,
                value: _caught.contains(p.id),
                title: Text(p.name),
                secondary: const Icon(
                  Icons.directions_run,
                  color: AppColors.player,
                ),
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        if (v ?? false) {
                          _caught.add(p.id);
                          _nobody = false;
                        } else {
                          _caught.remove(p.id);
                        }
                      }),
              ),
            const Divider(),
            CheckboxListTile(
              key: const Key('timeUpNobody'),
              contentPadding: EdgeInsets.zero,
              value: _nobody,
              title: Text(l10n.timeUpNobody),
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _nobody = v ?? false;
                      if (_nobody) _caught.clear();
                    }),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.timeUpHint(GameClock.confirmTimeout.inMinutes),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('confirmTimeUp'),
          onPressed: _chosen && !_busy ? _confirm : null,
          child: Text(l10n.timeUpConfirm),
        ),
      ],
    );
  }
}
