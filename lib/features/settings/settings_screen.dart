import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/game_settings.dart';
import '../../data/game_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import 'settings_form.dart';

/// Edit settings of an existing group (R-SET-08).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.initial,
  });

  final GroupSession session;
  final GameSettings initial;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late var _settings = widget.initial;
  var _busy = false;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(gameRepositoryProvider)
          .updateSettings(widget.session, _settings);
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.commonError('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsForm(
            settings: _settings,
            onChanged: (s) => setState(() => _settings = s),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const Key('saveSettings'),
            onPressed: _busy ? null : _save,
            child: Text(l10n.commonSave),
          ),
        ),
      ),
    );
  }
}
