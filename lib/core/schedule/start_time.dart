/// Countdown before the official start without a start time, or when it has
/// already passed (R-START-01, R-START-02).
const startCountdown = Duration(minutes: 1);

/// A start time further ahead than this counts as already passed: "14:00"
/// set at 14:05 means today's 14:00, not tomorrow's (R-START-02).
const startTimeLookahead = Duration(hours: 12);

/// When the official start of a round is, if the host starts it at [now]
/// (R-START-01, R-START-02): the next [startTime] (time of day, local) if it
/// is at most [startTimeLookahead] away, otherwise in [startCountdown].
DateTime plannedStartAt(DateTime now, {Duration? startTime}) {
  final fallback = now.add(startCountdown);
  if (startTime == null) return fallback;
  final local = now.toLocal();
  DateTime onDay(int day) => DateTime(
    local.year,
    local.month,
    day,
    startTime.inHours,
    startTime.inMinutes % 60,
  );
  var at = onDay(local.day);
  if (!at.isAfter(local)) at = onDay(local.day + 1);
  return at.difference(local) > startTimeLookahead ? fallback : at;
}

/// How long "START" stays on screen after the countdown (R-START-05).
const startFlash = Duration(milliseconds: 1500);

/// What the countdown overlay shows at [now] (R-START-05): the whole seconds
/// left until [startAt] (rounded up), 0 for "START" right after it, null once
/// that is over.
int? countdownSecondsLeft(DateTime startAt, DateTime now) {
  final left = startAt.difference(now);
  if (left > Duration.zero) return (left.inMilliseconds / 1000).ceil();
  return -left < startFlash ? 0 : null;
}
