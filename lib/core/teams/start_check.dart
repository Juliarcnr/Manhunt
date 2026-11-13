import '../models/game_settings.dart';
import '../models/member.dart';

/// Whether the host may press "Start" (R-LOBBY-06).
/// Unassigned members simply do not play (R-LOBBY-11); only the host must
/// have a role, as they steer the round (R-LOBBY-13).
class StartCheck {
  StartCheck(GameSettings settings, List<Member> members, {String? adminId})
    : settingsErrors = settings.validate(),
      hostUnassigned = members.any(
        (m) => m.id == adminId && m.role == Role.unassigned,
      ),
      noHunter = !members.any((m) => m.isHunter),
      noPlayer = !members.any((m) => m.isPlayer);

  final List<SettingsError> settingsErrors;
  final bool hostUnassigned;
  final bool noHunter;
  final bool noPlayer;

  bool get canStart =>
      settingsErrors.isEmpty && !hostUnassigned && !noHunter && !noPlayer;
}
