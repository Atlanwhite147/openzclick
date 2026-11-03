/// No Direct Sockets: a plain page, or a native host.
library;

import 'host.dart';

/// True only when the browser grants the Direct Sockets API.
const bool directSocketsAvailable = false;

/// Returns the host, `null` when this platform has no Direct Sockets.
DirectSocketsHost? createDirectSocketsHost() => null;
