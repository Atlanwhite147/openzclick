import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/net/windows_key_event.dart';

void main() {
  group('the Windows keyboard event layout', () {
    test('is sizeof(INPUT), not sizeof(KEYBDINPUT)', () {
      // Passing 24 makes every SendInput call fail with a parameter error that
      // names none of it. This is the single most expensive mistake in the file.
      expect(windowsInputSize, 40);
      expect(keyEventBytes(0x49, up: false).length, 40);
    });

    test('declares a keyboard event, not a mouse one', () {
      final ByteData view = ByteData.sublistView(
        keyEventBytes(0x49, up: false),
      );
      expect(view.getUint32(0, Endian.little), 1);
    });

    test('carries the virtual key and the scan code in the union', () {
      final ByteData view = ByteData.sublistView(
        keyEventBytes(0x25, up: false),
      );
      expect(view.getUint16(windowsUnionOffset, Endian.little), 0x25);
      expect(view.getUint16(windowsUnionOffset + 2, Endian.little), 0);
    });

    test('a press and a release differ only by the key-up flag', () {
      // Two separate events on purpose: an application that polls the key state
      // sees nothing if both arrive in one call.
      final ByteData down = ByteData.sublistView(
        keyEventBytes(0x49, up: false),
      );
      final ByteData up = ByteData.sublistView(keyEventBytes(0x49, up: true));
      expect(down.getUint32(windowsUnionOffset + 4, Endian.little), 0);
      expect(up.getUint32(windowsUnionOffset + 4, Endian.little), 0x0002);
      expect(
        down.getUint16(windowsUnionOffset, Endian.little),
        up.getUint16(windowsUnionOffset, Endian.little),
      );
    });

    test('leaves the timestamp and dwExtraInfo to the system', () {
      // dwExtraInfo sits at 24 once the pointer is 8-aligned, not at 20: writing
      // it at 20 would corrupt the timestamp instead.
      final ByteData view = ByteData.sublistView(
        keyEventBytes(0x49, up: false),
      );
      expect(view.getUint32(windowsUnionOffset + 8, Endian.little), 0);
      expect(view.getUint64(windowsUnionOffset + 16, Endian.little), 0);
    });

    test('has nothing set outside the keyboard fields', () {
      // Anything left over would be read as part of MOUSEINPUT by a host that
      // trusts cbSize more than the type.
      final Uint8List bytes = keyEventBytes(0x49, up: false);
      expect(bytes.sublist(4, 8), everyElement(0)); // padding before the union
      expect(bytes.sublist(20, 24), everyElement(0)); // padding for the pointer
      expect(bytes.sublist(32, 40), everyElement(0)); // tail of the union
    });
  });
}
