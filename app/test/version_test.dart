import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/platform/version.dart';

void main() {
  test('the version in the code matches the one in the pubspec', () {
    // A report stamped with the wrong version sends a maintainer to the wrong
    // commit. The string is a constant because a plugin for one line read only
    // by bug reports is not worth a dependency on every host, so this test is
    // what keeps it honest.
    final List<String> lines = File('pubspec.yaml').readAsLinesSync();
    final String declared = lines
        .firstWhere((String l) => l.startsWith('version:'))
        .substring('version:'.length)
        .trim();
    expect(appVersion, declared);
  });
}
