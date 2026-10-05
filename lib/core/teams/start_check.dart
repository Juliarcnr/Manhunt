import '../models/game_settings.dart';
import '../models/member.dart';

/// Whether the host may press "Start" (R-LOBBY-06).
/// Uses the actual roles, so manual swaps (R-LOBBY-05) count, not hunterCount.
class StartCheck {
  StartCheck(GameSettings settings, List<Member> members)
    : settingsErrors = settings
          .validate()
          .where((e) => e != SettingsError.notEnoughPlayers)
          .toList(),
      hasUnassigned = members.any((m) => m.role == Role.unassigned),
      noHunter = !members.any((m) => m.isHunter),
      noPlayer = !members.any((m) => m.isPlayer);

  final List<SettingsError> settingsErrors;
  final bool hasUnassigned;
  final bool noHunter;
  final bool noPlayer;

  bool get canStart =>
      settingsErrors.isEmpty && !hasUnassigned && !noHunter && !noPlayer;
}
