import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/schedule/game_clock.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Big countdown over the map until the official start (R-START-05). The
/// last three seconds pulse, then "START" pulses once. Taps go through to the
/// map, so everyone can look around while waiting.
class StartCountdownOverlay extends StatefulWidget {
  const StartCountdownOverlay({super.key, required this.secondsLeft});

  /// From `countdownSecondsLeft`; 0 shows "START".
  final int secondsLeft;

  /// The last seconds pulse.
  static const pulseFrom = 3;

  @override
  State<StartCountdownOverlay> createState() => _StartCountdownOverlayState();
}

class _StartCountdownOverlayState extends State<StartCountdownOverlay>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    _pulseIfDue();
  }

  @override
  void didUpdateWidget(StartCountdownOverlay old) {
    super.didUpdateWidget(old);
    if (old.secondsLeft != widget.secondsLeft) _pulseIfDue();
  }

  void _pulseIfDue() {
    if (widget.secondsLeft <= StartCountdownOverlay.pulseFrom) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seconds = widget.secondsLeft;
    final go = seconds == 0;
    final text = go
        ? l10n.countdownGo
        : seconds < 60
        ? '$seconds'
        : formatCountdown(Duration(seconds: seconds));
    return IgnorePointer(
      child: ColoredBox(
        key: const Key('startCountdown'),
        color: AppColors.background.withValues(alpha: 0.55),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Keeps the number in place when the label goes away.
                Opacity(
                  opacity: go ? 0 : 1,
                  child: Text(
                    l10n.countdownLabel.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    // Swells and settles; "START" a bit more.
                    final swell = sin(pi * _pulse.value);
                    return Transform.scale(
                      scale: 1 + (go ? 0.45 : 0.3) * swell,
                      child: child,
                    );
                  },
                  child: FittedBox(
                    child: Text(
                      text,
                      key: const Key('startCountdownText'),
                      style: TextStyle(
                        color: go ? AppColors.player : Colors.white,
                        fontSize: 140,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
