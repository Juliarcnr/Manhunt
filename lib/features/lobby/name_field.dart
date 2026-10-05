import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Closes the keyboard when tapping anywhere outside the focused text field.
/// Flutter only does this by default on desktop/web, not on Android/iOS.
void dismissKeyboard(PointerDownEvent _) =>
    FocusManager.instance.primaryFocus?.unfocus();

class NameField extends StatelessWidget {
  const NameField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      key: const Key('nameField'),
      controller: controller,
      maxLength: 20,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      onTapOutside: dismissKeyboard,
      decoration: InputDecoration(
        labelText: l10n.yourName,
        hintText: l10n.yourNameHint,
        prefixIcon: const Icon(Icons.person_outline),
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? l10n.nameRequired : null,
    );
  }
}
