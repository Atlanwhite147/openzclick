/// Sockets of the current host.
///
/// A browser only grants them to an Isolated Web App; everywhere else this
/// resolves to [createDirectSocketsHost] returning `null`.
library;

export 'host.dart';
export 'host_none.dart' if (dart.library.js_interop) 'host_web.dart';
