// Increments the build number in pubspec.yaml (`version: 0.1.0+1` -> `0.1.0+2`).
// The version name stays unchanged. Run from the project root:
//   dart run tool/bump_build.dart
import 'dart:io';

final _versionLine = RegExp(
  r'^version:[ \t]*(\S+)\+(\d+)[ \t]*(?=\r?$)',
  multiLine: true,
);

/// Returns [pubspec] with the build number after `+` incremented by one.
/// Throws [FormatException] if there is no `version: x.y.z+n` line.
String bumpBuildNumber(String pubspec) {
  final match = _versionLine.firstMatch(pubspec);
  if (match == null) {
    throw const FormatException('No "version: x.y.z+n" line in pubspec.yaml');
  }
  final next = int.parse(match.group(2)!) + 1;
  return pubspec.replaceRange(
    match.start,
    match.end,
    'version: ${match.group(1)}+$next',
  );
}

void main() {
  final file = File('pubspec.yaml');
  final updated = bumpBuildNumber(file.readAsStringSync());
  file.writeAsStringSync(updated);
  stdout.writeln(_versionLine.firstMatch(updated)!.group(0));
}
