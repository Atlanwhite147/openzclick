/// Keyboard and pointer injection on Linux, through X11 and the XTest
/// extension.
///
/// This is the reference implementation of the desktop port: the same
/// [KeyInjector] contract is what Windows and macOS need, and contributing one
/// is a self-contained job (see CONTRIBUTING.md).
///
/// The library is loaded at runtime, so the application starts on a machine
/// without X11 and simply reports that injection is unavailable.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// C function signatures of libX11 and libXtst.
typedef _OpenDisplayNative = Pointer<Void> Function(Pointer<Utf8>);
typedef _OpenDisplayDart = Pointer<Void> Function(Pointer<Utf8>);

typedef _CloseDisplayNative = Int32 Function(Pointer<Void>);
typedef _CloseDisplayDart = int Function(Pointer<Void>);

typedef _StringToKeysymNative = Uint64 Function(Pointer<Utf8>);
typedef _StringToKeysymDart = int Function(Pointer<Utf8>);

typedef _KeysymToKeycodeNative = Uint8 Function(Pointer<Void>, Uint64);
typedef _KeysymToKeycodeDart = int Function(Pointer<Void>, int);

typedef _FlushNative = Int32 Function(Pointer<Void>);
typedef _FlushDart = int Function(Pointer<Void>);

typedef _DefaultScreenNative = Int32 Function(Pointer<Void>);
typedef _DefaultScreenDart = int Function(Pointer<Void>);

typedef _DisplayWidthNative = Int32 Function(Pointer<Void>, Int32);
typedef _DisplayWidthDart = int Function(Pointer<Void>, int);

typedef _DisplayHeightNative = Int32 Function(Pointer<Void>, Int32);
typedef _DisplayHeightDart = int Function(Pointer<Void>, int);

typedef _FakeKeyNative = Int32 Function(Pointer<Void>, Uint32, Int32, Uint64);
typedef _FakeKeyDart = int Function(Pointer<Void>, int, int, int);

typedef _FakeMotionNative = Int32 Function(
  Pointer<Void>,
  Int32,
  Int32,
  Int32,
  Uint64,
);
typedef _FakeMotionDart = int Function(Pointer<Void>, int, int, int, int);

typedef _FakeButtonNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Int32,
  Uint64,
);
typedef _FakeButtonDart = int Function(Pointer<Void>, int, int, int);

/// Keyboard and pointer injection through XTest.
class X11Injection implements KeyInjector {
  X11Injection({String? display}) : _displayName = display;

  final String? _displayName;

  Pointer<Void>? _display;
  DynamicLibrary? _x11;
  DynamicLibrary? _xtst;

  late final _OpenDisplayDart _open;
  late final _CloseDisplayDart _close;
  late final _StringToKeysymDart _toKeysym;
  late final _KeysymToKeycodeDart _toKeycode;
  late final _FlushDart _flush;
  late final _DefaultScreenDart _screen;
  late final _DisplayWidthDart _width;
  late final _DisplayHeightDart _height;
  late final _FakeKeyDart _fakeKey;
  late final _FakeMotionDart _fakeMotion;
  late final _FakeButtonDart _fakeButton;

  /// True when X11 and XTest could be loaded and a display opened.
  bool get available => _ensureDisplay() != null;

  bool _bound = false;
  bool _failed = false;

  Pointer<Void>? _ensureDisplay() {
    final Pointer<Void>? existing = _display;
    if (existing != null) return existing;
    if (_failed) return null;

    if (!_bound) {
      try {
        _x11 ??= DynamicLibrary.open('libX11.so.6');
        _xtst ??= DynamicLibrary.open('libXtst.so.6');

        _open = _x11!.lookupFunction<_OpenDisplayNative, _OpenDisplayDart>(
          'XOpenDisplay',
        );
        _close = _x11!.lookupFunction<_CloseDisplayNative, _CloseDisplayDart>(
          'XCloseDisplay',
        );
        _toKeysym = _x11!
            .lookupFunction<_StringToKeysymNative, _StringToKeysymDart>(
              'XStringToKeysym',
            );
        _toKeycode = _x11!
            .lookupFunction<_KeysymToKeycodeNative, _KeysymToKeycodeDart>(
              'XKeysymToKeycode',
            );
        _flush = _x11!.lookupFunction<_FlushNative, _FlushDart>('XFlush');
        _screen = _x11!
            .lookupFunction<_DefaultScreenNative, _DefaultScreenDart>(
              'XDefaultScreen',
            );
        _width = _x11!.lookupFunction<_DisplayWidthNative, _DisplayWidthDart>(
          'XDisplayWidth',
        );
        _height = _x11!
            .lookupFunction<_DisplayHeightNative, _DisplayHeightDart>(
              'XDisplayHeight',
            );
        _fakeKey = _xtst!.lookupFunction<_FakeKeyNative, _FakeKeyDart>(
          'XTestFakeKeyEvent',
        );
        _fakeMotion = _xtst!.lookupFunction<_FakeMotionNative, _FakeMotionDart>(
          'XTestFakeMotionEvent',
        );
        _fakeButton = _xtst!.lookupFunction<_FakeButtonNative, _FakeButtonDart>(
          'XTestFakeButtonEvent',
        );
        _bound = true;
      } catch (_) {
        _failed = true;
        return null;
      }
    }

    final Pointer<Utf8> name =
        (_displayName ?? Platform.environment['DISPLAY'] ?? ':0')
            .toNativeUtf8();
    final Pointer<Void> display = _open(name);
    malloc.free(name);
    if (display.address == 0) {
      _failed = true;
      return null;
    }
    _display = display;
    return display;
  }

  @override
  Future<void> pressKey(String key) async {
    final Pointer<Void>? display = _ensureDisplay();
    if (display == null) {
      throw StateError('no X11 display: keyboard injection is unavailable');
    }

    final Pointer<Utf8> name = key.toNativeUtf8();
    final int keysym = _toKeysym(name);
    malloc.free(name);
    if (keysym == 0) {
      throw ArgumentError.value(key, 'key', 'unknown X11 keysym');
    }

    final int keycode = _toKeycode(display, keysym);
    if (keycode == 0) {
      throw StateError('the keyboard layout has no keycode for "$key"');
    }

    // A short press then release, with a 12 ms gap so that applications polling
    // the key state see the change.
    _fakeKey(display, keycode, 1, 0);
    _flush(display);
    await Future<void>.delayed(const Duration(milliseconds: 12));
    _fakeKey(display, keycode, 0, 0);
    _flush(display);
  }

  @override
  Future<void> tapAt(double x, double y) async {
    final Pointer<Void>? display = _ensureDisplay();
    if (display == null) {
      throw StateError('no X11 display: pointer injection is unavailable');
    }
    final int screen = _screen(display);
    final int px = (x.clamp(0.0, 1.0) * _width(display, screen)).round();
    final int py = (y.clamp(0.0, 1.0) * _height(display, screen)).round();

    _fakeMotion(display, screen, px, py, 0);
    _flush(display);
    _fakeButton(display, 1, 1, 0);
    _flush(display);
    await Future<void>.delayed(const Duration(milliseconds: 12));
    _fakeButton(display, 1, 0, 0);
    _flush(display);
  }

  /// Closes the display connection.
  void dispose() {
    final Pointer<Void>? display = _display;
    if (display != null) {
      _close(display);
      _display = null;
    }
  }
}
