# Manhunt – Projektnotizen für Claude

Private Flutter-App (Android + iOS, DE/EN) für das Geländespiel „Manhunt“.
Kommunikation mit der Projektinhaberin auf **Deutsch**. Code, Kommentare, Commit-Messages auf Englisch.

## Wichtige Dokumente
- [docs/requirements.md](docs/requirements.md) – alle Anforderungen mit IDs (`R-PING-01` …). Neue Wünsche dort ergänzen.
- [docs/architecture.md](docs/architecture.md) – Aufbau, Datenmodell, Zeitsteuerung, Umsetzungsstand.
- [docs/privacy.md](docs/privacy.md) – welche Daten wo landen (muss bei jeder Datenänderung aktualisiert werden).
- [docs/BeforeYourGame.md](docs/BeforeYourGame.md) – Checkliste für Mitspielende (Berechtigungen, Akku, App nicht beenden). Bei Änderungen an Tracking/Berechtigungen aktualisieren.

## Regeln
- **Immer testen**: jede Änderung bekommt Tests; danach Skill `verify` (format, analyze, test, build). Nichts als fertig melden, was nicht grün ist.
- Tests referenzieren Anforderungs-IDs im Namen, z.B. `group('… (R-SPEED-03)')`.
- **Datenarm**: keine neuen Daten an Firebase ohne Eintrag in `docs/privacy.md`. Standorte & Spielfeld nur verschlüsselt (`GroupCrypto`). Kein Analytics/Crashlytics/FCM.
- Spiellogik als reine Dart-Funktionen in `lib/core/` (ohne Flutter/Firebase-Imports) → einfach unit-testbar.
- UI-Texte nur über ARB (`lib/l10n/app_en.arb` + `app_de.arb`, beide pflegen), danach `flutter gen-l10n`.
- Farben/Styles nur über `lib/theme/app_theme.dart` (`AppColors`). Dark Mode; die Karte bleibt helle OSM.
- Lints: `analysis_options.yaml` (single quotes, trailing commas, strict casts).

- Änderungen an `firestore.rules` immer mit Tests in `firestore-tests/rules.test.mjs`; Deploy nur nach grünen Tests.
  Nicht nur Einzelzugriffe testen, sondern **ganze Abläufe so, wie das Repository sie ausführt** (z.B. erst auflisten,
  dann löschen) – und zwar für jede Rolle (Host als Hunter/Spieler/unassigned, Spieler, Hunter). Fake-Firestore in
  den Dart-Tests prüft keine Regeln! (Lehre aus dem Lösch-Bug vom 2026-10-05.)

## Umgebung
- Windows-Rechner mit Flutter (`C:\Users\julia\develop\flutter`); iOS-Builds auf dem Mac der Projektinhaberin.
- Bundle-ID: `play.manhunt.app`. Firebase-Projekt: `manhunt-54b5d` (Spark, kein Billing → kein TTL, keine Functions).
- Node/Firebase-CLI sind installiert, aber nicht im PATH der Claude-Shell: in PowerShell vorher
  `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  und `firebase.cmd` / `npm.cmd` verwenden. Java für den Emulator: `$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'`.
- MapTiler-Key liegt in `config/maptiler.json` (gitignored); App mit `--dart-define-from-file=config/maptiler.json` starten/bauen.
