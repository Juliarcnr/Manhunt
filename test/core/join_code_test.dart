import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/join_code.dart';

void main() {
  test('generated codes have format XXXXX-XXXXX (R-LOBBY-02)', () {
    final code = JoinCode.generate(random: Random(42));
    expect(code, matches(RegExp(r'^[2-9A-Z]{5}-[2-9A-Z]{5}$')));
    expect(JoinCode.normalize(code), code);
  });

  test('codes differ', () {
    final codes = {for (var i = 0; i < 100; i++) JoinCode.generate()};
    expect(codes, hasLength(100));
  });

  test('normalize tolerates case, spaces and missing dash', () {
    expect(JoinCode.normalize('abcde fghjk'), 'ABCDE-FGHJK');
    expect(JoinCode.normalize(' ABCDE-FGHJK '), 'ABCDE-FGHJK');
  });

  test('normalize rejects wrong length or ambiguous chars', () {
    expect(JoinCode.normalize('ABCD'), isNull);
    expect(JoinCode.normalize('ABCDE-FGHJ0'), isNull); // 0 not in alphabet
    expect(JoinCode.normalize('ABCDE-FGHJI'), isNull); // I not in alphabet
  });
}
