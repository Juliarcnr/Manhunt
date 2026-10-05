import 'package:flutter/material.dart';

import 'features/session_gate.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';

class ManhuntApp extends StatelessWidget {
  const ManhuntApp({super.key, this.locale});

  /// Overrides the device locale (used in tests).
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SessionGate(),
    );
  }
}
