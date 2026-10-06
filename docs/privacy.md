# Datenschutz

Ziel: so wenig Daten wie möglich (R-PRIV-01 … R-PRIV-05). **Jede Änderung an gespeicherten Daten hier eintragen.**

## Was verlässt das Gerät?
| Datum | Wohin | Lesbar für Firebase/Google? | Löschung |
|---|---|---|---|
| Anonyme Firebase-UID | Firebase Auth | ja (zufällige ID, keine E-Mail/kein Name) | bei App-Deinstallation verwaist |
| Gruppen-ID (aus Code abgeleitet) | Firestore | ja, aber ohne Rückschluss auf den Code | mit Gruppe |
| Anzeigename | Firestore | nein (verschlüsselt) | mit Gruppe |
| Rolle, gefangen, Joker benutzt | Firestore | ja (nötig für Regeln) | Rolle mit Gruppe; gefangen/Joker bei Rundenende zurückgesetzt |
| Spielfeld & Einstellungen | Firestore | nein (verschlüsselt) | mit Gruppe |
| Standorte (Pings, Hunter-Live), Speedhunt-/Catch-Ereignisse | Firestore | **nein** (AES-GCM) | **beim Beenden der Runde** |
| Antworten auf den Spieler-Joker (aktueller Standort der anderen Spieler) | Firestore | **nein** (AES-GCM); nur der fragende Spieler darf sie lesen | beim Beenden der Runde |
| Metadaten der Runde: wer wann gepingt hat (uid, Ping-Nr.), Ziel-uid eines Speedhunts, wer einen Joker wann benutzt hat | Firestore | ja (nötig für die Sicherheitsregeln; nur anonyme IDs, keine Orte) | beim Beenden der Runde (Joker-Zeitpunkte bleiben bis zur nächsten Runde) |
| Rundenübersicht (Runde, Datum, Dauer, Teams, Catches mit Zeit und Hunter) | Firestore `history` | nein (verschlüsselt), nur Zeitpunkt des Rundenendes lesbar | mit Gruppe (keine Standorte enthalten) |
| Zeitstempel (Erstellung, Beitritt, Rundenstart, Ablauf) | Firestore | ja | mit Gruppe |
| IP-Adresse | Google (technisch bei jeder Verbindung) | ja | nach Google-Richtlinie |
| Kartenkacheln-Anfragen | MapTiler | ja (welcher Kartenausschnitt, IP) | nach MapTiler-Richtlinie |

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

Im Spielfeld-Editor wird der eigene Standort einmal beim Öffnen und auf Knopfdruck abgefragt, um die Karte
dorthin zu bewegen. Er bleibt auf dem Gerät und wird weder gespeichert noch gesendet.
