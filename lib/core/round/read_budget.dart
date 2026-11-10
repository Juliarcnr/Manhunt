import '../models/game_settings.dart';
import '../models/member.dart';

/// Free Firestore reads per day (Firebase Spark), shared by all groups.
const dailyReadQuota = 50000;

/// From this share of [dailyReadQuota] for one round, the live positions are
/// shared less often (R-QUOTA-01).
const throttleShare = 0.8;

/// Hunters' live position normally and when throttled (R-HUNT-02, R-QUOTA-01).
const hunterLiveNormal = Duration(seconds: 5);
const hunterLiveThrottled = Duration(seconds: 15);

/// How often game masters and caught players see everyone live, normally and
/// when throttled (R-GM-05, R-QUOTA-01). Players upload their live position
/// just as often while someone watches.
const watcherLiveNormal = Duration(seconds: 15);
const watcherLiveThrottled = Duration(seconds: 30);

/// Rough number of Firestore reads of a whole round (R-QUOTA-01). The app
/// cannot query the real usage, so this is an estimate: every listener pays
/// for every changed document, and about half of the players are assumed to
/// be caught and watching (R-GM-07). Computer members count like people.
int estimateRoundReads({
  required GameSettings settings,
  required List<Member> members,
  required Duration hunterInterval,
  required Duration watcherInterval,
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
  final watched = watchers * (hunters + players) * updates(watcherInterval);
  // Every regular ping is read by hunters and watchers; with the setting
  // also by all players (R-SET-15).
  final pingReaders = hunters + watchers + (settings.sharedPings ? players : 0);
  final pings = players * updates(settings.pingInterval) * pingReaders;
  return (hunterLive + watched + pings).round();
}

/// Whether this round shares live positions less often: if it would use
/// [throttleShare] of the daily reads at the normal intervals (R-QUOTA-01).
bool liveThrottledFor(GameSettings settings, List<Member> members) =>
    estimateRoundReads(
      settings: settings,
      members: members,
      hunterInterval: hunterLiveNormal,
      watcherInterval: watcherLiveNormal,
    ) >=
    dailyReadQuota * throttleShare;

/// How often hunters share and see their live positions this round: every
/// 5 s, or every 15 s in a throttled round (R-QUOTA-01).
Duration hunterLiveIntervalFor(GameSettings settings, List<Member> members) =>
    liveThrottledFor(settings, members)
    ? hunterLiveThrottled
    : hunterLiveNormal;

/// How often game masters and caught players see everyone live, derived from
/// the round's hunter interval so every device decides the same: 15 s, or
/// 30 s in a throttled round (R-GM-05, R-QUOTA-01).
Duration watcherLiveIntervalFor(Duration hunterInterval) =>
    hunterInterval > hunterLiveNormal
    ? watcherLiveThrottled
    : watcherLiveNormal;

/// Share of the daily reads the round would use with the intervals it gets,
/// for the host's hint (R-QUOTA-02).
double estimatedQuotaShare(GameSettings settings, List<Member> members) {
  final hunterInterval = hunterLiveIntervalFor(settings, members);
  return estimateRoundReads(
        settings: settings,
        members: members,
        hunterInterval: hunterInterval,
        watcherInterval: watcherLiveIntervalFor(hunterInterval),
      ) /
      dailyReadQuota;
}
