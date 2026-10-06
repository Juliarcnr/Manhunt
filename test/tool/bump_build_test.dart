import 'package:flutter_test/flutter_test.dart';

import '../../tool/bump_build.dart';

void main() {
  group('bumpBuildNumber (R-DEV-04)', () {
    test('increments only the build number', () {
      expect(
        bumpBuildNumber('name: manhunt\nversion: 0.1.0+1\n\nenvironment:\n'),
        'name: manhunt\nversion: 0.1.0+2\n\nenvironment:\n',
      );
    });

    test('handles multi-digit build numbers', () {
      expect(bumpBuildNumber('version: 0.1.0+99\n'), 'version: 0.1.0+100\n');
    });

    test('ignores indented version keys of dependencies', () {
      const pubspec = 'deps:\n  version: 1.0.0+5\nversion: 0.1.0+3\n';
      expect(
        bumpBuildNumber(pubspec),
        'deps:\n  version: 1.0.0+5\nversion: 0.1.0+4\n',
      );
    });

    test('keeps Windows line endings', () {
      expect(
        bumpBuildNumber('version: 0.1.0+7\r\n\r\nname: x\r\n'),
        'version: 0.1.0+8\r\n\r\nname: x\r\n',
      );
    });

    test('throws without a build number', () {
      expect(() => bumpBuildNumber('version: 0.1.0\n'), throwsFormatException);
    });
  });
}
