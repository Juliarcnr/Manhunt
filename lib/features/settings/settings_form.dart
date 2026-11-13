import 'package:flutter/material.dart';

import '../../core/bots/bot_plan.dart';
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
    this.showBots = false,
  });

  final GameSettings settings;
  final ValueChanged<GameSettings>? onChanged;

  /// Debug builds: number of computer members (R-BOT-02) and very short
  /// rounds (R-BOT-08).
  final bool showBots;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = settings;
    final readOnly = onChanged == null;
    void change(GameSettings next) => onChanged?.call(next);

    /// Below [floor] (min ≤ floor) the − button stays active but only shows
    /// [floorMessage] instead of changing the value. With [values] (minutes,
    /// ascending) the value steps through these instead of [step].
    Widget minutes({
      Key? key,
      required String label,
      String? hint,
      required Duration value,
      int step = 1,
      int min = 0,
      int max = 0,
      List<int>? values,
      required GameSettings Function(Duration) apply,
      Duration floor = Duration.zero,
      String? floorMessage,
    }) {
      final current = value.inMinutes;
      final lower = values == null
          ? (current - step >= min ? current - step : null)
          : values.where((v) => v < current).lastOrNull;
      final higher = values == null
          ? (current + step <= max ? current + step : null)
          : values.where((v) => v > current).firstOrNull;
      return StepperTile(
        key: key,
        label: label,
        hint: hint,
        valueText: formatDuration(l10n, value),
        canDecrease: lower != null,
        canIncrease: higher != null,
        onDecrease: () {
          final next = Duration(minutes: lower!);
          if (next < floor && floorMessage != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(floorMessage)));
            return;
          }
          change(apply(next));
        },
        onIncrease: () => change(apply(Duration(minutes: higher!))),
        readOnly: readOnly,
      );
    }

    Widget count({
      Key? key,
      required String label,
      String? hint,
      required int value,
      required int min,
      required int max,
      required GameSettings Function(int) apply,
    }) => StepperTile(
      key: key,
      label: label,
      hint: hint,
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
            StartTimeTile(
              startTime: s.startTime,
              onChanged: readOnly
                  ? null
                  : (v) => change(s.copyWith(startTime: v)),
            ),
            if (showBots)
              SwitchListTile(
                key: const Key('skipCountdownSwitch'),
                contentPadding: const EdgeInsets.only(right: 8),
                title: Text(l10n.settingsSkipCountdown),
                subtitle: Text(
                  l10n.settingsSkipCountdownHint,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                value: s.skipCountdown,
                onChanged: readOnly
                    ? null
                    : (v) => change(s.copyWith(skipCountdown: v)),
              ),
            minutes(
              key: const Key('durationStepper'),
              label: l10n.settingsDuration,
              value: s.duration,
              values: durationChoices(testing: showBots),
              // A head start as long as the round is cut back (R-BOT-08).
              apply: (v) => s.copyWith(
                duration: v,
                headStart: s.headStart >= v ? Duration.zero : null,
              ),
            ),
            minutes(
              key: const Key('headStartStepper'),
              label: l10n.settingsHeadStart,
              value: s.headStart,
              values: headStartChoices(testing: showBots),
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
            minutes(
              key: const Key('speedhuntCooldown'),
              label: l10n.settingsSpeedhuntCooldown,
              hint: l10n.settingsSpeedhuntCooldownHint,
              value: s.speedhuntCooldown,
              step: 5,
              min: 0,
              max: 180,
              // The per-player pause is never shorter (R-SET-19).
              apply: (v) => s.copyWith(
                speedhuntCooldown: v,
                speedhuntRepeatCooldown: v > s.speedhuntRepeatCooldown
                    ? v
                    : null,
              ),
            ),
            SwitchListTile(
              key: const Key('speedhuntRepeatSwitch'),
              contentPadding: const EdgeInsets.only(right: 8),
              title: Text(l10n.settingsSpeedhuntRepeat),
              subtitle: Text(
                s.speedhuntRepeatTarget
                    ? l10n.settingsSpeedhuntRepeatOnHint
                    : l10n.settingsSpeedhuntRepeatOffHint,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              value: s.speedhuntRepeatTarget,
              onChanged: readOnly
                  ? null
                  : (v) => change(s.copyWith(speedhuntRepeatTarget: v)),
            ),
            if (s.speedhuntRepeatTarget)
              minutes(
                key: const Key('speedhuntRepeatCooldown'),
                label: l10n.settingsSpeedhuntRepeatCooldown,
                hint: l10n.settingsSpeedhuntRepeatCooldownHint,
                value: s.speedhuntRepeatCooldown,
                step: 5,
                min: 0,
                max: 180,
                floor: s.speedhuntCooldown,
                floorMessage: l10n.settingsSpeedhuntRepeatCooldownMin,
                apply: (v) => s.copyWith(speedhuntRepeatCooldown: v),
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
            // No hunter count: the roles are set in the lobby (R-LOBBY-04).
            count(
              key: const Key('hunterJokersStepper'),
              label: l10n.settingsJoker,
              hint: l10n.settingsJokerHint,
              value: s.hunterJokers,
              min: 0,
              max: GameSettings.maxHunterJokers,
              apply: (v) => s.copyWith(hunterJokers: v),
            ),
            SwitchListTile(
              key: const Key('playerJokerSwitch'),
              contentPadding: const EdgeInsets.only(right: 8),
              title: Text(l10n.settingsPlayerJoker),
              subtitle: Text(
                l10n.settingsPlayerJokerHint,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              // Either the joker or regular pings to everyone (R-SET-15).
              value: s.playerJokerAvailable,
              onChanged: readOnly
                  ? null
                  : (v) => change(
                      s.copyWith(
                        playerJokerEnabled: v,
                        sharedPings: v ? false : null,
                      ),
                    ),
            ),
            SwitchListTile(
              key: const Key('sharedPingsSwitch'),
              contentPadding: const EdgeInsets.only(right: 8),
              title: Text(l10n.settingsSharedPings),
              subtitle: Text(
                l10n.settingsSharedPingsHint,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              value: s.sharedPings,
              onChanged: readOnly
                  ? null
                  : (v) => change(
                      s.copyWith(
                        sharedPings: v,
                        playerJokerEnabled: v ? false : null,
                      ),
                    ),
            ),
            SwitchListTile(
              key: const Key('anonymousPlayersSwitch'),
              contentPadding: const EdgeInsets.only(right: 8),
              title: Text(l10n.settingsAnonymousPlayers),
              subtitle: Text(
                l10n.settingsAnonymousPlayersHint,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              value: s.anonymousPlayers,
              onChanged: readOnly
                  ? null
                  : (v) => change(s.copyWith(anonymousPlayers: v)),
            ),
            SwitchListTile(
              key: const Key('outsideLiveLocationSwitch'),
              contentPadding: const EdgeInsets.only(right: 8),
              title: Text(l10n.settingsOutsideLive),
              subtitle: Text(
                l10n.settingsOutsideLiveHint,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              value: s.outsideLiveLocation,
              onChanged: readOnly
                  ? null
                  : (v) => change(s.copyWith(outsideLiveLocation: v)),
            ),
          ],
        ),
        if (showBots)
          SectionCard(
            key: const Key('botSettings'),
            title: l10n.settingsSectionBots,
            children: [
              Text(
                l10n.settingsBotsHint,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              count(
                key: const Key('botCountStepper'),
                label: l10n.settingsBotCount,
                value: s.botCount,
                min: 0,
                max: maxBots,
                apply: (v) => s.copyWith(botCount: v),
              ),
            ],
          ),
      ],
    );
  }
}

/// Selectable round lengths in minutes (R-SET-02); when testing also 1 and
/// 5 minutes (R-BOT-08).
List<int> durationChoices({required bool testing}) => [
  if (testing) ...[1, 5],
  for (var m = 30; m <= 600; m += 15) m,
];

/// Selectable head starts in minutes (R-SET-03); when testing also every
/// minute below 5, to fit very short rounds (R-BOT-08).
List<int> headStartChoices({required bool testing}) => [
  0,
  if (testing) ...[1, 2, 3, 4],
  for (var m = 5; m <= 60; m += 5) m,
];

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
  SettingsError.speedhuntIntervalTooShort ||
  SettingsError.speedhuntRepeatCooldownTooShort => l10n.errorSpeedhuntInvalid,
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

/// Optional time of day of the official start (R-SET-21): tap to pick it,
/// × to remove it. Without [onChanged] only the value is shown (R-SET-14).
class StartTimeTile extends StatelessWidget {
  const StartTimeTile({
    super.key,
    required this.startTime,
    required this.onChanged,
  });

  final Duration? startTime;
  final ValueChanged<Duration?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final time = startTime;
    final onChanged = this.onChanged;
    final valueText = time == null
        ? l10n.settingsStartTimeNone
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay(hour: time.inHours, minute: time.inMinutes % 60),
            alwaysUse24HourFormat: true,
          );

    Future<void> pick() async {
      final picked = await showTimePicker(
        context: context,
        // Hours and minutes typed on the number pad, no clock dial.
        initialEntryMode: TimePickerEntryMode.inputOnly,
        initialTime: time == null
            ? const TimeOfDay(hour: 14, minute: 0)
            : TimeOfDay(hour: time.inHours, minute: time.inMinutes % 60),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (picked != null) {
        onChanged?.call(Duration(hours: picked.hour, minutes: picked.minute));
      }
    }

    return InkWell(
      key: const Key('startTimeTile'),
      onTap: onChanged == null ? null : pick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.settingsStartTime),
                  Text(
                    l10n.settingsStartTimeHint,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 12),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    valueText,
                    key: const Key('startTimeValue'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            if (onChanged != null && time != null)
              IconButton(
                key: const Key('startTimeClear'),
                tooltip: l10n.settingsStartTimeClear,
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close),
              ),
          ],
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
