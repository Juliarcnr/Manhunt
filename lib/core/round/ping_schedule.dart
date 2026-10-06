import '../models/geo_point.dart';
import '../schedule/game_clock.dart';
import '../schedule/speedhunt.dart';

enum PingKind { regular, speedhunt }

/// One planned location ping of a player. [id] is deterministic, so every
/// device (and a restarted app) agrees on it and a ping is never sent twice.
class PingSlot {
  const PingSlot({required this.id, required this.kind, required this.at});

  final String id;
  final PingKind kind;
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is PingSlot && other.id == id && other.at == at;

  @override
  int get hashCode => Object.hash(id, at);

  @override
  String toString() => 'PingSlot($id @ $at)';
}

/// All pings this player has to send: regular ones (R-PING-02) plus those of
/// speedhunts targeting them (R-SPEED-03). Nothing after the round's time.
List<PingSlot> playerPingSlots({
  required GameClock clock,
  required List<Speedhunt> speedhuntsOnMe,
}) {
  final slots = <PingSlot>[
    for (final (i, t) in clock.regularPingTimes().indexed)
      PingSlot(id: 'regular_${i + 1}', kind: PingKind.regular, at: t),
    for (final s in speedhuntsOnMe)
      for (final (i, t) in s.pingTimes().indexed)
        if (t.isBefore(clock.endAt))
          PingSlot(
            id: 'speedhunt_${s.startedAt.millisecondsSinceEpoch}_${i + 1}',
            kind: PingKind.speedhunt,
            at: t,
          ),
  ];
  slots.sort((a, b) => a.at.compareTo(b.at));
  return slots;
}

/// Slots that are due now and not yet sent. A ping that is more than [grace]
/// late (app was killed, phone off) is skipped instead of sending a stale
/// position under a wrong time.
List<PingSlot> duePings(
  List<PingSlot> slots, {
  required DateTime now,
  required Set<String> sentIds,
  Duration grace = const Duration(minutes: 3),
}) => [
  for (final s in slots)
    if (!s.at.isAfter(now) &&
        now.difference(s.at) <= grace &&
        !sentIds.contains(s.id))
      s,
];

/// Next slot strictly after [now], for "next ping in …" displays.
PingSlot? nextPing(List<PingSlot> slots, DateTime now) {
  for (final s in slots) {
    if (s.at.isAfter(now)) return s;
  }
  return null;
}

/// The speedhunt running right now, if any (R-SPEED-05).
Speedhunt? activeSpeedhunt(List<Speedhunt> all, DateTime now) {
  for (final s in all) {
    if (s.isActiveAt(now)) return s;
  }
  return null;
}

/// A location as stored in a ping or a hunter's live position.
class LocationFix {
  const LocationFix({required this.point, required this.at, this.accuracyM});

  final GeoPoint point;
  final DateTime at;
  final double? accuracyM;

  Map<String, Object?> toJson() => {
    ...point.toJson(),
    't': at.toUtc().toIso8601String(),
    if (accuracyM != null) 'acc': accuracyM,
  };

  factory LocationFix.fromJson(Map<String, Object?> json) => LocationFix(
    point: GeoPoint.fromJson(json),
    at: DateTime.parse(json['t']! as String),
    accuracyM: (json['acc'] as num?)?.toDouble(),
  );
}

/// A received ping (decrypted), for the hunters' map and the player's own
/// history (R-HUNT-03, R-HUNT-04, R-PLAY-01).
class PingRecord {
  const PingRecord({
    required this.playerId,
    required this.kind,
    required this.fix,
    this.slotId,
  });

  final String playerId;
  final PingKind kind;
  final LocationFix fix;

  /// The [PingSlot.id] it was sent for, e.g. `speedhunt_<ms>_2`.
  final String? slotId;

  /// Position within its speedhunt (1-based) for the ⚡1/⚡2/⚡3 labels
  /// (R-HUNT-07); null for regular pings.
  int? get speedhuntNumber {
    final id = slotId;
    if (kind != PingKind.speedhunt || id == null) return null;
    return int.tryParse(id.substring(id.lastIndexOf('_') + 1));
  }
}

/// Pings per player, chronological – basis for the numbered history.
Map<String, List<PingRecord>> pingsByPlayer(Iterable<PingRecord> pings) {
  final map = <String, List<PingRecord>>{};
  for (final p in pings) {
    (map[p.playerId] ??= []).add(p);
  }
  for (final list in map.values) {
    list.sort((a, b) => a.fix.at.compareTo(b.fix.at));
  }
  return map;
}

/// Latest regular ping of a chronological list, or null – the "last pings"
/// filter ignores speedhunt pings (R-HUNT-03).
PingRecord? lastRegularPing(List<PingRecord> pings) {
  for (final p in pings.reversed) {
    if (p.kind == PingKind.regular) return p;
  }
  return null;
}

/// Whether [next] holds a regular ping that [previous] did not – switches the
/// "last pings" filter back on (R-HUNT-08). Without [previous] (first load)
/// nothing counts as new.
bool hasNewRegularPing(List<PingRecord>? previous, List<PingRecord> next) {
  if (previous == null) return false;
  String key(PingRecord p) =>
      '${p.playerId}|${p.slotId ?? p.fix.at.toIso8601String()}';
  final known = {
    for (final p in previous)
      if (p.kind == PingKind.regular) key(p),
  };
  return next.any((p) => p.kind == PingKind.regular && !known.contains(key(p)));
}

/// Latest speedhunt ping per player – only these get a location pin on the
/// map, older ones stay small badges (R-HUNT-07). Ordered by slot (speedhunt
/// start, then number), not by the fix time: a ping resends the last known
/// fix, so ⚡1 and ⚡2 can carry the same time when the phone barely moved.
Map<String, PingRecord> latestSpeedhuntPings(Iterable<PingRecord> pings) {
  final latest = <String, PingRecord>{};
  for (final p in pings) {
    if (p.kind != PingKind.speedhunt) continue;
    final current = latest[p.playerId];
    if (current == null || _compareSpeedhuntSlots(p, current) > 0) {
      latest[p.playerId] = p;
    }
  }
  return latest;
}

/// Compares two speedhunt pings by their slot id `speedhunt_<ms>_<n>`;
/// falls back to the fix time if an id cannot be parsed.
int _compareSpeedhuntSlots(PingRecord a, PingRecord b) {
  (int, int)? order(PingRecord p) {
    final parts = p.slotId?.split('_');
    if (parts == null || parts.length != 3) return null;
    final start = int.tryParse(parts[1]);
    final number = int.tryParse(parts[2]);
    return start == null || number == null ? null : (start, number);
  }

  final (oa, ob) = (order(a), order(b));
  if (oa == null || ob == null) return a.fix.at.compareTo(b.fix.at);
  final byStart = oa.$1.compareTo(ob.$1);
  return byStart != 0 ? byStart : oa.$2.compareTo(ob.$2);
}

/// Next ping of a running speedhunt as number (1-based) and time, or null if
/// all its pings are done. Same for everyone, so it reveals no target
/// (R-SPEED-04, R-SPEED-08).
({int number, DateTime at})? nextSpeedhuntPing(Speedhunt s, DateTime now) {
  for (final (i, t) in s.pingTimes().indexed) {
    if (t.isAfter(now)) return (number: i + 1, at: t);
  }
  return null;
}
