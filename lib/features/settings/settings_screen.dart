import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/game_settings.dart';
import '../../data/game_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import 'settings_form.dart';

/// Edit settings of an existing group (R-SET-08). With [readOnly] (everyone
/// but the host) the settings are only shown, kept up to date (R-SET-14).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.initial,
    this.readOnly = false,
  });

  final GroupSession session;
  final GameSettings initial;
  final bool readOnly;

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
    final settings = widget.readOnly
        ? ref.watch(gameProvider).value?.settings ?? widget.initial
        : _settings;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.readOnly)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.settingsReadOnlyHint,
                      key: const Key('settingsReadOnlyHint'),
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          SettingsForm(
            settings: settings,
            onChanged: widget.readOnly
                ? null
                : (s) => setState(() => _settings = s),
          ),
        ],
      ),
      bottomNavigationBar: widget.readOnly
          ? null
          : SafeArea(
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
