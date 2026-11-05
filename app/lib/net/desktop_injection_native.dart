/// Desktop injection on a native host: X11 on Linux, `SendInput` on Windows.
///
/// One file for every host that has `dart:io`, because the choice is a runtime
/// one, not a compile-time one: a macOS build must still start and report that
/// injection is unavailable rather than fail to compile.
///
/// Windows arrived last and came with a warning worth keeping in view: Linux
/// drives a virtual device the system treats as hardware, Windows injects
/// events into a session and hopes the application listens there. See
/// `windows_injection.dart` for what that costs.
library;

import 'dart:io' show Platform;

import 'desktop_injection_port.dart';
import 'windows_focus.dart';
import 'windows_injection.dart';
import 'x11_injection.dart';

/// Returns the backend of the current host, `null` where there is none.
///
/// macOS has no backend yet: returning `null` keeps the injection switch
/// disabled, with an honest reason, instead of failing on the first press.
DesktopInjection? createDesktopInjection() {
  if (Platform.isLinux) {
    final X11Injection injector = X11Injection();
    return DesktopInjection(
      injector: injector,
      availability: () => injector.available,
    );
  }
  if (Platform.isWindows) {
    final WindowsInjection injector = WindowsInjection();
    return DesktopInjection(
      injector: injector,
      availability: () => injector.available,
      // A keystroke goes to the window that owns the focus, and that is rarely
      // the training application: see docs/injection.md.
      focuser: WindowsWindowFocuser(),
    );
  }
  return null;
}
