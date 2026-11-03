/// Injection backend in a browser: none.
library;

import 'package:openzclick_core/openzclick_core.dart';

import 'injection_backend_port.dart';

/// A browser cannot tap or type into another application, so there is no
/// backend: [InjectionPublisher] reports the host as unsupported.
InjectionBackend? createInjectionBackend({
  required KeyInjector injector,
  required Map<Action, String>? keys,
  required Map<Action, List<double>> positions,
}) => null;
