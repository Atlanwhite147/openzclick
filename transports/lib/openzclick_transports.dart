/// Public entry point of the transports package.
///
/// Every transport implements [Transport] and publishes a [TransportEvent]
/// stream. Nothing here is started implicitly: advertising stays off until the
/// application calls `start()`.
library;

export 'src/openzclick_transports.dart';
