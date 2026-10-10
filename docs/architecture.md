# Architektur

## Stack
Flutter · Riverpod 3 · Firebase Spark (Projekt `manhunt-54b5d`, Firestore europe-west3 + Anonymous Auth) ·
flutter_map + MapTiler-OSM-Tiles · geolocator (Hintergrund-Standort) · flutter_local_notifications ·
cryptography (AES-GCM, PBKDF2) · flutter_secure_storage.
Kein Cloud Functions, kein FCM, kein Analytics → keine Kreditkarte nötig.

## Ordner
```
lib/
  core/        reine Dart-Logik, keine Flutter/Firebase-Imports
    models/    GameSettings, Member, GeoPoint
    schedule/  GameClock (Phasen, Ping-Zeitplan), Speedhunt (+ canStartSpeedhunt)
    teams/     Zufallseinteilung, Tauschen, StartCheck
    crypto/    GroupCrypto (Schlüssel + Gruppen-ID aus Code, AES-GCM)
    geo/       Punkt-in-Polygon, Fläche/Ausdehnung, Überkreuzungs-Check, AreaDraft (Editor-Logik mit Undo)
    history/   CatchRecord, RoundSummary (Rundenübersicht für die Historie)
    join_code.dart
  data/        GameRepository (Interface) + FirestoreGameRepository, SessionStore (Gruppenliste + offene
               Gruppe im Keystore), LocationService (geolocator; Phase 4 nur „wo bin ich“)
  state/       Riverpod-Provider, SessionController (erstellen/beitreten/öffnen/schließen/verlassen/löschen)
  features/    UI: session_gate (Weiche), groups (Übersicht/Start), lobby, settings, game, history,
               map (BaseMap = MapTiler-Kacheln + Attribution, areaLayers, AreaEditorScreen, AreaCard)
  l10n/        ARB-Dateien (de/en), generiert app_localizations.dart
  theme/       AppTheme, AppColors
  firebase_options.dart   generiert von flutterfire
test/          spiegelt lib/; helpers.dart = Fake-Firestore-Overrides je „Gerät“
firestore.rules           Sicherheitsregeln
firestore-tests/          Regel-Tests (Node, laufen im Firestore-Emulator)
config/maptiler.json      MapTiler-Key (nicht im Git; Vorlage: maptiler.example.json)
```

## Kernideen
- **Kein Server-Timer**: Alle Ping-Zeitpunkte werden aus `startAt` + `GameSettings` deterministisch berechnet
  (`GameClock.regularPingTimes`, `Speedhunt.pingTimes`). Jedes Spieler-Gerät pingt selbst.
  `startAt` ist ein Firestore-Server-Timestamp; Uhr-Abweichungen der Handys werden später darüber ausgeglichen.
- **Code = Schlüssel**: Der Beitrittscode (10 Zeichen, ≈48 bit) wird per PBKDF2 (50k Iterationen, im Isolate,
  ≈1 s) zu 512 bit abgeleitet: 256 bit AES-Schlüssel + 128 bit öffentliche `groupId`.
  Der Code selbst geht nie an Firebase; lokal liegt er im OS-Keystore.
- **App bleibt wach**: Während eines Spiels läuft Standort-Tracking im Hintergrund
  (Android Foreground-Service, iOS Background-Mode `location`); dadurch bleiben Firestore-Listener aktiv und
  Benachrichtigungen können lokal ausgelöst werden.
- **Neu beitreten erlaubt**: Auch in ein laufendes Spiel (verlorenes Handy, R-LOBBY-07) – neue anonyme ID,
  Host teilt die Rolle neu zu.
- **Mehrere Gruppen** (R-GROUPS-01 … 04): `SessionStore` hält eine `GroupList` (core/groups, max. 5) und den Code
  der offenen Gruppe; `null` = Übersicht. Dieselbe anonyme UID ist Mitglied in allen Gruppen. Es ist immer nur
  **eine** Gruppe offen (Schlüssel abgeleitet, Listener, Tracking); die Übersicht liest den Status der anderen per
  `watchStatus(groupId)` ohne Schlüssel. Name/Host-Flag in der Liste aktualisiert `SessionGate` aus `gameProvider`.
  Aus dem Spielbildschirm geht es bewusst nicht in die Übersicht, damit das Tracking nicht stoppt.
  Alte Installationen: der einzelne Code (`group_code`) wird beim ersten Laden in die Liste übernommen.

## Firestore-Modell
| Pfad | Inhalt | verschlüsselt | Stand |
|---|---|---|---|
| `games/{groupId}` | adminUid, status, `name` (optional), `settings`, `area`, sharedPings (Klartext-Kopie aus den Einstellungen für die Regeln, R-SET-15), `aliases` (anonyme Spielernummern der Runde, R-ANON-01), startAt, createdAt, expiresAt | name, settings, aliases; area separat (von allen Mitgliedern in der Lobby änderbar) | ✔ |
| `games/{groupId}/members/{uid}` | `name`, role, caught, jokerUsed, joinedAt | Name | ✔ |
| `games/{groupId}/pings/{uid}_{slotId}` | uid, kind, slot, createdAt, `data` (LocationFix) – Hunter lesen alle, Spieler nur eigene; mit `sharedPings` zusätzlich alle regulären (Query `kind == regular`) | Standort | ✔ |
| `games/{groupId}/hunterLocs/{uid}` | updatedAt, `data` (live, alle 15 s) – nur Hunter; Spieler 2 min nach Joker | Standort | ✔ |
| `games/{groupId}/outsideLocs/{uid}` | updatedAt, `data` (live, alle 5 s) – nur solange der Spieler außerhalb des Spielfelds ist + 60 s (R-OUT-03/04); nur Hunter lesen, nur der Spieler selbst schreibt/löscht | Standort | ✔ |
| `games/{groupId}/events/{auto}` | type (catch/speedhunt), createdAt, `data` – Speedhunt-Event **ohne** Ziel | Inhalt | ✔ |
| `games/{groupId}/speedhuntTargets/{eventId}` | uid (Ziel), createdAt – nur Hunter + Ziel lesbar | – | ✔ |
| `games/{groupId}/jokerRequests/{id}` | uid (Fragender), createdAt – nur Spieler lesbar; nur zusammen mit `playerJokerUsed` | – | ✔ |
| `games/{groupId}/jokerAnswers/{requestId}_{uid}` | request, requester, uid, createdAt, `data` – nur der Fragende liest | Standort | ✔ |
| `games/{groupId}/history/{auto}` | endedAt, `data` (RoundSummary) – überlebt Rundenende | Inhalt | ✔ |

Security Rules (`firestore.rules`, getestet in `firestore-tests/`): Spiele nur per ID abrufbar (nicht auflistbar),
Mitgliederliste nur für Mitglieder, Einstellungen/Rollen/Start/Löschen nur Host, Spielfeld (`area`) alle Mitglieder
in der Lobby, Beitritt nur als „unassigned“,
Umbenennen nur sich selbst. Deploy: `firebase deploy --only firestore:rules`.

**Lebenszyklus**: Eine Gruppe lebt über viele Runden (`status`: lobby ↔ running). „Spiel beenden“ (Host)
löscht `pings`/`hunterLocs`/`outsideLocs`/`events`, setzt caught/jokerUsed zurück und geht in die Lobby. Jede Host-Aktion setzt
`expiresAt` = jetzt + 180 Tage; zusätzlich verlängert jedes Öffnen durch ein Mitglied (`checkIn`, max. 1× pro Tag). **TTL gibt es im Spark-Tarif nicht**; stattdessen ruft `SessionController.build`
beim App-Start `checkIn` auf: abgelaufen → alles löschen, sonst Frist verlängern (Regeln: Mitglieder dürfen nur `expiresAt` setzen, max. +181 Tage; löschen erst nach Ablauf).

## Bestätigte Regeln (Julia, 2026-10-04)
- Speedhunt: erster Ping sofort beim Auslösen, dann alle `speedhuntInterval`.
- Höchstens ein Speedhunt gleichzeitig; nur auf nicht gefangene Spieler.
- Wird das Ziel während des Speedhunts gefangen, endet er sofort (R-SPEED-10): Der Melder (Hunter oder Ziel selbst, beide
  kennen das Ziel) schreibt den Speedhunt-Start ins verschlüsselte Catch-Event (`CatchRecord.endsSpeedhunt`); alle
  Geräte setzen daraus `Speedhunt.endedAt` (`applyCatches` in den Providern) → keine weiteren Pings/⚡-Pings, Banner aus.
- Catch rückgängig (R-CATCH-04): der Host löscht die Catch-Events des Spielers und setzt `caught` zurück (`undoCatch`) →
  alle Geräte leiten Gefangen-Status, Speedhunt-Ende und Historie wieder aus den verbleibenden Daten ab.
- Joker: einmal pro Spieler und Spiel; per Einstellung abschaltbar (`jokerEnabled`).
- Reguläre Pings: bei `n × pingInterval` nach Start, kein Ping exakt bei Spielende.

## Umsetzungsstand
- [x] Phase 1: Projekt-Setup, Theme, l10n, Doku, Skill `verify`
- [x] Phase 2: Core-Logik + Tests
- [x] Phase 3: Firebase, Lobby-Flow (erstellen, beitreten, einteilen, tauschen, Einstellungen, starten),
      Runde beenden + Datenlöschung, 180-Tage-Aufräumen, Catch-Dialog („Gefangen von“), Historie (Rundenübersicht), Rules + Tests
- [x] Phase 4: Karte (MapTiler streets-v2, Außenbereich abgedunkelt) + Spielfeld-Editor (tippen = Punkt,
      ziehen = verschieben, lange drücken = löschen, „+“ = einfügen, Undo, Fläche in km², Überkreuzungs-Check),
      Spielfeld-Vorschau in der Lobby, Karte im Spielbildschirm
- [x] Phase 5: Hintergrund-Standort (`LocationService.track`), automatische Pings + Hunter-Live (`RoundEngine`),
      Speedhunt, Joker, Catch-Buttons, Benachrichtigungen (Banner+Vibration / System-Notification), Basis-Kartenebenen
- [x] Phase 6: Filterleiste (Hunter, Letzte Pings, Chip pro Spieler für die nummerierte Historie – Tippen schaltet
      Punkte → Punkte mit Linien/Pfeilen → aus –, Chip pro Speedhunt „⚡ Name hh:mm“ mit ⚡1-3, Gefangene gebündelt in einem Chip „Gefangen“; Spieler: Meine Pings + Joker-Chips), Joker-Ergebnisse im Keystore (`JokerStore`, pro Runde),
      Übersicht, Spieler-/Hunterfarben, kompakte Kopfzeile
- [x] Feldtest-Wünsche 2026-10-08: Gefangene nur im Chip „Gefangen“, nach Spielende wieder aufgeteilt (R-HUNT-11),
      Satellitenbild (R-MAP-03), Speedhunt-Chips für Spieler (R-SPEED-09), „Reguläre Pings an alle“ (R-SET-15,
      R-PLAY-05), flüssiger Live-Standort (R-MAP-04)
- [x] Anonyme Spieler 2026-10-08 (R-SET-16, R-ANON-01 … 04): Host würfelt beim Start die Nummern (`shuffleAliases`, lib/core/round/player_aliases.dart),
      gespeichert verschlüsselt in `games/{id}.aliases`, gelöscht bei Rundenende. Nur die Anzeige der Hunter ändert sich
      (`showAliases`); Chips und Farben nach Nummer. Keine Regeländerung nötig (Host darf das Spiel-Dokument frei ändern).
- [ ] Phase 7: Feldtest (Android + iOS/TestFlight)

## Karten-Hinweise
- Kacheln: `https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}{r}.png?key=…`, Satellit (R-MAP-03):
  `…/maps/hybrid/256/{z}/{x}/{y}{r}.jpg` (Satellit + Straßennamen); Wahl in `mapStyleProvider`, Knopf `MapStyleButton`. Key per
  `--dart-define-from-file=config/maptiler.json` (`MAPTILER_KEY`). Ohne Key (z.B. in Tests) zeigt `BaseMap`
  nur eine graue Fläche – kein Netzwerk in Tests.
- Attribution „© MapTiler © OpenStreetMap contributors“ ist Pflicht und in `BaseMap` fest eingebaut.
- Gesten: flutter_map beansprucht horizontale/vertikale Drags ab 18 px. Ziehbare Marker brauchen eine kleinere
  `touchSlop` (siehe `_CornerHandle`), sonst bewegt sich die Karte statt des Markers.
- Taps auf die Karte kommen erst nach dem Doppeltipp-Timeout; in Widget-Tests nach `tapAt` ~400 ms pumpen.

## Runde auf dem Gerät (Phase 5)
- Standort-Stream: Android `intervalDuration` 1 s, iOS ohne `distanceFilter` → ca. 1 Fix/s; der eigene Punkt und die
  Live-Pins der Hunter gleiten per `AnimatedMarkerLayer` (lib/features/map) zur neuen Position (R-MAP-04). Uploads
  bleiben gedrosselt (Hunter alle 15 s, Pings nach Zeitplan).
- `RoundEngine` (lib/state) gehört dem `GameScreen`: trackt nur in Vorlauf/Jagd und nur für Hunter bzw. nicht
  gefangene Spieler; tickt alle 5 s. Spieler: `duePings` → `sendPing` (Doc-ID `{uid}_{slotId}` ⇒ idempotent,
  die Regeln verbieten Überschreiben; >3 min verspätete Pings werden verworfen). Hunter: Live-Position alle 15 s.
- Benachrichtigungen: `NoticeTracker` meldet nur *neue* Catches/Speedhunts (erster Snapshot = Basis).
  Vordergrund → In-App-Banner + `HapticFeedback.vibrate`, Hintergrund → `NotificationService` (System, vibriert).
- Hunter-only-Streams (`allPingsProvider`, `hunterLocationsProvider`) nur bei Hunter-Rolle beobachten,
  `jokerRequestsProvider` nur bei Spieler-Rolle, `sharedPingsProvider` nur bei Spieler-Rolle mit `sharedPings`.
- Eigene ⚡-Pings (R-SPEED-09): `RoundEngine.speedhuntSnapshots` hält auf jedem aktiven Spielerhandy zu jedem
  Speedhunt-Ping-Zeitpunkt (aus den öffentlichen Speedhunts) den eigenen Standort fest – nur lokal, gespeichert mit
  den Joker-Ergebnissen (`JokerStore`), nach Neustart per `restoreSpeedhuntSnapshots` zurück.
- Spieler-Joker: Anfrage (`requestPlayerPositions`) → `RoundEngine.updateJokerRequests` auf den anderen
  Spieler-Handys beantwortet frische Anfragen (< 2 min) mit dem aktuellen Standort (`jokerAnswers`).
- Spielfeld verlassen (R-OUT-*): reine Logik in `lib/core/round/boundary_watch.dart` (`classifyFix`, `boundaryStep`:
  inside → warning → live → afterglow, Abstand zur Grenze über `distanceOutsideM` in `lib/core/geo/polygon.dart`).
  `RoundEngine` füttert jeden Standort hinein, fragt während einer Warnung bei stockendem Stream direkt nach
  (`currentFix`, mit Genauigkeit), lädt in live/afterglow alle 5 s nach `outsideLocs` hoch und löscht danach (auch beim
  Stoppen des Trackings und einmal beim Start, falls nach einem Neustart etwas übrig ist). `boundaryEvents` → Hinweise
  an den Spieler; `boundary` → rotes Banner. Hunter: `outsideLocationsProvider`, Pin-Layer `outsidePlayersLayer`,
  `NoticeTracker.onOutside` meldet neu Hinausgegangene (Namen über `_displayNames`, also ggf. „Spieler n“).
  Schwelle `outsideThresholdM` = 30 m + 2 × Genauigkeit; Debug-Log über `describeFix` (Wechsel mit Grund,
  „not counted“ höchstens alle 10 s) zum Kalibrieren im Feldtest (R-OUT-07).

## App-Icon (R-UI-04)
- Quellen: `assets/icon/*.svg` (1024×1024), daraus gerenderte PNGs. Plattform-Icons erzeugen mit
  `dart run flutter_launcher_icons` (Config in `pubspec.yaml`).
- Danach `ios/Runner.xcodeproj/project.pbxproj` prüfen: das Tool setzt fälschlich
  `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon` → zurücksetzen.

## Bekannte Grenzen / offene Punkte
- **App nicht wegwischen**: Android-Foreground-Service bzw. iOS-Hintergrundmodus halten die App am Leben, aber
  „Beenden erzwingen“/Wegwischen stoppt Pings. Herstellerspezifisches Akku-Sparen (Samsung, Xiaomi …) kann ebenfalls
  stören → Mitspielenden empfehlen, Akku-Optimierung für Manhunt abzuschalten.
- **Uhrzeit**: Ping-Zeitpunkte = Startzeit (Server-Zeit) + n × Intervall, verglichen mit der Handy-Uhr. Bewusst kein
  Countdown-Timer, weil der bei App-Neustart/Hintergrund verloren ginge. Mit automatischer Uhrzeit (Standard) weichen
  Handys < 1 s ab; nur bei manuell verstellter Uhr verschieben sich Pings (Checkliste in `docs/BeforeYourGame.md`).
  Weicht eine Handy-Uhr stark ab,
  verschieben sich ihre Pings. Ein Server-Zeit-Ausgleich wäre möglich, ist aber bisher nicht nötig.
- **Speedhunt-Limit** wird nur in der App geprüft (Regeln können nicht zählen) – unter Freunden ausreichend.
- **Gefangene Spieler** tracken nicht mehr; ihre App kann im Hintergrund pausiert werden, Benachrichtigungen kommen
  dann erst beim Öffnen.
- iOS-Hintergrundbetrieb ist ungetestet (Build nur auf dem Mac).
- Feldtest 2026-10-05: Android sendete keine Pings. Ursachen behoben: gleichzeitige Berechtigungsdialoge (Android
  bricht den zweiten ab) → jetzt nacheinander; Tracking-Fehler wurden verschluckt → Statuszeile + Neustart;
  `distanceFilter` 5 m lieferte im Stillstand keine Updates → 0 m + GPS-Direktabfrage bei veralteter Position.
- Feldtest 2026-10-05 (2): Tracking startete auf Android gar nicht (Protokoll nur „screen opened“). Ursache: Die
  Engine prüfte nur bei Ereignissen, ob sie tracken soll; lag z.B. der Server-Start ein paar Sekunden vor der
  Handy-Uhr („notStarted“), wurde nie neu geprüft. Jetzt: Timer läuft immer, Prüfung alle 5 s, Grund im Protokoll.
