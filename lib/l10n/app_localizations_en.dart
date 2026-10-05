// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Manhunt';

  @override
  String get homeTagline => 'Run. Hide. Hunt.';

  @override
  String get homeCreateGroup => 'Create group';

  @override
  String get homeJoinGroup => 'Join with code';

  @override
  String get homePrivacyNote =>
      'No account, no email. Locations are end-to-end encrypted and deleted after the game.';

  @override
  String get roleHunter => 'Hunter';

  @override
  String get rolePlayer => 'Player';

  @override
  String get roleHunters => 'Hunters';

  @override
  String get rolePlayers => 'Players';

  @override
  String get roleUnassigned => 'Not assigned yet';

  @override
  String get speedhuntActive => 'Speedhunt active';

  @override
  String get overviewTitle => 'Overview';

  @override
  String get overviewNoSpeedhunt => 'No speedhunt running';

  @override
  String overviewStillFree(int free, int total) {
    return '$free of $total free';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonClose => 'Close';

  @override
  String get debugLogTitle => 'Tracking log';

  @override
  String commonError(String details) {
    return 'Something went wrong: $details';
  }

  @override
  String get yourName => 'Your name';

  @override
  String get yourNameHint => 'How others see you';

  @override
  String get nameRequired => 'Please enter a name';

  @override
  String get createTitle => 'New group';

  @override
  String get createButton => 'Create group';

  @override
  String get createWorking => 'Creating group…';

  @override
  String get joinTitle => 'Join group';

  @override
  String get joinCode => 'Group code';

  @override
  String get joinCodeHint => 'ABCDE-FGHJK';

  @override
  String get joinButton => 'Join';

  @override
  String get joinWorking => 'Joining…';

  @override
  String get joinInvalidCode => 'The code has 10 characters, e.g. ABCDE-FGHJK';

  @override
  String get joinNotFound => 'No group with this code';

  @override
  String get settingsTitle => 'Game settings';

  @override
  String get settingsSectionGame => 'Game';

  @override
  String get settingsSectionPings => 'Pings';

  @override
  String get settingsSectionSpeedhunt => 'Speedhunt';

  @override
  String get settingsSectionTeams => 'Teams';

  @override
  String get settingsDuration => 'Game duration';

  @override
  String get settingsHeadStart => 'Head start for players';

  @override
  String get settingsPingInterval => 'Ping every';

  @override
  String get settingsSpeedhuntCount => 'Speedhunts for hunters';

  @override
  String get settingsSpeedhuntPings => 'Pings per speedhunt';

  @override
  String get settingsSpeedhuntInterval => 'Time between speedhunt pings';

  @override
  String get settingsSpeedhuntEarliest => 'First speedhunt after';

  @override
  String get settingsSpeedhuntFirstDelay => 'First speedhunt ping after';

  @override
  String get settingsHunterCount => 'Number of hunters';

  @override
  String get settingsJoker => 'Joker: hunter positions';

  @override
  String get settingsJokerHint =>
      'Each player may see where the hunters are once.';

  @override
  String get settingsPlayerJoker => 'Joker: player positions';

  @override
  String get settingsPlayerJokerHint =>
      'Each player may see where all other players are once.';

  @override
  String get settingsArea => 'Play area';

  @override
  String get settingsAreaMissing => 'Not drawn yet';

  @override
  String get areaTitle => 'Draw play area';

  @override
  String get areaHint =>
      'Tap the map to set corners. Drag to move, long-press to delete, „+“ inserts a corner.';

  @override
  String areaStats(int points, String area, String width, String height) {
    return '$points corners · ≈ $area km² · $width × $height km';
  }

  @override
  String get areaNeedPoints => 'Set at least 3 corners';

  @override
  String get areaCrossing => 'The edges cross – please fix the shape';

  @override
  String get areaUndo => 'Undo';

  @override
  String get areaClear => 'Clear all';

  @override
  String get areaMyLocation => 'My location';

  @override
  String get areaLocationUnavailable =>
      'Location not available – check permission and GPS';

  @override
  String get areaSave => 'Use as play area';

  @override
  String get areaDraw => 'Draw play area';

  @override
  String get areaEdit => 'Edit play area';

  @override
  String settingsAreaPoints(int count) {
    return '$count corners';
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
  String get errorDurationTooShort => 'The game needs a duration';

  @override
  String get errorHeadStartInvalid =>
      'Head start must be shorter than the game';

  @override
  String get errorPingIntervalTooShort => 'Ping interval is too short';

  @override
  String get errorSpeedhuntInvalid => 'Check the speedhunt settings';

  @override
  String get errorHunterCountInvalid => 'At least one hunter is needed';

  @override
  String get errorNotEnoughPlayers => 'At least one player is needed';

  @override
  String get errorAreaMissing => 'Draw the play area first';

  @override
  String get errorUnassigned => 'Everyone needs a role';

  @override
  String get lobbyTitle => 'Lobby';

  @override
  String get lobbyCodeLabel => 'Group code';

  @override
  String get lobbyCodeCopied => 'Code copied';

  @override
  String get lobbyShareHint => 'Friends join with this code.';

  @override
  String lobbyParticipants(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count participants',
      one: '1 participant',
    );
    return '$_temp0';
  }

  @override
  String get lobbyAssignRandom => 'Random teams';

  @override
  String get lobbyTapToSwitch => 'Tap a person to switch hunter ↔ player.';

  @override
  String get lobbyStart => 'Start game';

  @override
  String get lobbyWaitingForAdmin => 'Waiting for the host to start…';

  @override
  String get lobbyAdminBadge => 'Host';

  @override
  String get lobbyYouBadge => 'You';

  @override
  String lobbyRemoveMember(String name) {
    return 'Remove $name?';
  }

  @override
  String get lobbyRemove => 'Remove';

  @override
  String get removeMemberText =>
      'They will be removed from the group. With the code they can join again.';

  @override
  String get removedTitle => 'You were removed from the group by the host.';

  @override
  String get lobbyLeave => 'Leave group';

  @override
  String get lobbyDelete => 'Delete group';

  @override
  String get lobbyDeleteConfirm =>
      'Delete the group for everyone? This cannot be undone.';

  @override
  String get lobbyGroupGone => 'This group no longer exists.';

  @override
  String get lobbyBackHome => 'Back to start';

  @override
  String get gamePhaseStarting => 'Starting…';

  @override
  String get gamePhaseHeadStart => 'Head start – hunters wait';

  @override
  String get gamePhaseHunting => 'Hunt is on';

  @override
  String get gamePhaseTimeUp => 'Time is up';

  @override
  String get gameTimeUpHint =>
      'The round keeps running so you can look at the locations together. The host ends it.';

  @override
  String get gameEndButton => 'End game';

  @override
  String get gameEndConfirmTitle => 'End game?';

  @override
  String get gameEndConfirmText =>
      'For privacy, all sensitive data of this round – especially all locations – will now be deleted permanently for everyone. The group stays and you can start a new round.';

  @override
  String get gameEndConfirmAction => 'End and delete';

  @override
  String get gameAbortTitle => 'Abort the game early?';

  @override
  String gameAbortText(String remaining) {
    return 'The game is still running ($remaining left). Do you really want to abort it now?';
  }

  @override
  String get gameAbortContinue => 'Yes, abort';

  @override
  String get gameAbortFinalTitle => 'Really abort?';

  @override
  String get gameAbortFinalAction => 'Abort for good';

  @override
  String get historyAborted => 'aborted early';

  @override
  String gameNextPing(String time) {
    return 'Next ping in $time';
  }

  @override
  String get gameCaughtSelf =>
      'You were caught – your location is no longer shared.';

  @override
  String gameSpeedhuntNext(int number, int total, String time) {
    return 'Speedhunt active · ping $number/$total in $time';
  }

  @override
  String get gameYou => 'You';

  @override
  String get gameNoPingsYet => 'No pings yet';

  @override
  String get trackingTitle => 'Manhunt is running';

  @override
  String get trackingText =>
      'Your location is shared with your group for the game.';

  @override
  String get trackingWaiting => 'Waiting for GPS signal …';

  @override
  String get trackingNoPermission =>
      'No location access – please allow it in the settings (precise location), then retry.';

  @override
  String get trackingError => 'GPS problem – restarting automatically …';

  @override
  String speedhuntButton(int left) {
    return 'Speedhunt ($left)';
  }

  @override
  String get speedhuntTitle => 'Start speedhunt';

  @override
  String get speedhuntWho => 'On whom?';

  @override
  String speedhuntInfo(int pings, int minutes) {
    return '$pings locations, $minutes min apart. Players only learn that a speedhunt is running – not on whom.';
  }

  @override
  String speedhuntInfoDelay(int minutes) {
    return 'The first location is sent $minutes min after starting.';
  }

  @override
  String get speedhuntConfirm => 'Start';

  @override
  String get speedhuntNotHunting =>
      'Speedhunts are possible once the hunters are released.';

  @override
  String speedhuntTooEarly(int minutes) {
    return 'The first speedhunt is possible $minutes min after the start.';
  }

  @override
  String get speedhuntNoneLeft => 'No speedhunts left.';

  @override
  String get speedhuntAlreadyRunning => 'A speedhunt is already running.';

  @override
  String get speedhuntInvalidTarget => 'This player cannot be speedhunted.';

  @override
  String get jokerButton => 'Joker';

  @override
  String get jokerHuntersOption => 'Hunter positions';

  @override
  String get jokerHuntersHint => 'See once where the hunters are right now';

  @override
  String get jokerPlayersOption => 'Player positions';

  @override
  String get jokerPlayersHint =>
      'See once where all other players are right now';

  @override
  String get jokerAlreadyUsed => 'Already used';

  @override
  String get jokerPlayersTitle => 'Use player joker?';

  @override
  String get jokerPlayersText =>
      'All other active players\' phones send you their current position once. Afterwards this joker is used up.';

  @override
  String jokerPlayersResult(String time) {
    return 'Players at $time (joker)';
  }

  @override
  String get jokerTitle => 'Use hunter joker?';

  @override
  String get jokerText =>
      'You will see the hunters\' current positions once. Afterwards the joker is used up.';

  @override
  String get jokerConfirm => 'Use joker';

  @override
  String jokerResult(String time) {
    return 'Hunters at $time (joker)';
  }

  @override
  String get jokerNoHunters => 'No hunter positions available right now.';

  @override
  String noticeCaught(String player) {
    return '$player was caught';
  }

  @override
  String get noticeSpeedhunt => 'Speedhunt started!';

  @override
  String noticeSpeedhuntBody(int pings, int minutes) {
    return 'A player will be located $pings× every $minutes min.';
  }

  @override
  String get noticePingSent => 'Your location was sent to the hunters';

  @override
  String get catchTitle => 'Report catch';

  @override
  String get catchWho => 'Who was caught?';

  @override
  String get catchConfirm => 'Report catch';

  @override
  String get catchSelfTitle => 'I was caught';

  @override
  String get catchSelfText =>
      'You will be marked as caught and everyone will be notified.';

  @override
  String get catchSelfConfirm => 'Yes, caught';

  @override
  String get historyTitle => 'History';

  @override
  String get historyEmpty =>
      'No finished rounds yet. After „End game“ each round appears here – without locations.';

  @override
  String historyRound(int number) {
    return 'Round $number';
  }

  @override
  String get historyCatches => 'Catches';

  @override
  String get historyNoCatches => 'Nobody was caught.';

  @override
  String get historySurvivors => 'Not caught';

  @override
  String get historyAllCaught => 'All players caught!';
}
