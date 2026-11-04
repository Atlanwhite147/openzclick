import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/net/windows_keys.dart';

void main() {
  group('a key binding becomes the code Windows expects', () {
    test('the default bindings work', () {
      // These four are what the application injects by default: the two shifts
      // and the two directions.
      expect(virtualKeyFor('i'), 0x49);
      expect(virtualKeyFor('k'), 0x4B);
      expect(virtualKeyFor('Left'), 0x25);
      expect(virtualKeyFor('Right'), 0x27);
    });

    test('letters are case-insensitive, digits too', () {
      expect(virtualKeyFor('A'), 0x41);
      expect(virtualKeyFor('z'), 0x5A);
      expect(virtualKeyFor('0'), 0x30);
      expect(virtualKeyFor('9'), 0x39);
    });

    test('the X11 names already used by the bindings are understood', () {
      // The bindings come from X11 keysym names, so `Page_Up` and `BackSpace`
      // are what a rider's configuration actually holds.
      expect(virtualKeyFor('Page_Up'), 0x21);
      expect(virtualKeyFor('Page_Down'), 0x22);
      expect(virtualKeyFor('BackSpace'), 0x08);
      expect(virtualKeyFor('Return'), 0x0D);
      expect(virtualKeyFor('space'), 0x20);
      expect(virtualKeyFor('Up'), 0x26);
      expect(virtualKeyFor('Down'), 0x28);
    });

    test('function keys are accepted in either spelling', () {
      expect(virtualKeyFor('F1'), 0x70);
      expect(virtualKeyFor('f1'), 0x70);
      expect(virtualKeyFor('F12'), 0x7B);
      expect(virtualKeyFor('F13'), isNull);
    });

    test('a stray space does not make a binding unknown', () {
      expect(virtualKeyFor('  i  '), 0x49);
    });

    test('an unknown name is refused, never guessed', () {
      // A wrong virtual-key code presses a key nobody asked for, and the rider
      // would watch a training application change gear by itself. Silence with a
      // reason beats a plausible-looking guess.
      expect(virtualKeyFor('Hyper_R'), isNull);
      expect(virtualKeyFor(''), isNull);
      expect(virtualKeyFor('  '), isNull);
      expect(virtualKeyFor('PageUp'), isNull);
    });
  });
}
