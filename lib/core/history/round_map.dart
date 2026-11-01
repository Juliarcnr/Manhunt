import '../models/geo_point.dart';
import '../models/member.dart';
import '../round/ping_schedule.dart';
import '../schedule/speedhunt.dart';
import 'round_summary.dart';

/// Id of the [i]-th player of a [RoundMap] (colour order).
String roundMapPlayerId(int i) => 'p$i';

/// Id of the [i]-th hunter of a [RoundMap].
String roundMapHunterId(int i) => 'h$i';

/// One speedhunt of a [RoundMap]: when it started, on whom (if any ⚡ ping of
/// the target arrived) and its ping times, ended early by a catch
/// (R-SPEED-10).
class RoundMapSpeedhunt {
  const RoundMapSpeedhunt({
    required this.startedAt,
    required this.pingTimes,
    this.targetId,
  });

  final DateTime startedAt;
  final List<DateTime> pingTimes;

  /// A [roundMapPlayerId], or null if no ping of the target is known.
  final String? targetId;

  /// Slot id of the [number]-th ping (1-based), as in [playerPingSlots].
  String slotId(int number) =>
      'speedhunt_${startedAt.millisecondsSinceEpoch}_$number';
}

/// What the map showed once the round was over (R-GAME-06), kept in the
/// group history (R-HIST-04): play area, all pings, the hunters at every
/// ping time (R-HIST-05) and their last live position. Names are frozen at
/// round end – the real ones (R-ANON-02) – and members are numbered instead
/// of carrying their uid. Stored encrypted and compact.
class RoundMap {
  const RoundMap({
    required this.area,
    required this.startedAt,
    required this.endedAt,
    required this.pingInterval,
    required this.players,
    required this.hunters,
    this.pings = const [],
    this.hunterSnaps = const [],
    this.lastHunters = const {},
    this.catches = const [],
    this.speedhunts = const [],
  });

  final List<GeoPoint> area;
  final DateTime startedAt;

  /// Time up, the hunters' win (R-GAME-08) or the host's abort (R-GAME-07).
  final DateTime endedAt;
  final Duration pingInterval;

  /// Names in colour order; index i belongs to [roundMapPlayerId] (i).
  final List<String> players;

  /// Names; index i belongs to [roundMapHunterId] (i).
  final List<String> hunters;

  /// Players' regular and ⚡ pings, by [roundMapPlayerId].
  final List<PingRecord> pings;

  /// The hunters' positions at every regular and ⚡ ping time, by
  /// [roundMapHunterId], with the slot id of that ping time.
  final List<PingRecord> hunterSnaps;

  /// Last live position of each hunter, by [roundMapHunterId].
  final Map<String, LocationFix> lastHunters;

  /// Earliest catch of each caught player, by [roundMapPlayerId].
  final List<CatchRecord> catches;

  /// Oldest first.
  final List<RoundMapSpeedhunt> speedhunts;

  List<String> get playerIds => [
    for (var i = 0; i < players.length; i++) roundMapPlayerId(i),
  ];

  List<String> get hunterIds => [
    for (var i = 0; i < hunters.length; i++) roundMapHunterId(i),
  ];

  /// Display names by player and hunter id.
  Map<String, String> get names => {
    for (final (i, n) in players.indexed) roundMapPlayerId(i): n,
    for (final (i, n) in hunters.indexed) roundMapHunterId(i): n,
  };

  /// Builds the map at round end. [playerOrder] are the players' uids in
  /// colour order (by anonymous number, R-ANON-01); players missing there
  /// follow in member order. Pings of people who left the group are dropped,
  /// like their catches in the [RoundSummary].
  factory RoundMap.build({
    required List<GeoPoint> area,
    required DateTime startedAt,
    required DateTime endedAt,
    required Duration pingInterval,
    required List<Member> members,
    List<String> playerOrder = const [],
    List<PingRecord> pings = const [],
    List<PingRecord> hunterSnaps = const [],
    Map<String, LocationFix> hunterLocations = const {},
    List<CatchRecord> catches = const [],
    List<Speedhunt> speedhunts = const [],
  }) {
    final byId = {for (final m in members) m.id: m};
    final playerUids = [
      for (final id in playerOrder)
        if (byId[id]?.isPlayer ?? false) id,
      for (final m in members)
        if (m.isPlayer && !playerOrder.contains(m.id)) m.id,
    ];
    final hunterUids = [
      for (final m in members)
        if (m.isHunter) m.id,
    ];
    final playerIdOf = {
      for (final (i, uid) in playerUids.indexed) uid: roundMapPlayerId(i),
    };
    final hunterIdOf = {
      for (final (i, uid) in hunterUids.indexed) uid: roundMapHunterId(i),
    };
    PingRecord? rename(PingRecord p, Map<String, String> ids) =>
        switch (ids[p.playerId]) {
          final id? => PingRecord(
            playerId: id,
            kind: p.kind,
            fix: p.fix,
            slotId: p.slotId,
          ),
          null => null,
        };
    final mapPings = [for (final p in pings) ?rename(p, playerIdOf)];
    final firstCatch = <String, CatchRecord>{};
    for (final c in catches) {
      final id = playerIdOf[c.playerId];
      if (id == null) continue;
      final known = firstCatch[id];
      if (known == null || c.at.isBefore(known.at)) {
        firstCatch[id] = CatchRecord(playerId: id, at: c.at);
      }
    }
    // The public speedhunts carry no target (R-SPEED-04); the target is
    // whoever sent its ⚡ pings.
    final targets = {
      for (final s in speedhuntsFromPings(mapPings))
        s.startedAt.millisecondsSinceEpoch: s.playerId,
    };
    return RoundMap(
      area: area,
      startedAt: startedAt,
      endedAt: endedAt,
      pingInterval: pingInterval,
      players: [for (final uid in playerUids) byId[uid]!.name],
      hunters: [for (final uid in hunterUids) byId[uid]!.name],
      pings: mapPings,
      hunterSnaps: [for (final p in hunterSnaps) ?rename(p, hunterIdOf)],
      lastHunters: {
        for (final e in hunterLocations.entries) ?hunterIdOf[e.key]: e.value,
      },
      catches: firstCatch.values.toList()..sort((a, b) => a.at.compareTo(b.at)),
      speedhunts: [
        for (final s in [
          ...speedhunts,
        ]..sort((a, b) => a.startedAt.compareTo(b.startedAt)))
          RoundMapSpeedhunt(
            startedAt: s.startedAt,
            pingTimes: [
              for (final t in s.pingTimes())
                if (t.isBefore(endedAt)) t,
            ],
            targetId: targets[s.startedAt.millisecondsSinceEpoch],
          ),
      ],
    );
  }

  // Compact JSON: a whole round must fit into one encrypted document
  // (Firestore: 1 MiB), and less data means fewer bytes on every phone.

  static int _sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  static DateTime _time(Object? sec) =>
      DateTime.fromMillisecondsSinceEpoch((sec! as int) * 1000, isUtc: true);

  /// About 10 cm – more than GPS can tell anyway.
  static double _round(double v) => (v * 1e6).round() / 1e6;

  static List<Object> _fix(LocationFix f) => [
    _round(f.point.lat),
    _round(f.point.lng),
    _sec(f.at),
  ];

  static LocationFix _fixFrom(Object? json) {
    final list = json! as List<Object?>;
    return LocationFix(
      point: GeoPoint(
        (list[0]! as num).toDouble(),
        (list[1]! as num).toDouble(),
      ),
      at: _time(list[2]),
    );
  }

  /// Index from an id like `p3`.
  static int _index(String id) => int.parse(id.substring(1));

  static Map<String, Object?> _ping(PingRecord p, String key) => {
    key: _index(p.playerId),
    if (p.kind == PingKind.speedhunt) 'k': 's',
    's': p.slotId,
    'f': _fix(p.fix),
  };

  static PingRecord _pingFrom(
    Object? json,
    String key,
    String Function(int) id,
  ) {
    final map = json! as Map<String, Object?>;
    return PingRecord(
      playerId: id(map[key]! as int),
      kind: map['k'] == 's' ? PingKind.speedhunt : PingKind.regular,
      slotId: map['s'] as String?,
      fix: _fixFrom(map['f']),
    );
  }

  Map<String, Object?> toJson() => {
    'area': [
      for (final p in area) [_round(p.lat), _round(p.lng)],
    ],
    'start': _sec(startedAt),
    'end': _sec(endedAt),
    'pingSec': pingInterval.inSeconds,
    'players': players,
    'hunters': hunters,
    'pings': [for (final p in pings) _ping(p, 'p')],
    'hunterSnaps': [for (final p in hunterSnaps) _ping(p, 'h')],
    'lastHunters': [
      for (final e in lastHunters.entries)
        {'h': _index(e.key), 'f': _fix(e.value)},
    ],
    'catches': [
      for (final c in catches) {'p': _index(c.playerId), 't': _sec(c.at)},
    ],
    'speedhunts': [
      for (final s in speedhunts)
        {
          's': s.startedAt.millisecondsSinceEpoch,
          'p': ?switch (s.targetId) {
            final id? => _index(id),
            null => null,
          },
          't': [for (final t in s.pingTimes) _sec(t)],
        },
    ],
  };

  factory RoundMap.fromJson(Map<String, Object?> json) {
    List<Object?> list(String key) => json[key] as List<Object?>? ?? const [];
    return RoundMap(
      area: [
        for (final p in list('area'))
          if (p case [final num lat, final num lng])
            GeoPoint(lat.toDouble(), lng.toDouble()),
      ],
      startedAt: _time(json['start']),
      endedAt: _time(json['end']),
      pingInterval: Duration(seconds: json['pingSec']! as int),
      players: list('players').cast<String>(),
      hunters: list('hunters').cast<String>(),
      pings: [
        for (final p in list('pings')) _pingFrom(p, 'p', roundMapPlayerId),
      ],
      hunterSnaps: [
        for (final p in list('hunterSnaps'))
          _pingFrom(p, 'h', roundMapHunterId),
      ],
      lastHunters: {
        for (final e in list('lastHunters').cast<Map<String, Object?>>())
          roundMapHunterId(e['h']! as int): _fixFrom(e['f']),
      },
      catches: [
        for (final c in list('catches').cast<Map<String, Object?>>())
          CatchRecord(
            playerId: roundMapPlayerId(c['p']! as int),
            at: _time(c['t']),
          ),
      ],
      speedhunts: [
        for (final s in list('speedhunts').cast<Map<String, Object?>>())
          RoundMapSpeedhunt(
            startedAt: DateTime.fromMillisecondsSinceEpoch(
              s['s']! as int,
              isUtc: true,
            ),
            targetId: switch (s['p']) {
              final int i => roundMapPlayerId(i),
              _ => null,
            },
            pingTimes: [for (final t in s['t']! as List<Object?>) _time(t)],
          ),
      ],
    );
  }
}

/// Each hunter's positions at the regular ping times, chronological – shown
/// like a player's numbered history (R-HIST-05).
Map<String, List<PingRecord>> hunterHistories(List<PingRecord> hunterSnaps) =>
    pingsByPlayer(regularPings(hunterSnaps));

/// The hunters' positions at the ping times of [speedhunt] (R-HIST-05).
List<PingRecord> hunterSnapsForSpeedhunt(
  List<PingRecord> hunterSnaps,
  SpeedhuntPings speedhunt,
) {
  final prefix = 'speedhunt_${speedhunt.startedAt.millisecondsSinceEpoch}_';
  return [
    for (final p in hunterSnaps)
      if (p.kind == PingKind.speedhunt &&
          (p.slotId?.startsWith(prefix) ?? false))
        p,
  ];
}

/// One position of the timeline (R-HIST-07): a regular ping time or one ping
/// of a speedhunt.
class TimelineStep {
  const TimelineStep({
    required this.at,
    required this.slotId,
    required this.kind,
    this.targetId,
    this.speedhuntNumber,
  });

  final DateTime at;

  /// As in [PingSlot.id]: `regular_<n>` or `speedhunt_<ms>_<n>`.
  final String slotId;
  final PingKind kind;

  /// The speedhunt's target, if known; null for regular steps.
  final String? targetId;

  /// 1-based; null for regular steps.
  final int? speedhuntNumber;
}

/// All regular ping times of the round and the ping times of its
/// speedhunts, in time order (regular first when both fall together).
List<TimelineStep> timelineSteps(RoundMap map) {
  final steps = <TimelineStep>[
    for (
      var (n, t) = (1, map.startedAt.add(map.pingInterval));
      t.isBefore(map.endedAt) && map.pingInterval > Duration.zero;
      (n, t) = (n + 1, t.add(map.pingInterval))
    )
      TimelineStep(at: t, slotId: 'regular_$n', kind: PingKind.regular),
    for (final s in map.speedhunts)
      for (final (i, t) in s.pingTimes.indexed)
        TimelineStep(
          at: t,
          slotId: s.slotId(i + 1),
          kind: PingKind.speedhunt,
          targetId: s.targetId,
          speedhuntNumber: i + 1,
        ),
  ];
  // Stable: regular steps come first in the list.
  _stableSort(steps, (a, b) => a.at.compareTo(b.at));
  return steps;
}

/// Who is on the map at one [TimelineStep].
class TimelineFrame {
  const TimelineFrame({required this.players, required this.hunters});

  /// Players' pings for the step, by player id.
  final Map<String, PingRecord> players;

  /// Hunters' positions at the step, by hunter id.
  final Map<String, LocationFix> hunters;
}

/// The pings of everyone still in the game at [step] (R-HIST-07): at a
/// regular ping time every player not caught before it, at a speedhunt ping
/// only its target – nobody else pinged then –, and always all hunters.
/// Whoever did not send a ping for the step is left out.
TimelineFrame timelineAt(RoundMap map, TimelineStep step) {
  final caughtAt = {for (final c in map.catches) c.playerId: c.at};
  bool inGame(String id) => !(caughtAt[id]?.isBefore(step.at) ?? false);
  return TimelineFrame(
    players: {
      for (final p in map.pings)
        if (p.slotId == step.slotId && inGame(p.playerId)) p.playerId: p,
    },
    hunters: {
      for (final p in map.hunterSnaps)
        if (p.slotId == step.slotId) p.playerId: p.fix,
    },
  );
}

/// Stable insertion sort (`List.sort` is not stable) – the lists are short,
/// a few hundred steps at most.
void _stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  for (var i = 1; i < list.length; i++) {
    final item = list[i];
    var j = i - 1;
    while (j >= 0 && compare(list[j], item) > 0) {
      list[j + 1] = list[j];
      j--;
    }
    list[j + 1] = item;
  }
}

/// Number of the next round (R-HIST-02): one more than the highest so far,
/// so numbers do not repeat after a round was deleted (R-HIST-06).
int nextRoundNumber(Iterable<int> existing) =>
    existing.fold(0, (a, b) => a > b ? a : b) + 1;
