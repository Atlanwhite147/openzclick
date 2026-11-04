/// The bytes of one Windows keyboard event.
///
/// `SendInput` takes a buffer it cannot check: pass it the wrong layout and it
/// returns zero forever, with an error code that names the wrong cause. The
/// layout is therefore built here, in plain Dart, where a test can assert every
/// offset without a Windows machine to run on.
///
/// Two rules of that layout are easy to get wrong and expensive to debug:
///
///  * the size is `sizeof(INPUT)` — 40 bytes on x64 — and not
///    `sizeof(KEYBDINPUT)`, which is 24;
///  * `dwExtraInfo` sits at offset 24 (8 for the start of the union, plus 16
///    inside `KEYBDINPUT` once the pointer is aligned), not at 20.
library;

import 'dart:typed_data';

/// `sizeof(INPUT)` on a 64-bit Windows build.
const int windowsInputSize = 40;

/// `INPUT_KEYBOARD`.
const int _inputKeyboard = 1;

/// `KEYEVENTF_KEYUP`.
const int _keyUp = 0x0002;

/// Offset of the `KEYBDINPUT` union inside `INPUT`.
const int windowsUnionOffset = 8;

/// Builds one keyboard event for [virtualKey].
///
/// [up] selects the release. A press and a release are two separate events on
/// purpose: an application that polls the key state sees nothing if both arrive
/// in the same call.
Uint8List keyEventBytes(int virtualKey, {required bool up}) {
  final Uint8List bytes = Uint8List(windowsInputSize);
  final ByteData view = ByteData.sublistView(bytes);
  view.setUint32(0, _inputKeyboard, Endian.little);
  view.setUint16(windowsUnionOffset, virtualKey, Endian.little);
  view.setUint16(windowsUnionOffset + 2, 0, Endian.little); // wScan
  view.setUint32(windowsUnionOffset + 4, up ? _keyUp : 0, Endian.little);
  view.setUint32(windowsUnionOffset + 8, 0, Endian.little); // time
  view.setUint64(windowsUnionOffset + 16, 0, Endian.little); // dwExtraInfo
  return bytes;
}
