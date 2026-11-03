/// One way of applying an action to the target application.
///
/// This is the seam that keeps [InjectionPublisher] free of `dart:io`: the tap
/// and key transport comes from `openzclick_transports` on a native host, and
/// no backend at all exists in a browser.
library;

import 'package:openzclick_core/openzclick_core.dart';

/// Applies actions to the target application.
abstract interface class InjectionBackend {
  /// Prepares the backend; called once per run.
  Future<void> start();

  /// Releases everything acquired by [start].
  Future<void> stop();

  /// Applies [action] once.
  Future<void> emit(Action action);
}
