import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/bots/bot_walk.dart';
import 'package:manhunt/core/models/geo_point.dart';
import 'package:manhunt/core/round/ping_schedule.dart';
import 'package:manhunt/data/bot_location_service.dart';
import 'package:manhunt/data/location_service.dart';

import '../core/bots_test.dart' show metres;

void main() {
  group('simulated GPS of a computer member (R-BOT-04)', () {
    final now = DateTime.utc(2026, 10, 26, 12);
    LocationFix? anchor;
    LocationFix fix(GeoPoint p) => LocationFix(point: p, at: now);
    const a = GeoPoint(52.52, 13.405);
    const b = GeoPoint(48.137, 11.575);

    BotLocationService service() => BotLocationService(
      anchor: () => anchor,
      random: Random(1),
      interval: const Duration(milliseconds: 5),
      now: () => now,
    );

    setUp(() => anchor = null);

    test('no carrier position yet → no position', () async {
      expect(await service().currentFix(), isNull);
      expect(await service().ensurePermission(), isTrue);
    });

    test('positions near the carrier, following it', () async {
      final s = service();
      anchor = fix(a);
      final first = (await s.currentFix())!;
      expect(metres(a, first.point), lessThanOrEqualTo(botRadiusM + 0.5));
      expect(first.at, now);
      anchor = fix(b);
      expect(
        metres(b, (await s.currentFix())!.point),
        lessThanOrEqualTo(botRadiusM + 0.5),
      );
    });

    test('keeps the last carrier position when it is gone', () async {
      final s = service();
      anchor = fix(a);
      await s.currentFix();
      anchor = null;
      final kept = await s.currentFix();
      expect(metres(a, kept!.point), lessThanOrEqualTo(botRadiusM + 0.5));
    });

    test('tracking delivers walking positions until cancelled', () async {
      anchor = fix(a);
      final fixes = await service()
          .track(const TrackingNotice(title: 't', text: 'x'))
          .take(5)
          .toList();
      expect(fixes, hasLength(5));
      expect({for (final f in fixes) f.point}.length, greaterThan(1));
      for (final f in fixes) {
        expect(metres(a, f.point), lessThanOrEqualTo(botRadiusM + 0.5));
      }
    });
  });
}
