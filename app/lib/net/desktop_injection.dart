/// Synthetic input backend of the current host.
///
/// The library that provides it depends on the host: X11 on Linux, nothing in a
/// browser. Everything above this file only needs [DesktopInjection].
library;

export 'desktop_injection_port.dart';
export 'desktop_injection_none.dart'
    if (dart.library.io) 'desktop_injection_linux.dart';
