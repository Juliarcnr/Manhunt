# Datenschutz

Ziel: so wenig Daten wie möglich (R-PRIV-01 … R-PRIV-05). **Jede Änderung an gespeicherten Daten hier eintragen.**

## Was verlässt das Gerät?
| Datum | Wohin | Lesbar für Firebase/Google? | Löschung |
|---|---|---|---|
| Anonyme Firebase-UID | Firebase Auth | ja (zufällige ID, keine E-Mail/kein Name) | bei App-Deinstallation verwaist |
| Gruppen-ID (aus Code abgeleitet) | Firestore | ja, aber ohne Rückschluss auf den Code | mit Gruppe |
| Anzeigename | Firestore | nein (verschlüsselt) | mit Gruppe |
| Gruppenname (R-GROUPS-04) | Firestore | nein (verschlüsselt) | mit Gruppe |
| Rolle, gefangen, Joker benutzt | Firestore | ja (nötig für Regeln) | Rolle mit Gruppe; gefangen/Joker bei Rundenende zurückgesetzt |
| Spielfeld & Einstellungen | Firestore | nein (verschlüsselt) | mit Gruppe |
| Anonyme Spielernummern der Runde (R-ANON-01): Zuordnung UID → „Spieler n“ | Firestore `games/{id}.aliases` | nein (verschlüsselt) | beim Beenden der Runde |
| Schalter „Reguläre Pings an alle Spieler“ (R-SET-15) | Firestore `games/{id}.sharedPings` | ja (Klartext-Kopie aus den verschlüsselten Einstellungen, nötig für die Sicherheitsregeln; verrät nur die Spielvariante) | mit Gruppe |
| Standorte (Pings, Hunter-Live), Speedhunt-/Catch-Ereignisse | Firestore | **nein** (AES-GCM). Mit R-SET-15 dürfen auch Spieler die regulären Pings lesen (nie Speedhunt-Pings) | **beim Beenden der Runde** |
| Antworten auf den Spieler-Joker (aktueller Standort der anderen Spieler) | Firestore | **nein** (AES-GCM); nur der fragende Spieler darf sie lesen | beim Beenden der Runde |
| Metadaten der Runde: wer wann gepingt hat (uid, Ping-Nr.), Ziel-uid eines Speedhunts, wer einen Joker wann benutzt hat | Firestore | ja (nötig für die Sicherheitsregeln; nur anonyme IDs, keine Orte) | beim Beenden der Runde (Joker-Zeitpunkte bleiben bis zur nächsten Runde) |
| Rundenübersicht (Runde, Datum, Dauer, Teams, Catches mit Zeit und Hunter) | Firestore `history` | nein (verschlüsselt), nur Zeitpunkt des Rundenendes lesbar | mit Gruppe (keine Standorte enthalten) |
| Zeitstempel (Erstellung, Beitritt, Rundenstart, Ablauf) | Firestore | ja | mit Gruppe |
| IP-Adresse | Google (technisch bei jeder Verbindung) | ja | nach Google-Richtlinie |
| Kartenkacheln-Anfragen (Karte oder Satellit) | MapTiler | ja (welcher Kartenausschnitt, IP) | nach MapTiler-Richtlinie |

## Nur auf dem Gerät
- **Gruppenliste** (R-GROUPS-01): bis zu 5 Einträge mit Code, Gruppen-ID, Gruppenname (Kopie) und „bin Host“, dazu
  die zuletzt geöffnete Gruppe – im Schlüsselspeicher des Betriebssystems. Verlassen/Löschen entfernt den Eintrag.
- Die Gruppenübersicht liest pro Gruppe nur das Gruppendokument per ID (Status „Lobby/läuft/gelöscht“); dafür
  wird kein Schlüssel abgeleitet und nichts geschrieben. Erst das Öffnen einer Gruppe verlängert ihre Frist (R-PRIV-05).

## Was es nicht gibt
Kein Konto, keine E-Mail, keine Telefonnummer, kein Analytics, kein Crash-Reporting, keine Push-Tokens, keine Werbung.

## Löschung
- **Runde beenden** (Host, mit Warnhinweis): löscht sofort alle Standorte und Runden-Ereignisse für alle (R-PRIV-03).
  Nach Ablauf der Spielzeit läuft die Runde bewusst weiter, damit man die Standorte noch gemeinsam ansehen kann.
- **Gruppe löschen** (Host): löscht alles – Rundendaten, Mitglieder, Gruppe.
- **180 Tage ohne Öffnen** (R-PRIV-05): Jedes Öffnen der Gruppe durch ein Mitglied (max. 1× pro Tag geschrieben) und
  jede Host-Aktion setzt `expiresAt` auf jetzt + 180 Tage. Firestore-TTL gibt es im Spark-Tarif nicht (nur mit Billing), daher räumt das **erste Gerät der
  Gruppe auf, das die App nach Ablauf öffnet**; die Sicherheitsregeln erlauben das jedem Mitglied nur nach Ablauf.
  Restrisiko: Öffnet niemand die App mehr, bleibt die Gruppe (verschlüsselte Namen/Einstellungen, ohne Standorte,
  sofern die Runde beendet wurde) liegen.
- Wird eine Runde nie beendet, bleiben auch deren (verschlüsselte) Standorte bis zur 180-Tage-Löschung liegen.

## Standort
Wird nur während eines laufenden Spiels erfasst (R-PRIV-04). Android zeigt dabei eine Dauer-Benachrichtigung.

Joker-Ergebnisse (Hunter-Standorte vom Zeitpunkt des Jokers bzw. die Kennung der Spieler-Joker-Anfrage) werden nur
**auf dem eigenen Gerät** im Schlüsselspeicher des Betriebssystems abgelegt, damit man sie in der laufenden Runde
wieder einblenden kann (R-PLAY-04). Sie gehören zu genau einer Runde, werden in der nächsten Runde nicht mehr
angezeigt und beim nächsten Joker überschrieben; sie verlassen das Gerät nicht.

Ebenso bleiben die eigenen ⚡-Pings (R-SPEED-09) **nur auf dem Gerät** (Schlüsselspeicher, pro Runde): Zu jedem
Speedhunt-Ping-Zeitpunkt merkt sich jedes Spielerhandy seinen Standort, um ihn anzuzeigen. Gesendet wird nur der
Ping des tatsächlichen Ziels (an die Hunter, wie bisher).

Im Spielfeld-Editor wird der eigene Standort einmal beim Öffnen und auf Knopfdruck abgefragt, um die Karte
dorthin zu bewegen. Er bleibt auf dem Gerät und wird weder gespeichert noch gesendet.
