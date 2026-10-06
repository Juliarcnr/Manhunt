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

/// Name of the group, shown in the group overview (R-GROUPS-04).
class GroupNameField extends StatelessWidget {
  const GroupNameField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      key: const Key('groupNameField'),
      controller: controller,
      autofocus: autofocus,
      maxLength: 30,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      onFieldSubmitted: onSubmitted,
      onTapOutside: dismissKeyboard,
      decoration: InputDecoration(
        labelText: l10n.groupName,
        hintText: l10n.groupNameHint,
        prefixIcon: const Icon(Icons.groups_outlined),
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? l10n.groupNameRequired : null,
    );
  }
}
