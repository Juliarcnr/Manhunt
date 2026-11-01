/// Countdown before the official start when the start time has already
/// passed (R-START-02).
const startCountdown = Duration(minutes: 1);

/// A start time further ahead than this counts as already passed: "14:00"
/// set at 14:05 means today's 14:00, not tomorrow's (R-START-02).
const startTimeLookahead = Duration(hours: 12);

/// When the official start of a round is, if the host starts it at [now]
/// (R-START-01, R-START-02): the next [startTime] (time of day, local) if it
/// is at most [startTimeLookahead] away, otherwise in [startCountdown].
/// Null without a start time: the round starts right away.
DateTime? plannedStartAt(DateTime now, {Duration? startTime}) {
  if (startTime == null) return null;
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
  return at.difference(local) > startTimeLookahead
      ? now.add(startCountdown)
      : at;
}
