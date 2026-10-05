---
name: verify
description: Prüft die Manhunt-App nach jeder Änderung – l10n generieren, formatieren, analysieren, alle Tests, Firestore-Regel-Tests, Android-Debug-Build. Immer ausführen, bevor eine Änderung als fertig gemeldet oder committet wird.
---

# Verify (Manhunt)

Im Projektroot in dieser Reihenfolge ausführen. Bei einem Fehler: Ursache beheben und von vorn beginnen.

1. `flutter gen-l10n` – nur nötig, wenn ARB-Dateien geändert wurden.
2. `dart format lib test` – danach muss `dart format --set-exit-if-changed lib test` sauber sein.
3. `flutter analyze` – erwartet: `No issues found!` (auch keine infos).
4. `flutter test` – erwartet: `All tests passed!`
5. **Nur wenn `firestore.rules` oder Firestore-Datenfelder geändert wurden** – Regel-Tests im Emulator (PowerShell):
   ```
   $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
   $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'; $env:Path = "$env:JAVA_HOME\bin;$env:Path"
   firebase.cmd emulators:exec --only firestore "npm.cmd --prefix firestore-tests test"
   ```
   Erwartet: `ℹ fail 0`. (PERMISSION_DENIED-Logs sind normal – das sind die erwarteten Ablehnungen.)
   Danach ggf. `firebase.cmd deploy --only firestore:rules --project manhunt-54b5d`.
6. `flutter build apk --debug --dart-define-from-file=config/maptiler.json` – nur bei Änderungen an Plattform-Code,
   Dependencies oder größeren Features (dauert mehrere Minuten; mit `timeout` 600000 aufrufen).
   iOS wird auf dem Mac gebaut: `flutter build ios --no-codesign --dart-define-from-file=config/maptiler.json`.

Ergebnis knapp berichten: Anzahl Tests, Analyse-Status, Regel-Tests, Build-Status. Fehlgeschlagene Schritte nie verschweigen.
