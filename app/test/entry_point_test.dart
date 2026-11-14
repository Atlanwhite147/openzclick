import 'package:flutter_test/flutter_test.dart';

// Imported as a library, so `main` has to exist for this file to compile at all.
import 'package:openzclick/main.dart' as entry;

void main() {
  test('the application has an entry point', () {
    // Every platform build starts from `main()`. Tests import the root widget
    // instead and never call it, so a refactor can delete the entry point and
    // leave the suite green: that is exactly what happened when `main.dart` was
    // split, and it took a Windows release build to notice — MSBuild reported
    // "custom build exited with code 1" without naming the cause.
    expect(entry.main, isNotNull);
  });
}
