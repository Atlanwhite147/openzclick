/// The host's synthetic input backend, when it has one.
///
/// Declared once so that [createDesktopInjection] has a single return type: the
/// library that provides it depends on the host (X11 on Linux, nothing in a
/// browser), the shape does not.
library;

import 'package:openzclick_core/openzclick_core.dart';

/// A working injector plus what the interface needs to drive it.
class DesktopInjection {
  /// Builds the description.
  DesktopInjection({required this.injector, this.availability});

  /// The injector itself.
  final KeyInjector injector;

  /// Synchronous test of the platform capability, asked before the switch is
  /// enabled. `null` when the backend is always ready.
  final bool Function()? availability;
}
