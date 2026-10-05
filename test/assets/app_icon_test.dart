import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Reads width, height and color type from a PNG's IHDR chunk.
({int width, int height, int colorType}) _pngHeader(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  expect(bytes.sublist(1, 4), 'PNG'.codeUnits, reason: '$path is no PNG');
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
    colorType: bytes[25],
  );
}

const _rgb = 2;
const _rgba = 6;

void main() {
  group('app icon (R-UI-04)', () {
    test('source images are 1024x1024', () {
      for (final name in [
        'app_icon',
        'app_icon_foreground',
        'app_icon_background',
        'app_icon_monochrome',
      ]) {
        expect(File('assets/icon/$name.svg').existsSync(), isTrue);
        final png = _pngHeader('assets/icon/$name.png');
        expect((png.width, png.height), (1024, 1024), reason: name);
      }
    });

    test('adaptive foreground and monochrome are transparent', () {
      for (final name in ['app_icon_foreground', 'app_icon_monochrome']) {
        expect(_pngHeader('assets/icon/$name.png').colorType, _rgba);
      }
    });

    test('iOS marketing icon has no alpha channel (App Store requirement)', () {
      final png = _pngHeader(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
      );
      expect((png.width, png.height), (1024, 1024));
      expect(png.colorType, _rgb);
    });

    test('Android uses an adaptive icon with monochrome layer', () {
      final xml = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(xml, contains('ic_launcher_foreground'));
      expect(xml, contains('ic_launcher_background'));
      expect(xml, contains('ic_launcher_monochrome'));
    });
  });
}
