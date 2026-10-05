import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/game_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../settings/settings_form.dart';
import 'name_field.dart';

/// Create a group with initial settings (R-SET-01 … R-SET-07).
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  var _settings = const GameSettings();
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .create(name: _name.text.trim(), settings: _settings);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
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
      appBar: AppBar(title: Text(l10n.createTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          children: [
            NameField(controller: _name),
            const SizedBox(height: 16),
            SettingsForm(
              settings: _settings,
              onChanged: (s) => setState(() => _settings = s),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _busy ? null : _create,
            child: Text(_busy ? l10n.createWorking : l10n.createButton),
          ),
        ),
      ),
    );
  }
}
