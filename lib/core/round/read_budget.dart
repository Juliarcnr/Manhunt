import '../models/game_settings.dart';
import '../models/member.dart';
import 'observer.dart';

/// Free Firestore reads per day (Firebase Spark), shared by all groups.
const dailyReadQuota = 50000;

/// From this share of [dailyReadQuota] for one round, hunters see each other
/// less often (R-QUOTA-01).
const throttleShare = 0.7;

/// Hunters' live position normally and when throttled (R-HUNT-02, R-QUOTA-01).
const hunterLiveNormal = Duration(seconds: 5);
const hunterLiveThrottled = Duration(seconds: 15);

/// Rough number of Firestore reads of a whole round (R-QUOTA-01). The app
/// cannot query the real usage, so this is an estimate: every listener pays
/// for every changed document, and about half of the players are assumed to
/// be caught and watching (R-GM-07). Computer members count like people.
int estimateRoundReads({
  required GameSettings settings,
  required List<Member> members,
  required Duration hunterInterval,
}) {
  final hunters = members.where((m) => m.isHunter).length;
  final players = members.where((m) => m.isPlayer).length;
  final gameMasters = members.where((m) => m.isGameMaster).length;
  final seconds = settings.duration.inSeconds;
  final watchers = gameMasters + players / 2;
  double updates(Duration every) => seconds / every.inSeconds;

  // Hunters listen to each other.
  final hunterLive = hunters * updates(hunterInterval) * hunters;
  // Game masters and caught players fetch the hunters and get every
  // player's live position (R-GM-05).
  final watched = watchers * (hunters + players) * updates(playerLiveInterval);
  // Every regular ping is read by hunters and watchers; with the setting
  // also by all players (R-SET-15).
  final pingReaders = hunters + watchers + (settings.sharedPings ? players : 0);
  final pings = players * updates(settings.pingInterval) * pingReaders;
  return (hunterLive + watched + pings).round();
}

/// How often hunters share and see their live positions this round: every
/// 5 s, or every 15 s if the round would use [throttleShare] of the daily
/// reads (R-QUOTA-01).
Duration hunterLiveIntervalFor(GameSettings settings, List<Member> members) =>
    estimateRoundReads(
          settings: settings,
          members: members,
          hunterInterval: hunterLiveNormal,
        ) >=
        dailyReadQuota * throttleShare
    ? hunterLiveThrottled
    : hunterLiveNormal;

/// Share of the daily reads the round would use with [hunterLiveIntervalFor],
/// for the host's hint (R-QUOTA-02).
double estimatedQuotaShare(GameSettings settings, List<Member> members) =>
    estimateRoundReads(
      settings: settings,
      members: members,
      hunterInterval: hunterLiveIntervalFor(settings, members),
    ) /
    dailyReadQuota;
