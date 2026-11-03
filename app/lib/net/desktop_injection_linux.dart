/// Desktop injection on Linux: X11 and XTest, loaded at runtime.
library;

import 'dart:io' show Platform;

import 'desktop_injection_port.dart';
import 'x11_injection.dart';

/// Returns the X11 backend on Linux, `null` everywhere else.
///
/// Windows and macOS have no backend yet: returning `null` keeps the injection
/// switch disabled, with an honest reason, instead of failing on the first
/// press.
DesktopInjection? createDesktopInjection() {
  if (!Platform.isLinux) return null;
  final X11Injection injector = X11Injection();
  return DesktopInjection(
    injector: injector,
    availability: () => injector.available,
  );
}
