/// Injection backend built on the local transport of `openzclick_transports`.
library;

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';

import 'injection_backend_port.dart';

/// Injection through [LocalInjectionTransport].
class LocalInjectionBackend implements InjectionBackend {
  LocalInjectionBackend({
    required KeyInjector injector,
    required Map<Action, InjectionTarget> targets,
  }) : _transport = LocalInjectionTransport(
         injector: injector,
         targets: targets,
       );

  final LocalInjectionTransport _transport;

  @override
  Future<void> start() => _transport.start();

  @override
  Future<void> stop() => _transport.stop();

  @override
  Future<void> emit(Action action) => _transport.emit(action);
}

/// Builds the backend for a native host.
///
/// [keys] switches from taps to key presses: each action is then translated
/// into the key listed there, which is how desktop hosts drive an application
/// that listens to shortcuts.
InjectionBackend createInjectionBackend({
  required KeyInjector injector,
  required Map<Action, String>? keys,
  required Map<Action, List<double>> positions,
}) {
  return LocalInjectionBackend(
    injector: injector,
    targets: <Action, InjectionTarget>{
      if (keys != null)
        for (final MapEntry<Action, String> entry in keys.entries)
          entry.key: KeyTarget(entry.value)
      else
        for (final MapEntry<Action, List<double>> entry in positions.entries)
          entry.key: PointTarget(entry.value[0], entry.value[1]),
    },
  );
}
