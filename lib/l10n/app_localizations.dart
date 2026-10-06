import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Manhunt'**
  String get appTitle;

  /// No description provided for @homeTagline.
  ///
  /// In en, this message translates to:
  /// **'Run. Hide. Hunt.'**
  String get homeTagline;

  /// No description provided for @homeCreateGroup.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get homeCreateGroup;

  /// No description provided for @homeJoinGroup.
  ///
  /// In en, this message translates to:
  /// **'Join with code'**
  String get homeJoinGroup;

  /// No description provided for @homePrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'No account, no email. Locations are end-to-end encrypted and deleted after the game.'**
  String get homePrivacyNote;

  /// No description provided for @groupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your groups'**
  String get groupsTitle;

  /// No description provided for @groupsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max}'**
  String groupsCount(int count, int max);

  /// No description provided for @groupsUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Group {code}'**
  String groupsUnnamed(String code);

  /// No description provided for @groupsRunning.
  ///
  /// In en, this message translates to:
  /// **'Round running'**
  String get groupsRunning;

  /// No description provided for @groupsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get groupsDeleted;

  /// No description provided for @groupsGone.
  ///
  /// In en, this message translates to:
  /// **'This group no longer exists.'**
  String get groupsGone;

  /// No description provided for @groupsLimitReached.
  ///
  /// In en, this message translates to:
  /// **'You can be in at most {max} groups. Leave one to create or join another.'**
  String groupsLimitReached(int max);

  /// No description provided for @groupsBack.
  ///
  /// In en, this message translates to:
  /// **'All groups'**
  String get groupsBack;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @groupNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Friday crew'**
  String get groupNameHint;

  /// No description provided for @groupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a group name'**
  String get groupNameRequired;

  /// No description provided for @lobbyRename.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get lobbyRename;

  /// No description provided for @roleHunter.
  ///
  /// In en, this message translates to:
  /// **'Hunter'**
  String get roleHunter;

  /// No description provided for @rolePlayer.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get rolePlayer;

  /// No description provided for @roleHunters.
  ///
  /// In en, this message translates to:
  /// **'Hunters'**
  String get roleHunters;

  /// No description provided for @rolePlayers.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get rolePlayers;

  /// No description provided for @roleUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Not assigned yet'**
  String get roleUnassigned;

  /// No description provided for @speedhuntActive.
  ///
  /// In en, this message translates to:
  /// **'Speedhunt active'**
  String get speedhuntActive;

  /// No description provided for @overviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overviewTitle;

  /// No description provided for @filterHunters.
  ///
  /// In en, this message translates to:
  /// **'Hunters'**
  String get filterHunters;

  /// No description provided for @filterLastPings.
  ///
  /// In en, this message translates to:
  /// **'Last pings'**
  String get filterLastPings;

  /// No description provided for @filterSpeedhunt.
  ///
  /// In en, this message translates to:
  /// **'{name} {time}'**
  String filterSpeedhunt(String name, String time);

  /// No description provided for @filterMyPings.
  ///
  /// In en, this message translates to:
  /// **'My pings'**
  String get filterMyPings;

  /// No description provided for @filterHunterJoker.
  ///
  /// In en, this message translates to:
  /// **'Hunters {time}'**
  String filterHunterJoker(String time);

  /// No description provided for @filterPlayerJoker.
  ///
  /// In en, this message translates to:
  /// **'Players {time}'**
  String filterPlayerJoker(String time);

  /// No description provided for @overviewNoSpeedhunt.
  ///
  /// In en, this message translates to:
  /// **'No speedhunt running'**
  String get overviewNoSpeedhunt;

  /// No description provided for @overviewStillFree.
  ///
  /// In en, this message translates to:
  /// **'{free} of {total} free'**
  String overviewStillFree(int free, int total);

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @debugLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Tracking log'**
  String get debugLogTitle;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {details}'**
  String commonError(String details);

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @yourNameHint.
  ///
  /// In en, this message translates to:
  /// **'How others see you'**
  String get yourNameHint;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get nameRequired;

  /// No description provided for @createTitle.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get createTitle;

  /// No description provided for @createButton.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createButton;

  /// No description provided for @createWorking.
  ///
  /// In en, this message translates to:
  /// **'Creating group…'**
  String get createWorking;

  /// No description provided for @joinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join group'**
  String get joinTitle;

  /// No description provided for @joinCode.
  ///
  /// In en, this message translates to:
  /// **'Group code'**
  String get joinCode;

  /// No description provided for @joinCodeHint.
  ///
  /// In en, this message translates to:
  /// **'ABCDE-FGHJK'**
  String get joinCodeHint;

  /// No description provided for @joinButton.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinButton;

  /// No description provided for @joinWorking.
  ///
  /// In en, this message translates to:
  /// **'Joining…'**
  String get joinWorking;

  /// No description provided for @joinInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'The code has 10 characters, e.g. ABCDE-FGHJK'**
  String get joinInvalidCode;

  /// No description provided for @joinNotFound.
  ///
  /// In en, this message translates to:
  /// **'No group with this code'**
  String get joinNotFound;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Game settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionGame.
  ///
  /// In en, this message translates to:
  /// **'Game'**
  String get settingsSectionGame;

  /// No description provided for @settingsSectionPings.
  ///
  /// In en, this message translates to:
  /// **'Pings'**
  String get settingsSectionPings;

  /// No description provided for @settingsSectionSpeedhunt.
  ///
  /// In en, this message translates to:
  /// **'Speedhunt'**
  String get settingsSectionSpeedhunt;

  /// No description provided for @settingsSectionTeams.
  ///
  /// In en, this message translates to:
  /// **'Teams'**
  String get settingsSectionTeams;

  /// No description provided for @settingsDuration.
  ///
  /// In en, this message translates to:
  /// **'Game duration'**
  String get settingsDuration;

  /// No description provided for @settingsHeadStart.
  ///
  /// In en, this message translates to:
  /// **'Head start for players'**
  String get settingsHeadStart;

  /// No description provided for @settingsPingInterval.
  ///
  /// In en, this message translates to:
  /// **'Ping every'**
  String get settingsPingInterval;

  /// No description provided for @settingsSpeedhuntCount.
  ///
  /// In en, this message translates to:
  /// **'Speedhunts for hunters'**
  String get settingsSpeedhuntCount;

  /// No description provided for @settingsSpeedhuntPings.
  ///
  /// In en, this message translates to:
  /// **'Pings per speedhunt'**
  String get settingsSpeedhuntPings;

  /// No description provided for @settingsSpeedhuntInterval.
  ///
  /// In en, this message translates to:
  /// **'Time between speedhunt pings'**
  String get settingsSpeedhuntInterval;

  /// No description provided for @settingsSpeedhuntEarliest.
  ///
  /// In en, this message translates to:
  /// **'Speedhunts allowed after'**
  String get settingsSpeedhuntEarliest;

  /// No description provided for @settingsSpeedhuntEarliestHint.
  ///
  /// In en, this message translates to:
  /// **'Counted from the game start (including head start). Before that, hunters can\'t trigger a speedhunt.'**
  String get settingsSpeedhuntEarliestHint;

  /// No description provided for @settingsSpeedhuntFirstDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay until 1st ping'**
  String get settingsSpeedhuntFirstDelay;

  /// No description provided for @settingsSpeedhuntFirstDelayHint.
  ///
  /// In en, this message translates to:
  /// **'Time between triggering a speedhunt and its first ping.'**
  String get settingsSpeedhuntFirstDelayHint;

  /// No description provided for @settingsHunterCount.
  ///
  /// In en, this message translates to:
  /// **'Number of hunters'**
  String get settingsHunterCount;

  /// No description provided for @settingsJoker.
  ///
  /// In en, this message translates to:
  /// **'Joker: hunter positions'**
  String get settingsJoker;

  /// No description provided for @settingsJokerHint.
  ///
  /// In en, this message translates to:
  /// **'Each player may see where the hunters are once.'**
  String get settingsJokerHint;

  /// No description provided for @settingsPlayerJoker.
  ///
  /// In en, this message translates to:
  /// **'Joker: player positions'**
  String get settingsPlayerJoker;

  /// No description provided for @settingsPlayerJokerHint.
  ///
  /// In en, this message translates to:
  /// **'Each player may see where all other players are once.'**
  String get settingsPlayerJokerHint;

  /// No description provided for @settingsArea.
  ///
  /// In en, this message translates to:
  /// **'Play area'**
  String get settingsArea;

  /// No description provided for @settingsAreaMissing.
  ///
  /// In en, this message translates to:
  /// **'Not drawn yet'**
  String get settingsAreaMissing;

  /// No description provided for @areaTitle.
  ///
  /// In en, this message translates to:
  /// **'Draw play area'**
  String get areaTitle;

  /// No description provided for @areaHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to set corners. Drag to move, long-press to delete, „+“ inserts a corner.'**
  String get areaHint;

  /// No description provided for @areaStats.
  ///
  /// In en, this message translates to:
  /// **'{points} corners · ≈ {area} km² · {width} × {height} km'**
  String areaStats(int points, String area, String width, String height);

  /// No description provided for @areaNeedPoints.
  ///
  /// In en, this message translates to:
  /// **'Set at least 3 corners'**
  String get areaNeedPoints;

  /// No description provided for @areaCrossing.
  ///
  /// In en, this message translates to:
  /// **'The edges cross – please fix the shape'**
  String get areaCrossing;

  /// No description provided for @areaUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get areaUndo;

  /// No description provided for @areaClear.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get areaClear;

  /// No description provided for @areaMyLocation.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get areaMyLocation;

  /// No description provided for @areaLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Location not available – check permission and GPS'**
  String get areaLocationUnavailable;

  /// No description provided for @areaSave.
  ///
  /// In en, this message translates to:
  /// **'Use as play area'**
  String get areaSave;

  /// No description provided for @areaDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw play area'**
  String get areaDraw;

  /// No description provided for @areaEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit play area'**
  String get areaEdit;

  /// No description provided for @settingsAreaPoints.
  ///
  /// In en, this message translates to:
  /// **'{count} corners'**
  String settingsAreaPoints(int count);

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutes(int count);

  /// No description provided for @hoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String hoursMinutes(int hours, int minutes);

  /// No description provided for @errorDurationTooShort.
  ///
  /// In en, this message translates to:
  /// **'The game needs a duration'**
  String get errorDurationTooShort;

  /// No description provided for @errorHeadStartInvalid.
  ///
  /// In en, this message translates to:
  /// **'Head start must be shorter than the game'**
  String get errorHeadStartInvalid;

  /// No description provided for @errorPingIntervalTooShort.
  ///
  /// In en, this message translates to:
  /// **'Ping interval is too short'**
  String get errorPingIntervalTooShort;

  /// No description provided for @errorSpeedhuntInvalid.
  ///
  /// In en, this message translates to:
  /// **'Check the speedhunt settings'**
  String get errorSpeedhuntInvalid;

  /// No description provided for @errorHunterCountInvalid.
  ///
  /// In en, this message translates to:
  /// **'At least one hunter is needed'**
  String get errorHunterCountInvalid;

  /// No description provided for @errorNotEnoughPlayers.
  ///
  /// In en, this message translates to:
  /// **'At least one player is needed'**
  String get errorNotEnoughPlayers;

  /// No description provided for @errorAreaMissing.
  ///
  /// In en, this message translates to:
  /// **'Draw the play area first'**
  String get errorAreaMissing;

  /// No description provided for @errorUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Everyone needs a role'**
  String get errorUnassigned;

  /// No description provided for @lobbyTitle.
  ///
  /// In en, this message translates to:
  /// **'Lobby'**
  String get lobbyTitle;

  /// No description provided for @lobbyCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Group code'**
  String get lobbyCodeLabel;

  /// No description provided for @lobbyCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get lobbyCodeCopied;

  /// No description provided for @lobbyShareHint.
  ///
  /// In en, this message translates to:
  /// **'Friends join with this code.'**
  String get lobbyShareHint;

  /// No description provided for @lobbyParticipants.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 participant} other{{count} participants}}'**
  String lobbyParticipants(int count);

  /// No description provided for @lobbyAssignRandom.
  ///
  /// In en, this message translates to:
  /// **'Random teams'**
  String get lobbyAssignRandom;

  /// No description provided for @lobbyTapToSwitch.
  ///
  /// In en, this message translates to:
  /// **'Tap a person to switch hunter ↔ player.'**
  String get lobbyTapToSwitch;

  /// No description provided for @lobbyStart.
  ///
  /// In en, this message translates to:
  /// **'Start game'**
  String get lobbyStart;

  /// No description provided for @lobbyWaitingForAdmin.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the host to start…'**
  String get lobbyWaitingForAdmin;

  /// No description provided for @lobbyAdminBadge.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get lobbyAdminBadge;

  /// No description provided for @lobbyYouBadge.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get lobbyYouBadge;

  /// No description provided for @lobbyRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String lobbyRemoveMember(String name);

  /// No description provided for @lobbyRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get lobbyRemove;

  /// No description provided for @removeMemberText.
  ///
  /// In en, this message translates to:
  /// **'They will be removed from the group. With the code they can join again.'**
  String get removeMemberText;

  /// No description provided for @removedTitle.
  ///
  /// In en, this message translates to:
  /// **'You were removed from the group by the host.'**
  String get removedTitle;

  /// No description provided for @lobbyLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get lobbyLeave;

  /// No description provided for @lobbyDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get lobbyDelete;

  /// No description provided for @lobbyDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the group for everyone? This cannot be undone.'**
  String get lobbyDeleteConfirm;

  /// No description provided for @lobbyGroupGone.
  ///
  /// In en, this message translates to:
  /// **'This group no longer exists.'**
  String get lobbyGroupGone;

  /// No description provided for @lobbyBackHome.
  ///
  /// In en, this message translates to:
  /// **'Back to my groups'**
  String get lobbyBackHome;

  /// No description provided for @gamePhaseStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get gamePhaseStarting;

  /// No description provided for @gamePhaseHeadStart.
  ///
  /// In en, this message translates to:
  /// **'Head start'**
  String get gamePhaseHeadStart;

  /// No description provided for @gamePhaseHunting.
  ///
  /// In en, this message translates to:
  /// **'Hunt is on'**
  String get gamePhaseHunting;

  /// No description provided for @gamePhaseTimeUp.
  ///
  /// In en, this message translates to:
  /// **'Time is up'**
  String get gamePhaseTimeUp;

  /// No description provided for @gameTimeUpHint.
  ///
  /// In en, this message translates to:
  /// **'The round keeps running so you can look at the locations together. The host ends it.'**
  String get gameTimeUpHint;

  /// No description provided for @gameEndButton.
  ///
  /// In en, this message translates to:
  /// **'End game'**
  String get gameEndButton;

  /// No description provided for @gameEndConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'End game?'**
  String get gameEndConfirmTitle;

  /// No description provided for @gameEndConfirmText.
  ///
  /// In en, this message translates to:
  /// **'For privacy, all sensitive data of this round – especially all locations – will now be deleted permanently for everyone. The group stays and you can start a new round.'**
  String get gameEndConfirmText;

  /// No description provided for @gameEndConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'End and delete'**
  String get gameEndConfirmAction;

  /// No description provided for @gameAbortTitle.
  ///
  /// In en, this message translates to:
  /// **'Abort the game early?'**
  String get gameAbortTitle;

  /// No description provided for @gameAbortText.
  ///
  /// In en, this message translates to:
  /// **'The game is still running ({remaining} left). Do you really want to abort it now?'**
  String gameAbortText(String remaining);

  /// No description provided for @gameAbortContinue.
  ///
  /// In en, this message translates to:
  /// **'Yes, abort'**
  String get gameAbortContinue;

  /// No description provided for @gameAbortFinalTitle.
  ///
  /// In en, this message translates to:
  /// **'Really abort?'**
  String get gameAbortFinalTitle;

  /// No description provided for @gameAbortFinalAction.
  ///
  /// In en, this message translates to:
  /// **'Abort for good'**
  String get gameAbortFinalAction;

  /// No description provided for @historyAborted.
  ///
  /// In en, this message translates to:
  /// **'aborted early'**
  String get historyAborted;

  /// No description provided for @gameNextPing.
  ///
  /// In en, this message translates to:
  /// **'Next ping in {time}'**
  String gameNextPing(String time);

  /// No description provided for @gameCaughtSelf.
  ///
  /// In en, this message translates to:
  /// **'You were caught – your location is no longer shared.'**
  String get gameCaughtSelf;

  /// No description provided for @gameSpeedhuntNext.
  ///
  /// In en, this message translates to:
  /// **'Speedhunt active · ping {number}/{total} in {time}'**
  String gameSpeedhuntNext(int number, int total, String time);

  /// No description provided for @gameYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get gameYou;

  /// No description provided for @gameNoPingsYet.
  ///
  /// In en, this message translates to:
  /// **'No pings yet'**
  String get gameNoPingsYet;

  /// No description provided for @trackingTitle.
  ///
  /// In en, this message translates to:
  /// **'Manhunt is running'**
  String get trackingTitle;

  /// No description provided for @trackingText.
  ///
  /// In en, this message translates to:
  /// **'Your location is shared with your group for the game.'**
  String get trackingText;

  /// No description provided for @trackingWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for GPS signal …'**
  String get trackingWaiting;

  /// No description provided for @trackingNoPermission.
  ///
  /// In en, this message translates to:
  /// **'No location access – please allow it in the settings (precise location), then retry.'**
  String get trackingNoPermission;

  /// No description provided for @trackingError.
  ///
  /// In en, this message translates to:
  /// **'GPS problem – restarting automatically …'**
  String get trackingError;

  /// No description provided for @speedhuntButton.
  ///
  /// In en, this message translates to:
  /// **'Speedhunt ({left})'**
  String speedhuntButton(int left);

  /// No description provided for @speedhuntTitle.
  ///
  /// In en, this message translates to:
  /// **'Start speedhunt'**
  String get speedhuntTitle;

  /// No description provided for @speedhuntWho.
  ///
  /// In en, this message translates to:
  /// **'On whom?'**
  String get speedhuntWho;

  /// No description provided for @speedhuntInfo.
  ///
  /// In en, this message translates to:
  /// **'{pings} locations, {minutes} min apart. Players only learn that a speedhunt is running – not on whom.'**
  String speedhuntInfo(int pings, int minutes);

  /// No description provided for @speedhuntInfoDelay.
  ///
  /// In en, this message translates to:
  /// **'The first location is sent {minutes} min after starting.'**
  String speedhuntInfoDelay(int minutes);

  /// No description provided for @speedhuntConfirm.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get speedhuntConfirm;

  /// No description provided for @speedhuntNotHunting.
  ///
  /// In en, this message translates to:
  /// **'Speedhunts are possible once the hunters are released.'**
  String get speedhuntNotHunting;

  /// No description provided for @speedhuntTooEarly.
  ///
  /// In en, this message translates to:
  /// **'The first speedhunt is possible {minutes} min after the start.'**
  String speedhuntTooEarly(int minutes);

  /// No description provided for @speedhuntNoneLeft.
  ///
  /// In en, this message translates to:
  /// **'No speedhunts left.'**
  String get speedhuntNoneLeft;

  /// No description provided for @speedhuntAlreadyRunning.
  ///
  /// In en, this message translates to:
  /// **'A speedhunt is already running.'**
  String get speedhuntAlreadyRunning;

  /// No description provided for @speedhuntInvalidTarget.
  ///
  /// In en, this message translates to:
  /// **'This player cannot be speedhunted.'**
  String get speedhuntInvalidTarget;

  /// No description provided for @jokerButton.
  ///
  /// In en, this message translates to:
  /// **'Joker'**
  String get jokerButton;

  /// No description provided for @jokerHuntersOption.
  ///
  /// In en, this message translates to:
  /// **'Hunter positions'**
  String get jokerHuntersOption;

  /// No description provided for @jokerHuntersHint.
  ///
  /// In en, this message translates to:
  /// **'See once where the hunters are right now'**
  String get jokerHuntersHint;

  /// No description provided for @jokerPlayersOption.
  ///
  /// In en, this message translates to:
  /// **'Player positions'**
  String get jokerPlayersOption;

  /// No description provided for @jokerPlayersHint.
  ///
  /// In en, this message translates to:
  /// **'See once where all other players are right now'**
  String get jokerPlayersHint;

  /// No description provided for @jokerAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'Already used'**
  String get jokerAlreadyUsed;

  /// No description provided for @jokerPlayersTitle.
  ///
  /// In en, this message translates to:
  /// **'Use player joker?'**
  String get jokerPlayersTitle;

  /// No description provided for @jokerPlayersText.
  ///
  /// In en, this message translates to:
  /// **'All other active players\' phones send you their current position once. Afterwards this joker is used up.'**
  String get jokerPlayersText;

  /// No description provided for @jokerTitle.
  ///
  /// In en, this message translates to:
  /// **'Use hunter joker?'**
  String get jokerTitle;

  /// No description provided for @jokerText.
  ///
  /// In en, this message translates to:
  /// **'You will see the hunters\' current positions once. Afterwards the joker is used up.'**
  String get jokerText;

  /// No description provided for @jokerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Use joker'**
  String get jokerConfirm;

  /// No description provided for @jokerNoHunters.
  ///
  /// In en, this message translates to:
  /// **'No hunter positions available right now.'**
  String get jokerNoHunters;

  /// No description provided for @noticeCaught.
  ///
  /// In en, this message translates to:
  /// **'{player} was caught'**
  String noticeCaught(String player);

  /// No description provided for @noticeSpeedhunt.
  ///
  /// In en, this message translates to:
  /// **'Speedhunt started!'**
  String get noticeSpeedhunt;

  /// No description provided for @noticeSpeedhuntBody.
  ///
  /// In en, this message translates to:
  /// **'A player will be located {pings}× every {minutes} min.'**
  String noticeSpeedhuntBody(int pings, int minutes);

  /// No description provided for @noticePingSent.
  ///
  /// In en, this message translates to:
  /// **'Your location was sent to the hunters'**
  String get noticePingSent;

  /// No description provided for @catchTitle.
  ///
  /// In en, this message translates to:
  /// **'Report catch'**
  String get catchTitle;

  /// No description provided for @catchWho.
  ///
  /// In en, this message translates to:
  /// **'Who was caught?'**
  String get catchWho;

  /// No description provided for @catchConfirm.
  ///
  /// In en, this message translates to:
  /// **'Report catch'**
  String get catchConfirm;

  /// No description provided for @catchSelfTitle.
  ///
  /// In en, this message translates to:
  /// **'I was caught'**
  String get catchSelfTitle;

  /// No description provided for @catchSelfText.
  ///
  /// In en, this message translates to:
  /// **'You will be marked as caught and everyone will be notified.'**
  String get catchSelfText;

  /// No description provided for @catchSelfConfirm.
  ///
  /// In en, this message translates to:
  /// **'Yes, caught'**
  String get catchSelfConfirm;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No finished rounds yet. After „End game“ each round appears here – without locations.'**
  String get historyEmpty;

  /// No description provided for @historyRound.
  ///
  /// In en, this message translates to:
  /// **'Round {number}'**
  String historyRound(int number);

  /// No description provided for @historyCatches.
  ///
  /// In en, this message translates to:
  /// **'Catches'**
  String get historyCatches;

  /// No description provided for @historyNoCatches.
  ///
  /// In en, this message translates to:
  /// **'Nobody was caught.'**
  String get historyNoCatches;

  /// No description provided for @historySurvivors.
  ///
  /// In en, this message translates to:
  /// **'Not caught'**
  String get historySurvivors;

  /// No description provided for @historyAllCaught.
  ///
  /// In en, this message translates to:
  /// **'All players caught!'**
  String get historyAllCaught;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
