/// Desktop injection in a browser: nothing to inject with.
library;

import 'desktop_injection_port.dart';

/// A browser cannot synthesise a tap or a keystroke in another application.
DesktopInjection? createDesktopInjection() => null;
