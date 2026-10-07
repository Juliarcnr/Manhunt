# Manhunt – Anforderungen

Quelle: Anforderungen der Projektinhaberin (Julia) plus gemeinsam getroffene Entscheidungen.
Jede Anforderung hat eine ID (`R-<BEREICH>-<NR>`), auf die Tests, Commits und Doku verweisen.
Beispielwerte (z.B. „20 Minuten“) sind **Standardwerte**, alle sind einstellbar, sofern nicht anders angegeben.

## 1. Spielidee

Eine Gruppe (ca. 5–15 Personen) spielt ein Verstecken-Fangen über mehrere Stunden in einem festgelegten
Gebiet. Teilnehmende sind entweder **Hunter** oder **Spieler** (gemeint sind alle Geschlechter).
Die Hunter versuchen, bis Spielende alle Spieler zu fangen. Vorbild ist die YouTube-Serie „Manhunt“.

| ID | Anforderung |
|---|---|
| R-GAME-01 | Ein Spiel hat eine Gesamtdauer (Standard: 3 h). |
| R-GAME-02 | Das Spielgebiet ist ein auf der Karte gezeichneter Bereich, der nicht verlassen werden darf (Richtwert bei 7 Personen: ca. 1 km × 2 km). |
| R-GAME-03 | Alle Teilnehmenden sind entweder Hunter oder Spieler. |
| R-GAME-04 | Nach dem Start haben Spieler eine Vorlaufzeit (Standard: 15 min), erst danach dürfen die Hunter loslaufen. |
| R-GAME-05 | Ziel der Hunter: alle Spieler bis Spielende fangen. |
| R-GAME-06 | Nach Ablauf der Spielzeit läuft die Runde weiter, damit alle sich die Standorte noch anschauen können. Der Host beendet sie offiziell per Button „Spiel beenden“; vorher erscheint eine Warnung, dass alle sensiblen Daten wie Standorte aus Datenschutzgründen gelöscht werden. Der Host kann eine Runde auch vorzeitig beenden. |
| R-GAME-07 | Der Host kann eine Runde auch vorzeitig abbrechen. Solange die Spielzeit noch läuft, muss das **zweimal** bestätigt werden (1. „Spiel vorzeitig abbrechen?“ mit Restzeit, 2. „Wirklich abbrechen?“ mit Lösch-Hinweis). Die Runde erscheint in der Historie als „vorzeitig abgebrochen“. |

## 2. Gruppe & Einstellungen

| ID | Anforderung |
|---|---|
| R-SET-01 | Eine Gruppe kann erstellt werden. |
| R-SET-02 | Einstellbar: Spieldauer. |
| R-SET-03 | Einstellbar: Vorlaufzeit der Spieler. |
| R-SET-04 | Einstellbar: Abstand der regulären Pings (Standard: 20 min). |
| R-SET-05 | Einstellbar: Anzahl Speedhunts (Standard: 2), Pings pro Speedhunt (Standard: 3), Abstand der Speedhunt-Pings (Standard: 5 min). |
| R-SET-06 | Einstellbar: Spielgebiet über einen Karten-Editor auf OpenStreetMap-Basis (Polygon zeichnen, ähnlich Google My Maps): Punkte setzen, verschieben, einfügen, löschen, rückgängig; Anzeige von Fläche und Ausdehnung; sich überkreuzende Ränder werden verhindert. |
| R-SET-07 | Einstellbar: Anzahl Hunter; die Anzahl Spieler ergibt sich aus dem Rest. |
| R-SET-08 | Alle Einstellungen sind nach der Gruppenerstellung weiterhin bearbeitbar. |
| R-SET-09 | Einstellbar: ob es den Joker „Hunter-Standorte“ gibt (Standard: ja). |
| R-SET-10 | Das Spielfeld kann von allen Mitgliedern der Gruppe eingezeichnet und bearbeitet werden (nur in der Lobby, nicht während einer laufenden Runde). Alle anderen Einstellungen ändert nur der Host. |
| R-SET-11 | Einstellbar: ab wann (Minuten nach Spielstart) der erste Speedhunt erlaubt ist (Standard: 60 min). |
| R-SET-12 | Einstellbar: ob es den Joker „Spieler-Standorte“ gibt (Standard: ja). Der Joker „Hunter-Standorte“ ist über R-SET-09 einzeln abschaltbar. |
| R-SET-13 | Einstellbar: wie lange nach dem Auslösen eines Speedhunts der erste Speedhunt-Ping gesendet wird (Standard: 0 min = sofort, in 1-Minuten-Schritten bis 30 min). Der Wert wird beim Auslösen im Speedhunt festgehalten. |
| R-SET-14 | Alle Mitglieder können die Einstellungen der Gruppe in der Lobby ansehen (schreibgeschützt, aktuell gehalten); bearbeiten kann sie nur der Host (vgl. R-SET-10). |

## 3. Beitritt, Lobby & Start (Workflow)

| ID | Anforderung |
|---|---|
| R-LOBBY-01 | Keine Konten, keine E-Mail-Adressen. App installieren → mit Code einer Gruppe beitreten. |
| R-LOBBY-02 | Beim Erstellen einer Gruppe wird ein Beitrittscode erzeugt, den andere eingeben. |
| R-LOBBY-03 | Teilnehmende treten nach und nach per Code bei und geben einen Anzeigenamen an. |
| R-LOBBY-04 | Ein Zufallsgenerator teilt alle Teilnehmenden gemäß Hunter-Anzahl in Hunter und Spieler ein. |
| R-LOBBY-05 | Nach der Einteilung können Personen getauscht werden (Hunter ↔ Spieler). |
| R-LOBBY-06 | Mit „Start“ beginnt das Spiel für alle. |
| R-LOBBY-07 | Geht ein Handy verloren, tritt man der Gruppe einfach neu bei (keine Wiederherstellung nötig). |
| R-LOBBY-08 | Eine Gruppe bleibt über mehrere Runden bestehen (gleicher Code, gleiche Mitglieder, gleiche Einstellungen). Nach einer Runde geht es zurück in die Lobby; „gefangen“ und Joker werden zurückgesetzt, Rollen bleiben und können neu eingeteilt werden. |
| R-LOBBY-09 | Der Host kann Mitglieder aus der Gruppe entfernen – in der Lobby (Symbol neben der Person) und während einer Runde (Übersicht), jeweils mit Rückfrage. Die entfernte Person sieht „Du wurdest vom Host aus der Gruppe entfernt“ und kann mit dem Code wieder beitreten. |

### Mehrere Gruppen

| ID | Anforderung |
|---|---|
| R-GROUPS-01 | Ein Gerät kann zu mehreren Gruppen gehören. Die Codes liegen nur lokal im Schlüsselspeicher; beim App-Start öffnet sich die zuletzt geöffnete Gruppe (oder die Übersicht). |
| R-GROUPS-02 | Höchstens **5 Gruppen** pro Gerät – selbst erstellte und beigetretene zusammen. Bei 5/5 sind „Erstellen“ und „Beitreten“ gesperrt, mit Hinweis. Erneutes Beitreten zu einer bekannten Gruppe zählt nicht extra. |
| R-GROUPS-03 | Aus der Lobby (Zurück-Pfeil oder Zurück-Geste) kommt man in die Gruppenübersicht, ohne die Gruppe zu verlassen. Die Übersicht zeigt alle Gruppen (Name, Host-Kennzeichen, „Runde läuft“, „Gelöscht“) und bietet „Gruppe erstellen“ und „Mit Code beitreten“. Tippen öffnet eine Gruppe; eine inzwischen gelöschte verschwindet dabei mit Hinweis. Ohne Gruppen sieht die Übersicht aus wie der bisherige Startbildschirm. |
| R-GROUPS-04 | Jede Gruppe hat einen Namen (Pflichtfeld beim Erstellen, verschlüsselt gespeichert); der Host kann ihn in der Lobby ändern. Ältere Gruppen ohne Namen erscheinen als „Gruppe ABCDE-FGHJK“. |

## 4. Pings (Standortübermittlung)

| ID | Anforderung |
|---|---|
| R-PING-01 | Standorte der Spieler werden **automatisch** von der App erfasst und gesendet, ohne Knopfdruck. |
| R-PING-02 | Reguläre Pings: Alle Spieler senden im eingestellten Abstand ihren Standort an die Hunter. Erster Ping im ersten Intervall ab Spielstart (Beispiel: Start bei 0, Hunter ab Minute 15, erster Ping Minute 20). |
| R-PING-03 | Pings funktionieren auch bei ausgeschaltetem Bildschirm bzw. App im Hintergrund. |
| R-PING-04 | Gefangene Spieler senden keine Pings mehr. |

## 5. Speedhunt

| ID | Anforderung |
|---|---|
| R-SPEED-01 | Hunter haben eine begrenzte Anzahl Speedhunts (siehe R-SET-05). |
| R-SPEED-02 | Ein Speedhunt wird von einem Hunter für genau einen Spieler ausgelöst. |
| R-SPEED-03 | Während des Speedhunts sendet der betroffene Spieler die eingestellte Anzahl zusätzlicher Pings im eingestellten Abstand (Standard: 3 Pings, alle 5 min). Der erste Ping kommt nach der eingestellten Verzögerung (R-SET-13, Standard: sofort). |
| R-SPEED-06 | Es läuft höchstens ein Speedhunt gleichzeitig; Ziel kann nur ein nicht gefangener Spieler sein. |
| R-SPEED-07 | Der erste Speedhunt ist frühestens nach der eingestellten Zeit ab Spielstart möglich (R-SET-11). |
| R-SPEED-08 | Während eines Speedhunts zeigt das Banner allen (Huntern und Spielern) den Countdown zum nächsten Speedhunt-Ping, z.B. „Speedhunt aktiv · Ping 2/3 in 03:12“. Da alle dasselbe sehen, verrät das kein Ziel. |
| R-SPEED-04 | Spieler erfahren, **dass** ein Speedhunt läuft, aber nicht, **wen** er betrifft – auch der betroffene Spieler nicht: keine Benachrichtigung über seine Speedhunt-Pings, kein Einfluss auf „Nächster Ping“/„letzter Ping“, Speedhunt-Pings nicht in der eigenen Historie. |
| R-SPEED-05 | Im Haupt-View (Karte) ist für alle (Hunter und Spieler) sichtbar, ob gerade ein Speedhunt läuft. |

## 6. Haupt-View: Karte

| ID | Anforderung |
|---|---|
| R-MAP-01 | Hunter und Spieler sehen im Haupt-View immer die Karte (OpenStreetMap) mit dem Spielgebiet. Die Kopfzeile zeigt nur Phase und Countdown (z.B. „DIE JAGD LÄUFT 1:23:45“), damit möglichst viel Karte sichtbar bleibt; darunter nur kleine Hinweise (nächster Ping, GPS-Status, Speedhunt). Bei Spielern steht „Nächster Ping in …“ ganz oben, über den Filtern. Unter den Filtern (GPS-Status, Speedhunt-Banner) derselbe Abstand wie über ihnen (Kopfzeile bzw. „Nächster Ping“). |
| R-MAP-02 | Die Karte ist immer nach Norden ausgerichtet: zoomen und verschieben ja, drehen nein (alle Karten). |

### Hunter-View

| ID | Anforderung |
|---|---|
| R-HUNT-01 | Filter-Buttons (Chips) in einer Leiste unter der Kopfzeile, mehrere gleichzeitig aktivierbar: Hunter, Letzte Pings, ein Chip pro Spieler (in seiner Farbe) für dessen Ping-Historie (R-HUNT-04/05) und ein Chip pro Speedhunt (R-HUNT-07). Spieler haben „Meine Pings“ und nach dem Einlösen je einen Chip pro Joker. Alle Chips dunkel; aktive Chips mit farbiger Umrandung und Haken. |
| R-HUNT-02 | Filter „Hunter“: Live-Standorte aller Hunter als Standort-Pins, alle Hunter einheitlich in der (gedämpften) Hunter-Farbe Orange-Rot, Hunter-Symbol vor dem Namen, ohne Uhrzeit (live). |
| R-HUNT-03 | Filter „Letzte Pings“: letzter Ping jedes Spielers als Location-Pin mit Spielername darüber, **jeder Spieler in eigener Farbe**. Zählt nur normale Pings – Speedhunt-Pings gehören zum Filter „Speedhunts“ (R-HUNT-07). |
| R-HUNT-04 | Ping-Historie einzelner Spieler, nummeriert. Nur normale Pings – Speedhunt-Pings werden nicht mitgezählt, damit die Nummern mit denen auf dem Spielerhandy übereinstimmen (Feldtest 2026-10-06). |
| R-HUNT-05 | Historie-Punkte mit Linien verbinden, mit kleinen Pfeilen in Laufrichtung (nur normale Pings). Kein eigener Linien-Chip: Tippen auf den Spieler-Chip schaltet reihum Punkte → Punkte mit Linien → aus; bei Linien zeigt der Chip ein Linien-Symbol statt des Farbpunkts. |
| R-HUNT-06 | Hunter können einen Speedhunt für einen Spieler auslösen (solange verfügbar). |
| R-HUNT-07 | Speedhunt-Pings bleiben für die Hunter alle sichtbar, nummeriert (⚡1/⚡2/⚡3 auf dunklem Grund, Rand in Spielerfarbe); der jeweils neueste Speedhunt-Ping jedes Spielers zeigt im Badge zusätzlich den Spielernamen („⚡2 Anna“) und hat einen Location-Pin in Spielerfarbe unter dem Badge. Getrennt von der Spieler-Historie: ein Filter-Chip pro Speedhunt mit Blitz, Name und Startzeit („⚡ Sam 18:35“, Rand in Spielerfarbe), erscheint mit dem ersten Ping des Speedhunts, ist sofort an und einzeln ein-/ausschaltbar. |
| R-HUNT-08 | Ist „Letzte Pings“ ausgeschaltet und kommen neue normale Pings rein, schaltet sich der Filter automatisch wieder ein (Speedhunt-Pings lösen das nicht aus). Ebenso schaltet ein neuer Speedhunt-Ping den Chip seines Speedhunts wieder ein, falls er aus war (R-HUNT-07). |

### Spieler-View

| ID | Anforderung |
|---|---|
| R-PLAY-01 | Eigene Standort-Historie (gesendete Pings) kann angezeigt werden. |
| R-PLAY-02 | Joker „Hunter-Standorte“: einmal pro Spieler und Runde die aktuellen Hunter-Standorte abfragen, angezeigt als Pins wie bei R-HUNT-02, aber mit Uhrzeit der Position („Alex · 14:32“) (nur wenn R-SET-09 aktiv). |
| R-PLAY-03 | Joker „Spieler-Standorte“: einmal pro Spieler und Runde die aktuellen Standorte aller anderen (nicht gefangenen) Spieler abfragen, angezeigt als Pins, jeder Spieler in eigener Farbe, klar unterscheidbar vom Hunter-Orange-Rot (nur wenn R-SET-12 aktiv). Die anderen Handys antworten automatisch; nur der fragende Spieler sieht die Antworten, Hunter nie. |
| R-PLAY-04 | Joker-Ergebnisse werden als farbige Pins mit Uhrzeit angezeigt (Hunter einheitlich im Hunter-Orange-Rot, Spieler in ihren Spielerfarben). Dazu ein Filter-Button je Joker: nach dem Einlösen automatisch an, aus- und jederzeit wieder einschaltbar (zeigt dann wieder die Standorte von damals mit Uhrzeit). |

## 7. Benachrichtigungen

| ID | Anforderung |
|---|---|
| R-NOTIF-01 | In-App-Benachrichtigungen (Banner), das Handy vibriert dabei. |
| R-NOTIF-02 | Benachrichtigung an alle, wenn jemand gefangen wurde. |
| R-NOTIF-03 | Benachrichtigung an einen Spieler, wenn sein Standort bei einem regulären Ping an die Hunter gesendet wurde (nicht bei Speedhunt-Pings, siehe R-SPEED-04). |
| R-NOTIF-04 | Benachrichtigung, wenn ein Speedhunt gestartet wurde (ohne das Ziel an Spieler zu verraten). |
| R-NOTIF-05 | Ton richtet sich nach den Handy-Einstellungen: Ist das Handy laut, gibt es zusätzlich zur Vibration einen Benachrichtigungston; ist es stumm/lautlos, nur Vibration. Bei geöffneter App gibt es kein zusätzliches System-Pop-up (nur das Banner in der App). |

## 8. Catch

| ID | Anforderung |
|---|---|
| R-CATCH-01 | Ein Catch kann von einem Hunter (für einen Spieler) **oder** vom gefangenen Spieler selbst gemeldet werden. |
| R-CATCH-02 | Gefangene Spieler werden in der Übersicht durchgestrichen dargestellt. |
| R-CATCH-03 | Es wird nur festgehalten, **dass** jemand gefangen wurde, nicht von wem. Der Catch-Dialog für Hunter fragt nur nach dem Spieler; auch Historie und Benachrichtigungen nennen keinen Hunter. (Geändert am 2026-10-05; vorher „Gefangen von“-Feld.) |

## 8a. Historie

| ID | Anforderung |
|---|---|
| R-HIST-01 | Für jeden Catch wird festgehalten: wer und wann (Zeit seit Rundenstart) – **nicht**, von wem (R-CATCH-03). |
| R-HIST-02 | Beim Beenden einer Runde wird eine Rundenübersicht gespeichert: Rundennummer, Datum, Dauer, Hunter, Spieler, Catches, nicht Gefangene. Keine Standorte. |
| R-HIST-03 | Die Historie aller Runden ist in einem eigenen Bereich einsehbar (aus Lobby und Spiel erreichbar) und bleibt bis zur Löschung der Gruppe erhalten. |

## 9. Übersicht

| ID | Anforderung |
|---|---|
| R-OVER-01 | Für alle gibt es einen Übersichtsbereich, im Spiel über das Gruppen-Symbol oben rechts erreichbar (statt der Historie, die nur in der Lobby angeboten wird). |
| R-OVER-02 | Liste aller Teilnehmenden, unterteilt in Hunter und Spieler; gefangene Spieler durchgestrichen. |
| R-OVER-03 | Anzeige, ob aktuell ein Speedhunt läuft. |

## 10. Plattform, Sprache, Design

| ID | Anforderung |
|---|---|
| R-PLAT-01 | Android und iOS. |
| R-PLAT-02 | Sprachen: Deutsch und Englisch. |
| R-UI-01 | Moderne, „coole“ Optik. |
| R-UI-02 | Dark Mode als Standard für die App-Oberfläche. |
| R-UI-03 | Die Karte selbst bleibt eine normale (helle) OpenStreetMap. |
| R-UI-04 | App-Icon: stylisches „M“ (Verlauf Gelb→Hunter-Orange→Rot) auf dunklem Grund, ohne weitere Elemente. Android adaptiv inkl. Monochrom (Themed Icons). |

## 11. Datenschutz

| ID | Anforderung |
|---|---|
| R-PRIV-01 | So wenig Daten wie möglich sammeln; keine Konten, keine E-Mails, kein Analytics/Tracking. |
| R-PRIV-02 | Standorte sind Ende-zu-Ende-verschlüsselt; der Server kann sie nicht lesen. Der Schlüssel wird aus dem Gruppencode abgeleitet, der das Gerät nie verlässt. |
| R-PRIV-03 | Beim offiziellen Beenden einer Runde (R-GAME-06) werden alle sensiblen Rundendaten – insbesondere alle Standorte – für alle gelöscht. Der Host kann die ganze Gruppe jederzeit löschen. |
| R-PRIV-04 | Standort wird nur während eines laufenden Spiels erfasst. |
| R-PRIV-05 | Eine Gruppe wird gelöscht, wenn 180 Tage lang niemand die App geöffnet und die Gruppe aufgerufen hat. Jedes Öffnen durch ein Mitglied (und jede Host-Aktion) verlängert die Frist. Mangels Server erledigt das Löschen das erste Gerät, das die Gruppe danach öffnet. |

## 12. Entwicklungs-Richtlinien

| ID | Anforderung |
|---|---|
| R-DEV-01 | Zu jedem Code werden Tests geschrieben. |
| R-DEV-02 | Jede Änderung wird mit `flutter analyze`, `flutter test` und einem Build geprüft. |
| R-DEV-03 | Projektwissen wird in md-Dateien gepflegt (`CLAUDE.md`, `docs/`), wiederkehrende Abläufe als Skills. |
| R-DEV-04 | Versionsname bleibt vorerst `0.1.0`; die Buildnummer startet bei 1 und wird vor jedem Store-/Test-Build mit `dart run tool/bump_build.dart` hochgezählt. |

## 13. Technische Entscheidungen

| Thema | Entscheidung |
|---|---|
| App | Flutter (Dart) |
| Backend | Firebase Spark (kostenlos, ohne Kreditkarte): Firestore (EU, europe-west3) + Anonymous Auth. Keine Cloud Functions, kein FCM, kein Analytics/Crashlytics. |
| Karte | flutter_map + OSM-Tiles (MapTiler Free-Tier) |
| Standort | geolocator; Android Foreground-Service, iOS Background-Mode `location` |
| Zeitsteuerung | Ping-Zeitpunkte werden auf jedem Gerät deterministisch aus Startzeit + Einstellungen berechnet. |
