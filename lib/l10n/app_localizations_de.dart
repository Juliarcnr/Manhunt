// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Manhunt';

  @override
  String get homeTagline => 'Lauf. Versteck dich. Jage.';

  @override
  String get homeCreateGroup => 'Gruppe erstellen';

  @override
  String get homeJoinGroup => 'Mit Code beitreten';

  @override
  String get homePrivacyNote =>
      'Kein Konto, keine E-Mail. Standorte sind Ende-zu-Ende-verschlüsselt und werden nach dem Spiel gelöscht.';

  @override
  String get roleHunter => 'Hunter';

  @override
  String get rolePlayer => 'Spieler';

  @override
  String get roleHunters => 'Hunter';

  @override
  String get rolePlayers => 'Spieler';

  @override
  String get roleUnassigned => 'Noch nicht eingeteilt';

  @override
  String get speedhuntActive => 'Speedhunt aktiv';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonRetry => 'Erneut versuchen';

  @override
  String commonError(String details) {
    return 'Etwas ist schiefgelaufen: $details';
  }

  @override
  String get yourName => 'Dein Name';

  @override
  String get yourNameHint => 'So sehen dich die anderen';

  @override
  String get nameRequired => 'Bitte gib einen Namen ein';

  @override
  String get createTitle => 'Neue Gruppe';

  @override
  String get createButton => 'Gruppe erstellen';

  @override
  String get createWorking => 'Gruppe wird erstellt…';

  @override
  String get joinTitle => 'Gruppe beitreten';

  @override
  String get joinCode => 'Gruppencode';

  @override
  String get joinCodeHint => 'ABCDE-FGHJK';

  @override
  String get joinButton => 'Beitreten';

  @override
  String get joinWorking => 'Trete bei…';

  @override
  String get joinInvalidCode => 'Der Code hat 10 Zeichen, z.B. ABCDE-FGHJK';

  @override
  String get joinNotFound => 'Keine Gruppe mit diesem Code gefunden';

  @override
  String get settingsTitle => 'Spieleinstellungen';

  @override
  String get settingsSectionGame => 'Spiel';

  @override
  String get settingsSectionPings => 'Pings';

  @override
  String get settingsSectionSpeedhunt => 'Speedhunt';

  @override
  String get settingsSectionTeams => 'Teams';

  @override
  String get settingsDuration => 'Spieldauer';

  @override
  String get settingsHeadStart => 'Vorlauf für Spieler';

  @override
  String get settingsPingInterval => 'Ping alle';

  @override
  String get settingsSpeedhuntCount => 'Speedhunts für Hunter';

  @override
  String get settingsSpeedhuntPings => 'Pings pro Speedhunt';

  @override
  String get settingsSpeedhuntInterval => 'Abstand der Speedhunt-Pings';

  @override
  String get settingsSpeedhuntEarliest => 'Erster Speedhunt ab';

  @override
  String get settingsHunterCount => 'Anzahl Hunter';

  @override
  String get settingsJoker => 'Joker: Hunter-Standorte';

  @override
  String get settingsJokerHint =>
      'Jeder Spieler darf einmal sehen, wo die Hunter gerade sind.';

  @override
  String get settingsPlayerJoker => 'Joker: Spieler-Standorte';

  @override
  String get settingsPlayerJokerHint =>
      'Jeder Spieler darf einmal sehen, wo alle anderen Spieler gerade sind.';

  @override
  String get settingsArea => 'Spielfeld';

  @override
  String get settingsAreaMissing => 'Noch nicht eingezeichnet';

  @override
  String get areaTitle => 'Spielfeld einzeichnen';

  @override
  String get areaHint =>
      'Tippe auf die Karte, um Eckpunkte zu setzen. Ziehen verschiebt, lange drücken löscht, „+“ fügt einen Punkt ein.';

  @override
  String areaStats(int points, String area, String width, String height) {
    return '$points Eckpunkte · ≈ $area km² · $width × $height km';
  }

  @override
  String get areaNeedPoints => 'Mindestens 3 Eckpunkte setzen';

  @override
  String get areaCrossing =>
      'Die Ränder überkreuzen sich – bitte Form korrigieren';

  @override
  String get areaUndo => 'Rückgängig';

  @override
  String get areaClear => 'Alles löschen';

  @override
  String get areaMyLocation => 'Mein Standort';

  @override
  String get areaLocationUnavailable =>
      'Standort nicht verfügbar – Berechtigung und GPS prüfen';

  @override
  String get areaSave => 'Als Spielfeld übernehmen';

  @override
  String get areaDraw => 'Spielfeld einzeichnen';

  @override
  String get areaEdit => 'Spielfeld bearbeiten';

  @override
  String settingsAreaPoints(int count) {
    return '$count Eckpunkte';
  }

  @override
  String minutes(int count) {
    return '$count min';
  }

  @override
  String hoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get errorDurationTooShort => 'Das Spiel braucht eine Dauer';

  @override
  String get errorHeadStartInvalid =>
      'Der Vorlauf muss kürzer als das Spiel sein';

  @override
  String get errorPingIntervalTooShort => 'Ping-Abstand ist zu kurz';

  @override
  String get errorSpeedhuntInvalid => 'Bitte Speedhunt-Einstellungen prüfen';

  @override
  String get errorHunterCountInvalid => 'Es braucht mindestens einen Hunter';

  @override
  String get errorNotEnoughPlayers => 'Es braucht mindestens einen Spieler';

  @override
  String get errorAreaMissing => 'Zuerst das Spielfeld einzeichnen';

  @override
  String get errorUnassigned => 'Alle brauchen eine Rolle';

  @override
  String get lobbyTitle => 'Lobby';

  @override
  String get lobbyCodeLabel => 'Gruppencode';

  @override
  String get lobbyCodeCopied => 'Code kopiert';

  @override
  String get lobbyShareHint => 'Mit diesem Code treten Freunde bei.';

  @override
  String lobbyParticipants(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Personen',
      one: '1 Person',
    );
    return '$_temp0';
  }

  @override
  String get lobbyAssignRandom => 'Zufällig einteilen';

  @override
  String get lobbyTapToSwitch =>
      'Tippe auf eine Person, um Hunter ↔ Spieler zu tauschen.';

  @override
  String get lobbyStart => 'Spiel starten';

  @override
  String get lobbyWaitingForAdmin =>
      'Warte darauf, dass das Spiel gestartet wird…';

  @override
  String get lobbyAdminBadge => 'Host';

  @override
  String get lobbyYouBadge => 'Du';

  @override
  String lobbyRemoveMember(String name) {
    return '$name entfernen?';
  }

  @override
  String get lobbyRemove => 'Entfernen';

  @override
  String get lobbyLeave => 'Gruppe verlassen';

  @override
  String get lobbyDelete => 'Gruppe löschen';

  @override
  String get lobbyDeleteConfirm =>
      'Gruppe für alle löschen? Das kann nicht rückgängig gemacht werden.';

  @override
  String get lobbyGroupGone => 'Diese Gruppe gibt es nicht mehr.';

  @override
  String get lobbyBackHome => 'Zurück zum Start';

  @override
  String get gamePhaseStarting => 'Startet…';

  @override
  String get gamePhaseHeadStart => 'Vorlauf – Hunter warten';

  @override
  String get gamePhaseHunting => 'Die Jagd läuft';

  @override
  String get gamePhaseTimeUp => 'Zeit abgelaufen';

  @override
  String get gameTimeUpHint =>
      'Die Runde läuft weiter, damit ihr euch die Standorte noch gemeinsam anschauen könnt. Der Host beendet sie.';

  @override
  String get gameEndButton => 'Spiel beenden';

  @override
  String get gameEndConfirmTitle => 'Spiel beenden?';

  @override
  String get gameEndConfirmText =>
      'Aus Datenschutzgründen werden jetzt alle sensiblen Daten dieser Runde – insbesondere alle Standorte – für alle endgültig gelöscht. Die Gruppe bleibt bestehen und ihr könnt eine neue Runde starten.';

  @override
  String get gameEndConfirmAction => 'Beenden und löschen';

  @override
  String get gameAbortTitle => 'Spiel vorzeitig abbrechen?';

  @override
  String gameAbortText(String remaining) {
    return 'Das Spiel läuft noch (noch $remaining). Willst du es wirklich jetzt abbrechen?';
  }

  @override
  String get gameAbortContinue => 'Ja, abbrechen';

  @override
  String get gameAbortFinalTitle => 'Wirklich abbrechen?';

  @override
  String get gameAbortFinalAction => 'Endgültig abbrechen';

  @override
  String get historyAborted => 'vorzeitig abgebrochen';

  @override
  String gameNextPing(String time) {
    return 'Nächster Ping in $time';
  }

  @override
  String get gameCaughtSelf =>
      'Du wurdest gefangen – dein Standort wird nicht mehr geteilt.';

  @override
  String gameSpeedhuntUntil(String time) {
    return 'Speedhunt aktiv bis $time';
  }

  @override
  String get gameYou => 'Du';

  @override
  String get gameNoPingsYet => 'Noch keine Pings';

  @override
  String get trackingTitle => 'Manhunt läuft';

  @override
  String get trackingText =>
      'Dein Standort wird für das Spiel mit deiner Gruppe geteilt.';

  @override
  String get trackingWaiting => 'Warte auf GPS-Signal …';

  @override
  String get trackingOk => 'GPS ok';

  @override
  String trackingOkLastPing(String time) {
    return 'GPS ok · letzter Ping $time';
  }

  @override
  String get trackingNoPermission =>
      'Kein Standortzugriff – bitte in den Einstellungen erlauben (genauer Standort), dann erneut versuchen.';

  @override
  String get trackingError => 'GPS-Problem – wird automatisch neu gestartet …';

  @override
  String speedhuntButton(int left) {
    return 'Speedhunt ($left)';
  }

  @override
  String get speedhuntTitle => 'Speedhunt starten';

  @override
  String get speedhuntWho => 'Auf wen?';

  @override
  String speedhuntInfo(int pings, int minutes) {
    return '$pings Standorte im Abstand von $minutes min. Die Spieler erfahren nur, dass ein Speedhunt läuft – nicht auf wen.';
  }

  @override
  String get speedhuntConfirm => 'Starten';

  @override
  String get speedhuntNotHunting =>
      'Speedhunts sind erst nach dem Vorlauf möglich.';

  @override
  String speedhuntTooEarly(int minutes) {
    return 'Der erste Speedhunt ist erst $minutes min nach Spielstart möglich.';
  }

  @override
  String get speedhuntNoneLeft => 'Keine Speedhunts mehr übrig.';

  @override
  String get speedhuntAlreadyRunning => 'Es läuft bereits ein Speedhunt.';

  @override
  String get speedhuntInvalidTarget =>
      'Auf diesen Spieler ist kein Speedhunt möglich.';

  @override
  String get jokerButton => 'Joker';

  @override
  String get jokerHuntersOption => 'Hunter-Standorte';

  @override
  String get jokerHuntersHint => 'Einmalig sehen, wo die Hunter gerade sind';

  @override
  String get jokerPlayersOption => 'Spieler-Standorte';

  @override
  String get jokerPlayersHint =>
      'Einmalig sehen, wo alle anderen Spieler gerade sind';

  @override
  String get jokerAlreadyUsed => 'Bereits benutzt';

  @override
  String get jokerPlayersTitle => 'Spieler-Joker einsetzen?';

  @override
  String get jokerPlayersText =>
      'Die Handys aller anderen aktiven Spieler senden dir einmalig ihren aktuellen Standort. Danach ist dieser Joker verbraucht.';

  @override
  String jokerPlayersResult(String time) {
    return 'Spieler um $time (Joker)';
  }

  @override
  String get jokerTitle => 'Hunter-Joker einsetzen?';

  @override
  String get jokerText =>
      'Du siehst einmalig die aktuellen Standorte der Hunter. Danach ist der Joker verbraucht.';

  @override
  String get jokerConfirm => 'Joker einsetzen';

  @override
  String jokerResult(String time) {
    return 'Hunter um $time (Joker)';
  }

  @override
  String get jokerNoHunters => 'Gerade keine Hunter-Standorte verfügbar.';

  @override
  String noticeCaught(String player) {
    return '$player wurde gefangen';
  }

  @override
  String get noticeSpeedhunt => 'Speedhunt gestartet!';

  @override
  String noticeSpeedhuntBody(int pings, int minutes) {
    return 'Ein Spieler wird $pings× im Abstand von $minutes min geortet.';
  }

  @override
  String get noticePingSent => 'Dein Standort wurde an die Hunter gesendet';

  @override
  String get noticeSpeedhuntPingSent =>
      'Speedhunt: Dein Standort wurde an die Hunter gesendet';

  @override
  String get catchTitle => 'Catch melden';

  @override
  String get catchWho => 'Wer wurde gefangen?';

  @override
  String get catchConfirm => 'Catch melden';

  @override
  String get catchSelfTitle => 'Ich wurde gefangen';

  @override
  String get catchSelfText =>
      'Du wirst als gefangen markiert und alle bekommen eine Benachrichtigung.';

  @override
  String get catchSelfConfirm => 'Ja, gefangen';

  @override
  String get historyTitle => 'Historie';

  @override
  String get historyEmpty =>
      'Noch keine beendeten Runden. Nach „Spiel beenden“ erscheint hier jede Runde – ohne Standorte.';

  @override
  String historyRound(int number) {
    return 'Runde $number';
  }

  @override
  String get historyCatches => 'Catches';

  @override
  String get historyNoCatches => 'Niemand wurde gefangen.';

  @override
  String get historySurvivors => 'Nicht gefangen';

  @override
  String get historyAllCaught => 'Alle Spieler gefangen!';
}
