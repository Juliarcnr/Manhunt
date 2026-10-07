import 'package:flutter/material.dart';

import '../../core/models/game_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Editable list of all game settings (R-SET-02 … R-SET-07).
/// Used both when creating a group and when editing it later (R-SET-08).
/// Without [onChanged] the form is read-only (R-SET-14).
class SettingsForm extends StatelessWidget {
  const SettingsForm({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final GameSettings settings;
  final ValueChanged<GameSettings>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = settings;
    final readOnly = onChanged == null;
    void change(GameSettings next) => onChanged?.call(next);

    Widget minutes({
      required String label,
      String? hint,
      required Duration value,
      required int step,
      required int min,
      required int max,
      required GameSettings Function(Duration) apply,
    }) => StepperTile(
      label: label,
      hint: hint,
      valueText: formatDuration(l10n, value),
      canDecrease: value.inMinutes - step >= min,
      canIncrease: value.inMinutes + step <= max,
      onDecrease: () => change(apply(value - Duration(minutes: step))),
      onIncrease: () => change(apply(value + Duration(minutes: step))),
      readOnly: readOnly,
    );

    Widget count({
      required String label,
      required int value,
      required int min,
      required int max,
      required GameSettings Function(int) apply,
    }) => StepperTile(
      label: label,
      valueText: '$value',
      canDecrease: value > min,
      canIncrease: value < max,
      onDecrease: () => change(apply(value - 1)),
      onIncrease: () => change(apply(value + 1)),
      readOnly: readOnly,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: l10n.settingsSectionGame,
          children: [
            minutes(
              label: l10n.settingsDuration,
              value: s.duration,
              step: 15,
              min: 30,
              max: 600,
              apply: (v) => s.copyWith(duration: v),
            ),
            minutes(
              label: l10n.settingsHeadStart,
              value: s.headStart,
              step: 5,
              min: 0,
              max: 60,
              apply: (v) => s.copyWith(headStart: v),
            ),
          ],
        ),
        SectionCard(
          title: l10n.settingsSectionPings,
          children: [
            minutes(
              label: l10n.settingsPingInterval,
              value: s.pingInterval,
              step: 5,
              min: 5,
              max: 60,
              apply: (v) => s.copyWith(pingInterval: v),
            ),
          ],
        ),
        SectionCard(
          title: l10n.settingsSectionSpeedhunt,
          children: [
            count(
              label: l10n.settingsSpeedhuntCount,
              value: s.speedhuntCount,
              min: 0,
              max: 10,
              apply: (v) => s.copyWith(speedhuntCount: v),
            ),
            minutes(
              label: l10n.settingsSpeedhuntEarliest,
              hint: l10n.settingsSpeedhuntEarliestHint,
              value: s.speedhuntEarliest,
              step: 5,
              min: 0,
              max: 600,
              apply: (v) => s.copyWith(speedhuntEarliest: v),
            ),
            count(
              label: l10n.settingsSpeedhuntPings,
              value: s.speedhuntPings,
              min: 1,
              max: 10,
              apply: (v) => s.copyWith(speedhuntPings: v),
            ),
            minutes(
              label: l10n.settingsSpeedhuntFirstDelay,
              hint: l10n.settingsSpeedhuntFirstDelayHint,
              value: s.speedhuntFirstDelay,
              step: 1,
              min: 0,
              max: 30,
              apply: (v) => s.copyWith(speedhuntFirstDelay: v),
            ),
            minutes(
              label: l10n.settingsSpeedhuntInterval,
              value: s.speedhuntInterval,
              step: 1,
              min: 1,
              max: 15,
              apply: (v) => s.copyWith(speedhuntInterval: v),
            ),
          ],
        ),
        SectionCard(
          title: l10n.settingsSectionTeams,
          children: [
            count(
              label: l10n.settingsHunterCount,
              value: s.hunterCount,
              min: 1,
              max: 14,
              apply: (v) => s.copyWith(hunterCount: v),
            ),
            SwitchListTile(
              key: const Key('jokerSwitch'),
              contentPadding: const EdgeInsets.only(right: 8),
              title: Text(l10n.settingsJoker),
              subtitle: Text(
                l10n.settingsJokerHint,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              value: s.jokerEnabled,
              onChanged: readOnly
                  ? null
                  : (v) => change(s.copyWith(jokerEnabled: v)),
            ),
            SwitchListTile(
              key: const Key('playerJokerSwitch'),
              contentPadding: const EdgeInsets.only(right: 8),
              title: Text(l10n.settingsPlayerJoker),
              subtitle: Text(
                l10n.settingsPlayerJokerHint,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              value: s.playerJokerEnabled,
              onChanged: readOnly
                  ? null
                  : (v) => change(s.copyWith(playerJokerEnabled: v)),
            ),
          ],
        ),
      ],
    );
  }
}

String formatDuration(AppLocalizations l10n, Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h == 0 ? l10n.minutes(m) : l10n.hoursMinutes(h, m);
}

/// Message for each validation problem, or null if not shown to users.
String settingsErrorText(AppLocalizations l10n, SettingsError e) => switch (e) {
  SettingsError.durationTooShort => l10n.errorDurationTooShort,
  SettingsError.headStartInvalid => l10n.errorHeadStartInvalid,
  SettingsError.pingIntervalTooShort => l10n.errorPingIntervalTooShort,
  SettingsError.speedhuntCountInvalid ||
  SettingsError.speedhuntPingsInvalid ||
  SettingsError.speedhuntIntervalTooShort => l10n.errorSpeedhuntInvalid,
  SettingsError.hunterCountInvalid => l10n.errorHunterCountInvalid,
  SettingsError.notEnoughPlayers => l10n.errorNotEnoughPlayers,
  SettingsError.areaMissing => l10n.errorAreaMissing,
};

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textMuted,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class StepperTile extends StatelessWidget {
  const StepperTile({
    super.key,
    required this.label,
    this.hint,
    required this.valueText,
    required this.canDecrease,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
    this.readOnly = false,
  });

  final String label;

  /// Optional explanation shown muted below the label.
  final String? hint;
  final String valueText;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  /// Shows only the value, without +/− buttons (R-SET-14).
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final value = Text(
      valueText,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: hint == null
                ? Text(label)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label),
                      Text(
                        hint!,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
          ),
          if (readOnly)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 12),
                child: Center(widthFactor: 1, child: value),
              ),
            )
          else ...[
            IconButton(
              tooltip: '−',
              onPressed: canDecrease ? onDecrease : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(width: 92, child: value),
            IconButton(
              tooltip: '+',
              onPressed: canIncrease ? onIncrease : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ],
      ),
    );
  }
}
