import '../models/game_settings.dart';
import '../models/member.dart';

/// Computer members for testing with few phones (R-BOT-01 … R-BOT-06). They
/// all run on the host's phone and walk around it (R-BOT-03, R-BOT-04).
///
/// Upper limit of the setting (R-BOT-02).
const maxBots = 8;

/// Rare, gloriously ugly names, so every phone recognises a bot from its
/// (encrypted) name alone: no extra field, no rules change (R-BOT-03). At
/// least [maxBots]; older app versions used them for hunters and players
/// separately, so all of them still count as bots.
const _botNames = [
  'Adelgunde',
  'Stromius',
  'Pankratius',
  'Knorbert',
  'Notburga',
  'Kunibald',
  'Ulfbert',
  'Rumpold',
  'Mechthildis',
  'Hadubrand',
  'Waltrudis',
  'Gisbrecht',
  'Hildebold',
  'Wulfhart',
  'Radegundis',
  'Ottokar',
];

const _botPrefix = '🤖 ';

/// The [number]th name (from 1).
String botName(int number) => '$_botPrefix${_botNames[number - 1]}';

int? _botNumber(String name) {
  if (!name.startsWith(_botPrefix)) return null;
  final i = _botNames.indexOf(name.substring(_botPrefix.length));
  return i < 0 ? null : i + 1;
}

bool isBot(Member m) => _botNumber(m.name) != null;

/// What one phone has to do in the lobby so the bots match the settings.
class BotActions {
  const BotActions({this.create = const [], this.remove = const []});

  /// Names of new bots to join from this phone; they join unassigned like
  /// any newcomer (R-BOT-03, R-LOBBY-11).
  final List<String> create;

  /// Ids of this phone's bots to leave the group.
  final List<String> remove;

  bool get isEmpty => create.isEmpty && remove.isEmpty;
}

/// [members] in joining order; [myBotIds] are the bots run by this phone.
/// Only the host's phone carries bots (R-BOT-03); any other phone removes
/// its own (e.g. from an older app version). Roles are never touched: the
/// host assigns bots like people (R-LOBBY-04, R-LOBBY-05).
BotActions botActions({
  required GameSettings settings,
  required List<Member> members,
  required Set<String> myBotIds,
  required bool isHost,
}) {
  final mine = [
    for (final m in members)
      if (myBotIds.contains(m.id)) m,
  ];
  final wanted = isHost ? settings.botCount : 0;
  // The newest go first.
  final remove = mine.length > wanted
      ? [for (final m in mine.skip(wanted)) m.id]
      : <String>[];
  final used = {for (final m in members) _botNumber(m.name)};
  final create = <String>[];
  var number = 1;
  for (var i = mine.length; i < wanted && number <= _botNames.length; i++) {
    while (number <= _botNames.length && used.contains(number)) {
      number++;
    }
    if (number > _botNames.length) break;
    used.add(number);
    create.add(botName(number));
  }
  return BotActions(create: create, remove: remove);
}
