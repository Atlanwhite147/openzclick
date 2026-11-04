/// Keyboard and pointer injection on Windows, through `SendInput`.
///
/// The Linux backend uses `uinput`-style XTest, which the system treats as a
/// real device. `SendInput` is a different category: it places events in the
/// session's input queue and hopes the target application listens at that layer.
/// Some do not — Raw Input, DirectInput and exclusive fullscreen read the device
/// instead — and nothing here can detect that. What this file *can* do is fail
/// honestly when the call itself fails, instead of reporting a gear change
/// nobody saw.
///
/// Three details decide whether it works at all, and each one is a known way to
/// lose an afternoon:
///
///  * `cbSize` is `sizeof(INPUT)` — 40 bytes on x64 — and **not**
///    `sizeof(KEYBDINPUT)`, which is 24. Passing the smaller size makes every
///    call fail with `ERROR_INVALID_PARAMETER`.
///  * every press needs its own release in a separate call: applications that
///    poll the key state never see a down and an up delivered together.
///  * `SendInput` returns how many events it inserted. Zero means nothing
///    happened, and `GetLastError` will not tell you that UIPI blocked a
///    higher-integrity window. A zero return is reported as a failure here.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:openzclick_core/openzclick_core.dart';

import 'windows_key_event.dart';
import 'windows_keys.dart';

// Mouse flags used by `tapAt`.
const int _leftDown = 0x0002;
const int _leftUp = 0x0004;

typedef _SendInputNative = Uint32 Function(Uint32, Pointer<Uint8>, Int32);
typedef _SendInputDart = int Function(int, Pointer<Uint8>, int);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

typedef _SetCursorPosNative = Int32 Function(Int32, Int32);
typedef _SetCursorPosDart = int Function(int, int);

typedef _MouseEventNative = Void Function(
  Uint32,
  Int32,
  Int32,
  Uint32,
  UintPtr,
);
typedef _MouseEventDart = void Function(int, int, int, int, int);

/// Keyboard and pointer injection through `SendInput`.
class WindowsInjection implements KeyInjector {
  DynamicLibrary? _user32;
  DynamicLibrary? _kernel32;
  bool _bound = false;
  bool _failed = false;

  late final _SendInputDart _sendInput;
  late final _GetLastErrorDart _lastError;
  late final _SetCursorPosDart _setCursorPos;
  late final _MouseEventDart _mouseEvent;

  /// True when `user32.dll` could be loaded, which is the only test that means
  /// anything before the first press.
  bool get available => _bind();

  bool _bind() {
    if (_bound) return true;
    if (_failed) return false;
    try {
      _user32 = DynamicLibrary.open('user32.dll');
      _kernel32 = DynamicLibrary.open('kernel32.dll');
      _sendInput = _user32!.lookupFunction<_SendInputNative, _SendInputDart>(
        'SendInput',
      );
      _lastError = _kernel32!
          .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
            'GetLastError',
          );
      _setCursorPos = _user32!
          .lookupFunction<_SetCursorPosNative, _SetCursorPosDart>(
            'SetCursorPos',
          );
      _mouseEvent = _user32!.lookupFunction<_MouseEventNative, _MouseEventDart>(
        'mouse_event',
      );
      _bound = true;
      return true;
    } catch (_) {
      _failed = true;
      return false;
    }
  }

  @override
  Future<void> pressKey(String key) async {
    if (!_bind()) {
      throw StateError(
        'user32.dll could not be loaded: injection is unavailable',
      );
    }
    final int? code = virtualKeyFor(key);
    if (code == null) {
      throw ArgumentError.value(key, 'key', 'unknown Windows virtual key');
    }

    // Down and up in two separate calls, with a gap: an application that polls
    // the key state sees nothing if both arrive in the same buffer.
    _send(code, up: false);
    await Future<void>.delayed(const Duration(milliseconds: 12));
    _send(code, up: true);
  }

  @override
  Future<void> tapAt(double x, double y) async {
    if (!_bind()) {
      throw StateError(
        'user32.dll could not be loaded: injection is unavailable',
      );
    }
    // Fractions of the screen are the contract; Windows takes absolute pixels.
    final int px = (x.clamp(0.0, 1.0) * 65535).round();
    final int py = (y.clamp(0.0, 1.0) * 65535).round();
    _setCursorPos(px, py);
    _mouseEvent(_leftDown, 0, 0, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 12));
    _mouseEvent(_leftUp, 0, 0, 0, 0);
  }

  /// Sends one keyboard event, and refuses a silent failure.
  void _send(int virtualKey, {required bool up}) {
    final Uint8List bytes = keyEventBytes(virtualKey, up: up);
    final Pointer<Uint8> buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final int inserted = _sendInput(1, buffer, bytes.length);
      if (inserted != 1) {
        // Zero events inserted is not a slow system: it is a refusal, most often
        // UIPI declining to inject into a window of higher integrity. Reporting
        // it as a shift that happened is the one outcome to avoid.
        throw StateError(
          'SendInput inserted $inserted of 1 events '
          '(error ${_lastError()}); the target window may be more privileged '
          'than this application',
        );
      }
    } finally {
      calloc.free(buffer);
    }
  }
}
