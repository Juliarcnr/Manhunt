import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bots/bot_plan.dart';
import '../core/history/round_summary.dart';
import '../core/models/member.dart';
import '../core/round/ping_schedule.dart';
import '../core/schedule/speedhunt.dart';
import '../data/bot_backend.dart';
import '../data/bot_location_service.dart';
import '../data/game_repository.dart';
import '../data/location_service.dart';
import 'round_engine.dart';

/// Computer members (R-BOT-01): always in debug builds, in release builds
/// only with `--dart-define=MANHUNT_BOTS=true`.
final botsEnabledProvider = Provider<bool>(
  (ref) => kDebugMode || const bool.fromEnvironment('MANHUNT_BOTS'),
);

final botBackendProvider = Provider<BotBackend>((ref) => FirebaseBotBackend());

/// Runs [work] for the latest value only, one at a time: values arriving
/// meanwhile replace each other.
class _Latest<T> {
  _Latest(this.work);

  final Future<void> Function(T value) work;
  T? _next;
  var _hasNext = false;
  Future<void>? _running;

  Future<void> add(T value) {
    _next = value;
    _hasNext = true;
    return _running ??= _drain().whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    while (_hasNext) {
      final value = _next as T;
      _hasNext = false;
      _next = null;
      try {
        await work(value);
      } on Exception catch (e) {
        debugPrint('[manhunt] bots: $e');
      }
    }
  }
}

/// Keeps this phone's bots in line with the settings while the group is in
/// the lobby (R-BOT-02, R-BOT-03): the carrier joins or removes its bots, the
/// host gives every bot the role of its kind.
class BotLobbySync {
  BotLobbySync({
    required this.session,
    required this.games,
    required this.backend,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final GroupSession session;
  final GameRepository games;
  final BotBackend backend;
  final DateTime Function() _now;
  late final _latest = _Latest<({GameInfo game, List<Member> members})>(
    (v) => _sync(v.game, v.members),
  );

  /// Bots this phone just added or removed that the member list does not
  /// reflect yet: until it does, nothing more happens, so no bot is added
  /// twice. Given up after [_maxWait].
  final _joining = <String>{};
  final _leaving = <String>{};
  DateTime? _waitingSince;
  static const _maxWait = Duration(seconds: 20);

  /// Call with every change of the game or the members.
  Future<void> update(GameInfo game, List<Member> members) =>
      _latest.add((game: game, members: members));

  Future<void> _sync(GameInfo game, List<Member> members) async {
    if (game.status != GameStatus.lobby) return;
    final ids = {for (final m in members) m.id};
    _joining.removeWhere(ids.contains);
    _leaving.removeWhere((id) => !ids.contains(id));
    if (_joining.isNotEmpty || _leaving.isNotEmpty) {
      final since = _waitingSince;
      if (since != null && _now().difference(since) < _maxWait) return;
      _joining.clear();
      _leaving.clear();
    }
    _waitingSince = null;
    final settings = game.settings;
    if (settings.botHunters == 0 &&
        settings.botPlayers == 0 &&
        !members.any(isBot)) {
      return;
    }
    final known = await backend.knownIds();
    final actions = botActions(
      settings: settings,
      members: members,
      myId: session.userId,
      myBotIds: {
        for (final id in known.values)
          if (ids.contains(id)) id,
      },
      isHost: game.adminId == session.userId,
    );
    if (actions.isEmpty) return;
    _waitingSince = _now();
    final slotOf = {for (final e in known.entries) e.value: e.key};
    for (final id in actions.remove) {
      final device = await backend.open(slotOf[id]!);
      _leaving.add(id);
      await device.games.removeMember(_botSession(session, id), id);
    }
    final free = [
      for (var slot = 1; slot <= BotBackend.slots; slot++)
        if (!ids.contains(known[slot])) slot,
    ];
    for (final (i, bot) in actions.create.indexed) {
      if (i >= free.length) break;
      final device = await backend.open(free[i]);
      _joining.add(device.id);
      await device.games.joinGame(
        _botSession(session, device.id),
        name: bot.name,
      );
    }
    if (actions.assign.isNotEmpty) {
      await games.setRoles(session, actions.assign);
    }
  }
}

/// The carrier's group session as seen by the bot [id].
GroupSession _botSession(GroupSession carrier, String id) =>
    GroupSession(code: carrier.code, crypto: carrier.crypto, userId: id);

/// Runs this phone's bots during a round, each like a phone of its own
/// (R-BOT-05). Belongs to the game screen, like the own [RoundEngine].
class BotSquad {
  BotSquad({
    required this.session,
    required this.backend,
    required this.anchor,
    required this.notice,
    this.now,
    this.onLog,
  });

  final GroupSession session;
  final BotBackend backend;

  /// The carrier's current position (R-BOT-04).
  final LocationFix? Function() anchor;
  final TrackingNotice notice;
  final DateTime Function()? now;
  final void Function(String message)? onLog;

  final _runners = <String, BotRunner>{};
  late final _latest = _Latest<List<Member>>(_sync);
  var _disposed = false;

  /// Running bots by id – for tests.
  Map<String, BotRunner> get runners => Map.unmodifiable(_runners);

  /// Call with every change of the members.
  Future<void> update(List<Member> members) => _latest.add(members);

  Future<void> _sync(List<Member> members) async {
    final bots = {
      for (final m in members)
        if (isBot(m)) m.id: m.name,
    };
    for (final id in [..._runners.keys]) {
      if (!bots.containsKey(id)) await _runners.remove(id)!.dispose();
    }
    if (bots.isEmpty || _disposed) return;
    final known = await backend.knownIds();
    for (final MapEntry(key: slot, value: id) in known.entries) {
      final name = bots[id];
      if (name == null || _runners.containsKey(id)) continue;
      final device = await backend.open(slot);
      if (_disposed) return;
      _runners[id] = BotRunner(
        session: _botSession(session, id),
        device: device,
        location: BotLocationService(anchor: anchor),
        notice: notice,
        now: now,
        onLog: (m) => onLog?.call('$name: $m'),
      )..start();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final runner in _runners.values) {
      await runner.dispose();
    }
    _runners.clear();
  }
}

/// One bot during a round: its own [RoundEngine], fed from its own streams –
/// the same as the providers do for the phone's owner.
class BotRunner {
  BotRunner({
    required this.session,
    required this.device,
    required LocationService location,
    required TrackingNotice notice,
    DateTime Function()? now,
    void Function(String message)? onLog,
  }) : engine = RoundEngine(
         session: session,
         rounds: device.rounds,
         location: location,
         notice: notice,
         now: now,
         onLog: onLog,
       );

  final GroupSession session;
  final BotDevice device;
  final RoundEngine engine;

  GameInfo? _game;
  Member? _me;
  List<Speedhunt> _speedhunts = const [];
  List<Speedhunt> _speedhuntsOnMe = const [];
  List<CatchRecord> _catches = const [];
  final _subscriptions = <StreamSubscription<Object?>>[];
  StreamSubscription<Object?>? _onMe;
  StreamSubscription<Object?>? _jokerRequests;

  void start() {
    _subscriptions
      ..add(
        device.games.watchGame(session).listen((g) {
          _game = g;
          _feed();
        }, onError: _error),
      )
      ..add(
        device.games.watchMembers(session).listen((members) {
          _me = members.where((m) => m.id == session.userId).firstOrNull;
          _playerStreams();
          _feed();
        }, onError: _error),
      )
      ..add(
        device.rounds.watchSpeedhunts(session).listen((s) {
          _speedhunts = s;
          _feed();
        }, onError: _error),
      )
      ..add(
        device.games.watchCatches(session).listen((c) {
          _catches = c;
          _feed();
        }, onError: _error),
      );
  }

  /// Speedhunts on the bot and joker requests only as a player – the rules
  /// hide joker requests from hunters.
  void _playerStreams() {
    final isPlayer = _me?.isPlayer ?? false;
    if (isPlayer && _onMe == null) {
      _onMe = device.rounds.watchSpeedhuntsOnMe(session).listen((s) {
        _speedhuntsOnMe = s;
        _feed();
      }, onError: _error);
      _jokerRequests = device.rounds
          .watchJokerRequests(session)
          .listen(engine.updateJokerRequests, onError: _error);
    } else if (!isPlayer && _onMe != null) {
      unawaited(_onMe?.cancel());
      unawaited(_jokerRequests?.cancel());
      _onMe = null;
      _jokerRequests = null;
      _speedhuntsOnMe = const [];
    }
  }

  void _feed() => engine.update(
    game: _game,
    me: _me,
    speedhuntsOnMe: applyCatches(_speedhuntsOnMe, _catches),
    speedhunts: applyCatches(_speedhunts, _catches),
  );

  void _error(Object e) => engine.note('stream error: $e');

  Future<void> dispose() async {
    for (final s in [..._subscriptions, ?_onMe, ?_jokerRequests]) {
      await s.cancel();
    }
    _subscriptions.clear();
    await engine.dispose();
  }
}
