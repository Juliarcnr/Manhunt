# Datenschutz

Ziel: so wenig Daten wie möglich (R-PRIV-01 … R-PRIV-05). **Jede Änderung an gespeicherten Daten hier eintragen.**

## Was verlässt das Gerät?
| Datum | Wohin | Lesbar für Firebase/Google? | Löschung |
|---|---|---|---|
| Anonyme Firebase-UID | Firebase Auth | ja (zufällige ID, keine E-Mail/kein Name) | bei App-Deinstallation verwaist |
| Gruppen-ID (aus Code abgeleitet) | Firestore | ja, aber ohne Rückschluss auf den Code | mit Gruppe |
| Anzeigename (in der Lobby änderbar, R-LOBBY-10) | Firestore | nein (verschlüsselt) | mit Gruppe |
| Gruppenname (R-GROUPS-04) | Firestore | nein (verschlüsselt) | mit Gruppe |
| Rolle, gefangen, Joker benutzt (Hunter-Joker: Anzahl `jokersUsed`, R-SET-09) | Firestore | ja (nötig für Regeln) | Rolle mit Gruppe; gefangen/Joker bei Rundenende zurückgesetzt |
| Spielfeld & Einstellungen (inkl. optionaler Startzeit, R-SET-21) | Firestore | nein (verschlüsselt) | mit Gruppe |
| Anonyme Spielernummern der Runde (R-ANON-01): Zuordnung UID → „Spieler n“ | Firestore `games/{id}.aliases` | nein (verschlüsselt) | beim Beenden der Runde |
| Schalter „Reguläre Pings an alle Spieler“ (R-SET-15) | Firestore `games/{id}.sharedPings` | ja (Klartext-Kopie aus den verschlüsselten Einstellungen, nötig für die Sicherheitsregeln; verrät nur die Spielvariante) | mit Gruppe |
| Anzahl der Hunter-Joker pro Spieler (R-SET-09) | Firestore `games/{id}.hunterJokers` | ja (Klartext-Kopie aus den verschlüsselten Einstellungen, nötig für die Sicherheitsregeln; nur eine Zahl 0–5) | mit Gruppe |
| Takt der Hunter-Live-Standorte der Runde, 5 oder 15 s; daraus abgeleitet der Takt der Live-Ansicht für Spielleitung und Gefangene, 15 oder 30 s (R-QUOTA-01) | Firestore `games/{id}.hunterLiveSec` | ja (nur eine Zahl, verrät nur, dass die Runde groß ist) | bleibt bis zum nächsten Start, mit Gruppe |
| Spieldauer (R-GAME-06) | Firestore `games/{id}.durationSec` | ja (Klartext-Kopie aus den verschlüsselten Einstellungen, nötig, damit die Sicherheitsregeln das Spielende kennen; verrät nur die Spieldauer) | mit Gruppe |
| Zeitpunkt „Hunter haben gewonnen“ (R-GAME-08) | Firestore `games/{id}.finishedAt` | ja (nur ein Zeitpunkt, kein Name) | beim Beenden der Runde |
| Zeitpunkt der Bestätigung nach Zeitablauf, wer noch gefangen wurde (R-GAME-11) | Firestore `games/{id}.confirmedAt` | ja (nur ein Zeitpunkt; wer bestätigt hat, wird nicht gespeichert, die nachgemeldeten Catches sind normale verschlüsselte Catch-Ereignisse) | beim Beenden der Runde |
| Standorte (Pings, Hunter-Live), Speedhunt-/Catch-Ereignisse (ein Catch vermerkt ggf. den Start des Speedhunts, den er beendet – R-SPEED-10) | Firestore | **nein** (AES-GCM). Mit R-SET-15 dürfen auch Spieler die regulären Pings lesen (nie Speedhunt-Pings). Nach Ablauf der Spielzeit oder dem Hunter-Sieg dürfen alle Spieler alle Pings und Hunter-Standorte lesen (R-GAME-06, R-GAME-08) | **beim Beenden der Runde** (ein vom Host rückgängig gemachter Catch sofort, R-CATCH-04) |
| Live-Standort eines Spielers, der das Spielfeld verlassen hat (R-OUT-03), mit GPS-Genauigkeit – nur solange er eindeutig (30 m + doppelte Ungenauigkeit) und seit 30 s draußen ist, plus 60 s nach der Rückkehr (Einstellung R-SET-17) | Firestore `outsideLocs/{uid}` | **nein** (AES-GCM); nur Hunter dürfen lesen; lesbar ist nur, *dass* eine anonyme ID gerade draußen ist | vom eigenen Handy gelöscht, sobald die 60 s um sind, man gefangen wird oder die Zeit abläuft; spätestens beim Beenden der Runde |
| Live-Standort jedes nicht gefangenen Spielers für Spielleitung und gefangene Spieler (R-GM-05), alle 15 s überschrieben – nur solange es eine Spielleitung oder einen gefangenen Spieler gibt | Firestore `playerLocs/{uid}` | **nein** (AES-GCM); lesen dürfen nur Spielleitung und gefangene Spieler, solange die Runde läuft und noch niemand gewonnen hat – nie Hunter oder Spieler im Spiel. Gefangene werden in der App gewarnt, nichts weiterzugeben (R-GM-08) | vom eigenen Handy gelöscht, sobald man gefangen wird, niemand mehr zusehen darf oder die Zeit abläuft bzw. die Hunter gewonnen haben; spätestens beim Beenden der Runde |
| Standort jedes Spielers, der bei Spielende noch im Spiel ist, einmal, sobald das Ergebnis feststeht (R-HIST-08, R-GAME-11) | Firestore `pings/{uid}_end` | **nein** (AES-GCM), wie ein regulärer Ping; zu dem Zeitpunkt dürfen ohnehin alle alle Pings lesen (R-GAME-06) | beim Ende der Runde (Inhalt wandert in die Rundenkarte) |
| Standort jedes Hunters zu jedem regulären und ⚡-Ping-Zeitpunkt (R-HIST-05), für die Rundenkarte | Firestore `hunterSnaps/{uid}_{slot}` | **nein** (AES-GCM); lesbar sind nur Hunter-UID und Ping-Nummer. Während der Runde liest ihn niemand (auch keine Hunter), danach alle Mitglieder | beim Ende der Runde (Inhalt wandert in die Rundenkarte) |
| Rolle „Spielleitung“ (R-GM-01) | Firestore `members/{uid}.role` | ja (wie die anderen Rollen, nötig für die Regeln) | mit Gruppe |
| Zeichnungen der Hunter auf der Karte (R-DRAW-01 … 07): Farbe + Linienpunkte (Koordinaten), Autor-UID, Zeitpunkt | Firestore `drawings/{id}` | **nein** für Farbe und Punkte (AES-GCM); lesbar sind nur Autor-UID, Zeitpunkt und Anzahl der Striche. Nur Hunter dürfen lesen, Spieler nie | per Radiergummi/Mülleimer sofort; spätestens beim Beenden der Runde |
| Antworten auf den Spieler-Joker (aktueller Standort der anderen Spieler) | Firestore | **nein** (AES-GCM); nur der fragende Spieler darf sie lesen | beim Beenden der Runde |
| Metadaten der Runde: wer wann gepingt hat (uid, Ping-Nr.), Ziel-uid eines Speedhunts, wer einen Joker wann benutzt hat | Firestore | ja (nötig für die Sicherheitsregeln; nur anonyme IDs, keine Orte) | beim Beenden der Runde (Joker-Zeitpunkte bleiben bis zur nächsten Runde) |
| Rundenübersicht (Runde, Datum, Dauer, Teams, Catches mit Zeit) | Firestore `history` | nein (verschlüsselt), nur Zeitpunkt des Rundenendes lesbar | wenn der Host die Runde löscht (R-HIST-06), sonst mit Gruppe (keine Standorte enthalten) |
| **Rundenkarte** (R-HIST-04): Spielfeld, alle Pings und ⚡-Pings, Standorte bei Spielende (R-HIST-08), Hunter-Positionen zu den Ping-Zeiten, letzter Hunter-Standort, Catch-Zeiten, Speedhunts, Namen der Runde – ohne UIDs und ohne GPS-Genauigkeit, Koordinaten auf ca. 10 cm gerundet | Firestore `historyMaps/{id}` (gleiche ID wie die Übersicht) | **nein** (AES-GCM), nur Zeitpunkt des Rundenendes lesbar; alle Mitglieder der Gruppe dürfen sie lesen – auch später Beigetretene | **bleibt** über die Runde hinaus: bis der Host die Runde löscht (R-HIST-06) oder die Gruppe gelöscht wird (auch 180-Tage-Löschung) |
| Zeitstempel (Erstellung, Beitritt, Rundenstart, Ablauf) | Firestore | ja | mit Gruppe |
| IP-Adresse | Google (technisch bei jeder Verbindung) | ja | nach Google-Richtlinie |
| Kartenkacheln-Anfragen (Karte oder Satellit) | MapTiler | ja (welcher Kartenausschnitt, IP) | nach MapTiler-Richtlinie |

### Nur zum Testen: Computer-Mitglieder (R-BOT-01 … R-BOT-06)
Nur in Debug-Builds bzw. mit `--dart-define=MANHUNT_BOTS=true`. Das Handy, das sie betreibt, legt pro
Computer-Mitglied ein zusätzliches **anonymes Firebase-Konto** an (höchstens 8 pro Handy, wiederverwendet; verwaist
bei Deinstallation). Sie erzeugen dieselben Daten wie ein echtes Mitglied (Name „🤖 …“ verschlüsselt, Rolle, Pings,
Hunter-Live …) und werden genauso gelöscht. Ihre Standorte sind der Standort des betreibenden Handys ± 200 m – also
ebenfalls verschlüsselt, aber sinngemäß ein weiterer Standort dieser Person. Die gewünschte Anzahl steht verschlüsselt
in den Einstellungen, ebenso der Test-Schalter „Countdown überspringen“ (R-BOT-09).

## Nur auf dem Gerät
- **Gruppenliste** (R-GROUPS-01): bis zu 5 Einträge mit Code, Gruppen-ID, Gruppenname (Kopie) und „bin Host“, dazu
  die zuletzt geöffnete Gruppe – im Schlüsselspeicher des Betriebssystems. Verlassen/Löschen entfernt den Eintrag.
- Die Gruppenübersicht liest pro Gruppe nur das Gruppendokument per ID (Status „Lobby/läuft/gelöscht“); dafür
  wird kein Schlüssel abgeleitet und nichts geschrieben. Erst das Öffnen einer Gruppe verlängert ihre Frist (R-PRIV-05).

## Was es nicht gibt
Kein Konto, keine E-Mail, keine Telefonnummer, kein Analytics, kein Crash-Reporting, keine Push-Tokens, keine Werbung.

## Löschung
- **Rundenende** (automatisch 15 s nach Ablauf der Spielzeit bzw. nach dem letzten Catch, R-GAME-10, oder Abbruch
  durch den Host, R-GAME-07): löscht alle Live-Standorte und Runden-Ereignisse für alle (R-PRIV-03). Vorher wird
  eine verschlüsselte **Rundenkarte** in die Historie geschrieben (R-HIST-04) – das, was alle nach Spielende ohnehin
  sehen durften, plus die Hunter-Positionen zu den Ping-Zeiten. Bewusste Entscheidung der Projektinhaberin
  (2026-11-01): Die Karte bleibt, bis der Host die Runde in der Historie löscht (R-HIST-06) oder die Gruppe gelöscht wird.
- Das Rundenende erledigt mangels Server das erste Mitgliedsgerät, das die Runde 15 s nach ihrem Ende sieht. Dafür
  dürfen ab diesem Zeitpunkt (bis zur Rückkehr in die Lobby) alle Mitglieder die Rundendaten lesen und löschen, die
  Mitglieder zurücksetzen und Historie-Eintrag und Rundenkarte schreiben. Neu zu sehen gibt es dabei kaum etwas:
  Alle Pings und Hunter-Standorte sind seit Spielende für alle sichtbar (R-GAME-06); dazu kommen nur Zeichnungen der
  Hunter, Joker-Antworten und Außerhalb-Standorte (die nicht in die Karte übernommen werden).
- **Gruppe löschen** (Host): löscht alles – Rundendaten, Mitglieder, Gruppe.
- **180 Tage ohne Öffnen** (R-PRIV-05): Jedes Öffnen der Gruppe durch ein Mitglied (max. 1× pro Tag geschrieben) und
  jede Host-Aktion setzt `expiresAt` auf jetzt + 180 Tage. Firestore-TTL gibt es im Spark-Tarif nicht (nur mit Billing), daher räumt das **erste Gerät der
  Gruppe auf, das die App nach Ablauf öffnet**; die Sicherheitsregeln erlauben das jedem Mitglied nur nach Ablauf.
  Restrisiko: Öffnet niemand die App mehr, bleibt die Gruppe (verschlüsselte Namen/Einstellungen und die
  verschlüsselten Rundenkarten mit Standorten) liegen.
- Wird eine Runde nie beendet und öffnet danach auch niemand mehr die App, bleiben deren (verschlüsselte) Standorte
  bis zur 180-Tage-Löschung liegen (R-GAME-10 braucht ein Gerät, das die Gruppe öffnet).

## Standort
Wird nur während eines laufenden Spiels erfasst (R-PRIV-04). Android zeigt dabei eine Dauer-Benachrichtigung.
Ob man das Spielfeld verlassen hat, prüft nur das eigene Handy (R-OUT-01). Die Warnung bleibt auf dem Gerät; erst
nach 30 s eindeutig draußen geht ein Live-Standort an die Hunter (R-OUT-03), und das zeigt die App dem Spieler die
ganze Zeit über an (R-OUT-06).

Joker-Ergebnisse (Hunter-Standorte vom Zeitpunkt jedes eingesetzten Hunter-Jokers bzw. die Kennung der Spieler-Joker-Anfrage) werden nur
**auf dem eigenen Gerät** im Schlüsselspeicher des Betriebssystems abgelegt, damit man sie in der laufenden Runde
wieder einblenden kann (R-PLAY-04). Sie gehören zu genau einer Runde, werden in der nächsten Runde nicht mehr
angezeigt; sie verlassen das Gerät nicht. Mehrere Hunter-Joker einer Runde (R-SET-09) werden nebeneinander
gespeichert.

Dass ein gefangener Spieler die Warnung zur Live-Ansicht bestätigt hat (R-GM-08), merkt sich nur das eigene Gerät
(Schlüsselspeicher, pro Runde, zusammen mit den Joker-Ergebnissen).

Ebenso bleiben die eigenen ⚡-Pings (R-SPEED-09) **nur auf dem Gerät** (Schlüsselspeicher, pro Runde): Zu jedem
Speedhunt-Ping-Zeitpunkt merkt sich jedes Spielerhandy seinen Standort, um ihn anzuzeigen. Gesendet wird nur der
Ping des tatsächlichen Ziels (an die Hunter, wie bisher).

Im Spielfeld-Editor wird der eigene Standort einmal beim Öffnen und auf Knopfdruck abgefragt, um die Karte
dorthin zu bewegen. Er bleibt auf dem Gerät und wird weder gespeichert noch gesendet.
