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

/// Language-neutral, so every phone recognises a bot and its kind from the
/// (encrypted) name alone – no extra field, no rules change (R-BOT-03).
String botName(BotKind kind, int number) =>
    '🤖 ${kind == BotKind.hunter ? 'Hunter' : 'Player'} $number';

final _botName = RegExp(r'^🤖 (Hunter|Player) (\d+)$');

BotKind? botKindOf(String name) => switch (_botName.firstMatch(name)?[1]) {
  'Hunter' => BotKind.hunter,
  'Player' => BotKind.player,
  _ => null,
};

int? _botNumber(String name) =>
    int.tryParse(_botName.firstMatch(name)?[2] ?? '');

bool isBot(Member m) => botKindOf(m.name) != null;

/// The phone that runs the bots of [kind]: the first human (by joining
/// order) with that role; null if there is none yet (R-BOT-03).
String? botCarrier(BotKind kind, List<Member> members) {
  for (final m in members) {
    if (!isBot(m) && m.role == kind.role) return m.id;
  }
  return null;
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
