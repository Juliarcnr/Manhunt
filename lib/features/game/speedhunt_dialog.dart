import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/game_settings.dart';
import '../../core/models/member.dart';
import '../../core/schedule/game_clock.dart';
import '../../core/schedule/speedhunt.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Hunter picks the player for a speedhunt (R-SPEED-02). Returns the player id.
/// [names] overrides the shown names, e.g. "Player 3" for anonymous players
/// (R-ANON-01). [targeted] are the previous speedhunts with their targets:
/// blocked players are greyed out, with the remaining pause (R-SET-19).
Future<String?> showSpeedhuntDialog(
  BuildContext context, {
  required List<Member> members,
  Map<String, String> names = const {},
  required GameSettings settings,
  List<Speedhunt> targeted = const [],
  required DateTime Function() now,
}) => showDialog<String>(
  context: context,
  builder: (_) => _SpeedhuntDialog(
    members: members,
    names: names,
    settings: settings,
    targeted: targeted,
    now: now,
  ),
);

/// [remaining] is the time until the speedhunt or target is possible again
/// (R-SET-11, R-SET-18, R-SET-19); [targetName] the shown name of the target.
String speedhuntDenialText(
  AppLocalizations l10n,
  SpeedhuntDenial d, {
  Duration remaining = Duration.zero,
  String targetName = '',
}) => switch (d) {
  SpeedhuntDenial.notHunting => l10n.speedhuntNotHunting,
  SpeedhuntDenial.tooEarly || SpeedhuntDenial.coolingDown =>
    l10n.speedhuntNotYet(formatCountdown(remaining)),
  SpeedhuntDenial.noneLeft => l10n.speedhuntNoneLeft,
  SpeedhuntDenial.alreadyRunning => l10n.speedhuntAlreadyRunning,
  SpeedhuntDenial.invalidTarget => l10n.speedhuntInvalidTarget,
  SpeedhuntDenial.sameTarget => l10n.speedhuntSameTarget,
  SpeedhuntDenial.targetCoolingDown => l10n.speedhuntTargetCoolingDown(
    targetName,
    formatCountdown(remaining),
  ),
};

class _SpeedhuntDialog extends StatefulWidget {
  const _SpeedhuntDialog({
    required this.members,
    required this.names,
    required this.settings,
    required this.targeted,
    required this.now,
  });

  final List<Member> members;
  final Map<String, String> names;
  final GameSettings settings;
  final List<Speedhunt> targeted;
  final DateTime Function() now;

  @override
  State<_SpeedhuntDialog> createState() => _SpeedhuntDialogState();
}

class _SpeedhuntDialogState extends State<_SpeedhuntDialog> {
  String? _playerId;

  /// Why the last picked player is blocked; shown inside the dialog, as a
  /// snack bar would be hidden behind it.
  String? _blockedText;

  /// Bumped to reset the dropdown after a blocked player was picked.
  int _resets = 0;

  String _name(Member m) => widget.names[m.id] ?? m.name;

  Map<String, TargetBlock> _blocks() {
    final now = widget.now();
    return {
      for (final m in widget.members)
        m.id: ?speedhuntTargetBlock(
          settings: widget.settings,
          previous: widget.targeted,
          targetId: m.id,
          now: now,
        ),
    };
  }

  void _pick(String? id, Map<String, TargetBlock> blocks) {
    final block = blocks[id];
    if (id == null || block == null) {
      setState(() {
        _playerId = id;
        _blockedText = null;
      });
      return;
    }
    final l10n = AppLocalizations.of(context);
    final member = widget.members.firstWhere((m) => m.id == id);
    setState(() {
      _resets++;
      _blockedText = switch (block.until) {
        null => speedhuntDenialText(l10n, SpeedhuntDenial.sameTarget),
        final until => speedhuntDenialText(
          l10n,
          SpeedhuntDenial.targetCoolingDown,
          remaining: until.difference(widget.now()),
          targetName: _name(member),
        ),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final blocks = _blocks();
    // A picked player may have become blocked meanwhile (new speedhunt).
    if (blocks.containsKey(_playerId)) _playerId = null;
    final players = [
      for (final m in widget.members)
        if (m.isPlayer && !m.caught) m,
    ];
    return AlertDialog(
      icon: const Icon(Icons.bolt, color: AppColors.speedhunt),
      title: Text(l10n.speedhuntTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: ValueKey(_resets),
            child: DropdownButtonFormField<String>(
              key: const Key('speedhuntPlayer'),
              initialValue: _playerId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.speedhuntWho,
                prefixIcon: const Icon(
                  Icons.directions_run,
                  color: AppColors.player,
                ),
              ),
              items: [
                for (final p in players)
                  DropdownMenuItem(
                    value: p.id,
                    // Blocked players stay tappable, to learn why (R-SET-19).
                    child: switch (blocks[p.id]) {
                      null => Text(_name(p)),
                      TargetBlock(until: null) => Text(
                        _name(p),
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      // Ticks by itself: the open menu is a route of its
                      // own and does not rebuild with the dialog.
                      TargetBlock(:final until?) => _WaitingPlayer(
                        name: _name(p),
                        until: until,
                        now: widget.now,
                      ),
                    },
                  ),
              ],
              // Fresh check: a pause may have run out while the menu was open.
              onChanged: (v) => _pick(v, _blocks()),
            ),
          ),
          if (_blockedText case final text?) ...[
            const SizedBox(height: 8),
            Text(
              text,
              key: const Key('speedhuntBlocked'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            l10n.speedhuntInfo(
              widget.settings.speedhuntPings,
              widget.settings.speedhuntInterval.inMinutes,
            ),
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (widget.settings.speedhuntFirstDelay > Duration.zero) ...[
            const SizedBox(height: 6),
            Text(
              l10n.speedhuntInfoDelay(
                widget.settings.speedhuntFirstDelay.inMinutes,
              ),
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('confirmSpeedhunt'),
          onPressed: _playerId == null
              ? null
              : () => Navigator.pop(context, _playerId),
          child: Text(l10n.speedhuntConfirm),
        ),
      ],
    );
  }
}

/// A player in their per-player pause, greyed out with a running countdown;
/// shown normally once it is over (R-SPEED-12).
class _WaitingPlayer extends StatefulWidget {
  const _WaitingPlayer({
    required this.name,
    required this.until,
    required this.now,
  });

  final String name;
  final DateTime until;
  final DateTime Function() now;

  @override
  State<_WaitingPlayer> createState() => _WaitingPlayerState();
}

class _WaitingPlayerState extends State<_WaitingPlayer> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
      if (!widget.until.isAfter(widget.now())) _ticker?.cancel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(widget.now());
    if (left <= Duration.zero) return Text(widget.name);
    return Text(
      AppLocalizations.of(context)
          .speedhuntPlayerWait(widget.name, formatCountdown(left)),
      style: const TextStyle(color: AppColors.textMuted),
    );
  }
}
