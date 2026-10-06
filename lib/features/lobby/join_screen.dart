import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/groups/group_list.dart';
import '../../data/game_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import 'name_field.dart';

/// Join an existing group by code (R-LOBBY-01, R-LOBBY-03).
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .join(code: _code.text, name: _name.text.trim());
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e) {
          InvalidCodeException() => l10n.joinInvalidCode,
          GroupNotFoundException() => l10n.joinNotFound,
          GroupLimitException() => l10n.groupsLimitReached(GroupList.maxGroups),
          _ => l10n.commonError('$e'),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.joinTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('codeField'),
              textInputAction: TextInputAction.next,
              onTapOutside: dismissKeyboard,
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              style: const TextStyle(
                fontSize: 22,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                labelText: l10n.joinCode,
                hintText: l10n.joinCodeHint,
                prefixIcon: const Icon(Icons.key_outlined),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
            NameField(controller: _name),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _busy ? null : _join,
            child: Text(_busy ? l10n.joinWorking : l10n.joinButton),
          ),
        ),
      ),
    );
  }
}
