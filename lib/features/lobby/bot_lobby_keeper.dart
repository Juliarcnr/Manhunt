import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/member.dart';
import '../../data/game_repository.dart';
import '../../state/bots.dart';
import '../../state/providers.dart';

/// Keeps the computer members in line with the settings while the lobby is
/// open (R-BOT-02, R-BOT-03); shows only [child].
class BotLobbyKeeper extends ConsumerStatefulWidget {
  const BotLobbyKeeper({
    super.key,
    required this.session,
    required this.game,
    required this.members,
    required this.child,
  });

  final GroupSession session;
  final GameInfo game;
  final List<Member>? members;
  final Widget child;

  @override
  ConsumerState<BotLobbyKeeper> createState() => _BotLobbyKeeperState();
}

class _BotLobbyKeeperState extends ConsumerState<BotLobbyKeeper> {
  late final _sync = BotLobbySync(
    session: widget.session,
    games: ref.read(gameRepositoryProvider),
    backend: ref.read(botBackendProvider),
  );

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(BotLobbyKeeper old) {
    super.didUpdateWidget(old);
    _update();
  }

  void _update() {
    final members = widget.members;
    // Before the members are loaded nothing is known about the bots.
    if (members == null || !ref.read(botsEnabledProvider)) return;
    unawaited(_sync.update(widget.game, members));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
