/// Injection backend of the current host.
library;

export 'injection_backend_port.dart';
export 'injection_backend_none.dart'
    if (dart.library.io) 'injection_backend_native.dart';
