import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/models/member.dart';
import 'package:manhunt/core/round/observer.dart';
import 'package:manhunt/core/schedule/game_clock.dart';

void main() {
  const gm = Member(id: 'g', name: 'G', role: Role.gameMaster);
  const hunter = Member(id: 'h', name: 'H', role: Role.hunter);
  const player = Member(id: 'p', name: 'P', role: Role.player);
  final caught = player.copyWith(caught: true);

  group('seesEveryoneLive (R-GM-03, R-GM-07, R-GM-09)', () {
    test('game master while the round runs', () {
      for (final phase in [GamePhase.headStart, GamePhase.hunting]) {
        expect(seesEveryoneLive(gm, phase, accepted: false), isTrue);
      }
      expect(
        seesEveryoneLive(gm, GamePhase.notStarted, accepted: false),
        isFalse,
      );
      expect(seesEveryoneLive(gm, GamePhase.ended, accepted: false), isFalse);
    });

    test('caught player only after accepting', () {
      expect(
        seesEveryoneLive(caught, GamePhase.hunting, accepted: false),
        isFalse,
      );
      expect(
        seesEveryoneLive(caught, GamePhase.hunting, accepted: true),
        isTrue,
      );
      expect(
        seesEveryoneLive(caught, GamePhase.ended, accepted: true),
        isFalse,
      );
    });

    test('never hunters or players still in the game', () {
      expect(
        seesEveryoneLive(hunter, GamePhase.hunting, accepted: true),
        isFalse,
      );
      expect(
        seesEveryoneLive(player, GamePhase.hunting, accepted: true),
        isFalse,
      );
      expect(
        seesEveryoneLive(null, GamePhase.hunting, accepted: true),
        isFalse,
      );
    });
  });

  group('mustAcceptLiveView (R-GM-08)', () {
    test('caught player during the round until accepted', () {
      expect(
        mustAcceptLiveView(caught, GamePhase.hunting, accepted: false),
        isTrue,
      );
      expect(
        mustAcceptLiveView(caught, GamePhase.hunting, accepted: true),
        isFalse,
      );
      expect(
        mustAcceptLiveView(caught, GamePhase.ended, accepted: false),
        isFalse,
      );
      expect(
        mustAcceptLiveView(player, GamePhase.hunting, accepted: false),
        isFalse,
      );
      expect(
        mustAcceptLiveView(gm, GamePhase.hunting, accepted: false),
        isFalse,
      );
    });
  });

  group('hasLiveAudience (R-GM-05)', () {
    test('game master or caught player', () {
      expect(hasLiveAudience([hunter, player]), isFalse);
      expect(hasLiveAudience([hunter, player, gm]), isTrue);
      expect(hasLiveAudience([hunter, player, caught]), isTrue);
    });
  });
}
