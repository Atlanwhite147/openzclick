/// Public entry point of the project core.
///
/// Pure Dart: no I/O, no plugins, no platform code. Everything here can be
/// exercised by `dart test` without hardware.
library;

export 'src/devices/openzclick_devices.dart';
export 'src/mapping/openzclick_mapping.dart';
export 'src/protocol/openzclick_protocol.dart';
export 'src/shifting/openzclick_shifting.dart';
