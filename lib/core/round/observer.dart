import '../models/member.dart';
import '../schedule/game_clock.dart';

/// Players share their live position every this often while someone watches
/// (R-GM-05) – more often would get close to the free Firebase quota.
const playerLiveInterval = Duration(seconds: 15);

/// Whether [me] watches everyone live right now (R-GM-03, R-GM-07): game
/// masters always while the round runs, caught players only after they
/// [accepted] the warning (R-GM-08). Once the round is over, nothing is shared
/// live any more and everyone gets the usual end view (R-GM-09).
bool seesEveryoneLive(Member? me, GamePhase phase, {required bool accepted}) {
  if (me == null) return false;
  if (phase != GamePhase.headStart && phase != GamePhase.hunting) return false;
  return me.isGameMaster || (me.isPlayer && me.caught && accepted);
}

/// Whether a caught [me] still has to confirm the warning before seeing
/// everyone live (R-GM-08).
bool mustAcceptLiveView(
  Member? me,
  GamePhase phase, {
  required bool accepted,
}) =>
    me != null &&
    me.isPlayer &&
    me.caught &&
    !accepted &&
    (phase == GamePhase.headStart || phase == GamePhase.hunting);

/// Someone may watch the players live: a game master or a caught player
/// (R-GM-05). Without anyone, players share nothing.
bool hasLiveAudience(List<Member> members) =>
    members.any((m) => m.isGameMaster || (m.isPlayer && m.caught));
