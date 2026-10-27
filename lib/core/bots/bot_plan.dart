import '../models/game_settings.dart';
import '../models/member.dart';

/// Computer members for testing with few phones (R-BOT-01 … R-BOT-06). Each
/// one runs on the phone of a human of its role (its "carrier") and walks
/// around that phone.
enum BotKind {
  hunter,
  player;

  Role get role => this == hunter ? Role.hunter : Role.player;

  int wanted(GameSettings settings) =>
      this == hunter ? settings.botHunters : settings.botPlayers;
}

/// Upper limit of each setting (R-BOT-02).
const maxBotsPerKind = 4;

/// Rare, gloriously ugly names – one list per kind, so every phone recognises
/// a bot and its kind from the (encrypted) name alone: no extra field, no
/// rules change (R-BOT-03). At least [maxBotsPerKind] each.
const _botNames = {
  BotKind.hunter: [
    'Stromius',
    'Knorbert',
    'Kunibald',
    'Rumpold',
    'Hadubrand',
    'Gisbrecht',
    'Wulfhart',
    'Ottokar',
  ],
  BotKind.player: [
    'Adelgunde',
    'Pankratius',
    'Notburga',
    'Ulfbert',
    'Mechthildis',
    'Waltrudis',
    'Hildebold',
    'Radegundis',
  ],
};

const _botPrefix = '🤖 ';

/// The [number]th name (from 1) of [kind].
String botName(BotKind kind, int number) =>
    '$_botPrefix${_botNames[kind]![number - 1]}';

BotKind? botKindOf(String name) => _botNumberOf(name)?.kind;

int? _botNumber(String name) => _botNumberOf(name)?.number;

({BotKind kind, int number})? _botNumberOf(String name) {
  if (!name.startsWith(_botPrefix)) return null;
  final bare = name.substring(_botPrefix.length);
  for (final MapEntry(key: kind, value: names) in _botNames.entries) {
    final i = names.indexOf(bare);
    if (i >= 0) return (kind: kind, number: i + 1);
  }
  return null;
}

bool isBot(Member m) => botKindOf(m.name) != null;

/// The phone that runs the bots of [kind]: the first human (by joining
/// order) with that role, otherwise the first human at all – so the bots are
/// there right away, also with a single phone; null only without any human
/// (R-BOT-03).
String? botCarrier(BotKind kind, List<Member> members) {
  String? first;
  for (final m in members) {
    if (isBot(m)) continue;
    if (m.role == kind.role) return m.id;
    first ??= m.id;
  }
  return first;
}

/// What one phone has to do in the lobby so the bots match the settings.
class BotActions {
  const BotActions({
    this.create = const [],
    this.remove = const [],
    this.assign = const [],
  });

  /// New bots to join from this phone.
  final List<({BotKind kind, String name})> create;

  /// Ids of this phone's bots to leave the group.
  final List<String> remove;

  /// Host only: bots with their correct role.
  final List<Member> assign;

  bool get isEmpty => create.isEmpty && remove.isEmpty && assign.isEmpty;
}

/// [members] in joining order; [myBotIds] are the bots run by this phone.
BotActions botActions({
  required GameSettings settings,
  required List<Member> members,
  required String myId,
  required Set<String> myBotIds,
  required bool isHost,
}) {
  final create = <({BotKind kind, String name})>[];
  final remove = <String>[];
  for (final kind in BotKind.values) {
    final mine = [
      for (final m in members)
        if (myBotIds.contains(m.id) && botKindOf(m.name) == kind) m,
    ];
    final wanted = botCarrier(kind, members) == myId
        ? kind.wanted(settings)
        : 0;
    if (mine.length > wanted) {
      remove.addAll(mine.skip(wanted).map((m) => m.id));
    }
    final used = {
      for (final m in members)
        if (botKindOf(m.name) == kind) _botNumber(m.name),
    };
    var number = 1;
    for (var i = mine.length; i < wanted; i++) {
      while (used.contains(number)) {
        number++;
      }
      used.add(number);
      create.add((kind: kind, name: botName(kind, number)));
    }
  }
  return BotActions(
    create: create,
    remove: remove,
    assign: [
      if (isHost)
        for (final m in members)
          if (botKindOf(m.name) case final kind?)
            if (m.role != kind.role && !remove.contains(m.id))
              m.copyWith(role: kind.role),
    ],
  );
}
