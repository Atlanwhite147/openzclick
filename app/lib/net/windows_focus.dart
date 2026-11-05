/// The Windows implementation of [WindowFocuser].
///
/// `EnumWindows` walks the top-level windows of the session, `GetWindowTextW`
/// gives the title of each, and the first title containing the configured string
/// is restored and activated with `ShowWindow` + `SetForegroundWindow`.
///
/// Three details are worth knowing before changing this file:
///
///  * the enumeration callback is a `fromFunction` pointer, so it cannot close
///    over anything: the target string, the found handle and the two symbols the
///    callback needs travel through library-level variables, assigned in
///    [_bind]. One `focusWindow` call at a time is the contract, which the
///    injection publisher keeps by awaiting each injection.
///  * `SetForegroundWindow` is refused by Windows when the calling process does
///    not own the foreground. The call returns a boolean and it is honoured
///    here: a refused activation reports `false` rather than pretending.
///  * invisible windows are skipped, otherwise a hidden helper window with the
///    right title wins the match and nothing appears.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'window_focus.dart';

typedef _EnumWindowsNative = Int32 Function(
  Pointer<NativeFunction<_EnumProcNative>>,
  IntPtr,
);
typedef _EnumWindowsDart = int Function(
  Pointer<NativeFunction<_EnumProcNative>>,
  int,
);
typedef _EnumProcNative = Int32 Function(IntPtr, IntPtr);

typedef _GetWindowTextWNative = Int32 Function(IntPtr, Pointer<Uint16>, Int32);
typedef _GetWindowTextWDart = int Function(int, Pointer<Uint16>, int);

typedef _IsWindowVisibleNative = Int32 Function(IntPtr);
typedef _IsWindowVisibleDart = int Function(int);

typedef _ShowWindowNative = Int32 Function(IntPtr, Int32);
typedef _ShowWindowDart = int Function(int, int);

typedef _SetForegroundWindowNative = Int32 Function(IntPtr);
typedef _SetForegroundWindowDart = int Function(int);

typedef _IsIconicNative = Int32 Function(IntPtr);
typedef _IsIconicDart = int Function(int);

/// Target of the enumeration in progress.
String _wanted = '';

/// Handle the enumeration found, 0 when nothing matched.
int _found = 0;

/// Symbols the callback needs; a `fromFunction` callback cannot read an
/// instance field, so they live here and are assigned once, in [_bind].
_IsWindowVisibleDart? _isVisible;
_GetWindowTextWDart? _readTitle;

/// Windows implementation of [WindowFocuser].
class WindowsWindowFocuser implements WindowFocuser {
  _EnumWindowsDart? _enumWindows;
  _ShowWindowDart? _showWindow;
  _SetForegroundWindowDart? _setForegroundWindow;
  _IsIconicDart? _isIconic;
  Pointer<NativeFunction<_EnumProcNative>>? _callback;
  bool _failed = false;

  bool _bind() {
    if (_callback != null) return true;
    if (_failed) return false;
    try {
      final DynamicLibrary user32 = DynamicLibrary.open('user32.dll');
      _enumWindows = user32
          .lookupFunction<_EnumWindowsNative, _EnumWindowsDart>('EnumWindows');
      _readTitle = user32
          .lookupFunction<_GetWindowTextWNative, _GetWindowTextWDart>(
            'GetWindowTextW',
          );
      _isVisible = user32
          .lookupFunction<_IsWindowVisibleNative, _IsWindowVisibleDart>(
            'IsWindowVisible',
          );
      _showWindow = user32.lookupFunction<_ShowWindowNative, _ShowWindowDart>(
        'ShowWindow',
      );
      _setForegroundWindow = user32
          .lookupFunction<_SetForegroundWindowNative, _SetForegroundWindowDart>(
            'SetForegroundWindow',
          );
      _isIconic = user32.lookupFunction<_IsIconicNative, _IsIconicDart>(
        'IsIconic',
      );
      _callback = Pointer.fromFunction<_EnumProcNative>(_visit, 1);
      return true;
    } catch (_) {
      _failed = true;
      return false;
    }
  }

  @override
  Future<bool> focusWindow(String match) async {
    if (match.trim().isEmpty) return true;
    if (!_bind()) return false;
    _wanted = match;
    _found = 0;
    _enumWindows!(_callback!, 0);
    final int target = _found;
    _wanted = '';
    if (target == 0) return false;
    if (_isIconic!(target) != 0) {
      _showWindow!(target, 9); // SW_RESTORE
    }
    return _setForegroundWindow!(target) != 0;
  }

  /// Called by the system for each top-level window; stops at the first match.
  static int _visit(int hwnd, int _) {
    final _IsWindowVisibleDart? visible = _isVisible;
    final _GetWindowTextWDart? title = _readTitle;
    if (visible == null || title == null) return 0;
    if (visible(hwnd) == 0) return 1;
    final Pointer<Uint16> buffer = calloc<Uint16>(512);
    try {
      final int length = title(hwnd, buffer, 512);
      if (length <= 0) return 1;
      if (windowTitleMatches(buffer.cast<Utf16>().toDartString(), _wanted)) {
        _found = hwnd;
        return 0; // stop the enumeration
      }
    } finally {
      calloc.free(buffer);
    }
    return 1;
  }
}
