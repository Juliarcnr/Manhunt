import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../lobby/create_group_screen.dart';
import '../lobby/join_screen.dart';

/// Entry screen: create a group or join one by code (R-LOBBY-01).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.2,
            colors: [Color(0x33FF4D2E), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                const Icon(Icons.radar, size: 88, color: AppColors.hunter),
                const SizedBox(height: 16),
                Text(
                  l10n.appTitle.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.homeTagline,
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const Spacer(flex: 3),
                FilledButton.icon(
                  key: const Key('createButton'),
                  onPressed: () => _push(context, const CreateGroupScreen()),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: Text(l10n.homeCreateGroup),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('joinButton'),
                  onPressed: () => _push(context, const JoinScreen()),
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(l10n.homeJoinGroup),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.homePrivacyNote,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
