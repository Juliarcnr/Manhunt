import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'history_screen.dart';

class HistoryButton extends StatelessWidget {
  const HistoryButton({super.key, this.isHost = false});

  /// The host may delete rounds (R-HIST-06).
  final bool isHost;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('historyButton'),
    icon: const Icon(Icons.history),
    tooltip: AppLocalizations.of(context).historyTitle,
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => HistoryScreen(isHost: isHost)),
    ),
  );
}
