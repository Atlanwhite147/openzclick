/// Registry of the built-in device definitions.
///
/// The registry is read-only and performs no I/O: definitions are built in
/// Dart, which guarantees their validity as soon as the library compiles and
/// avoids any dependency on an asset loader.
///
/// The `assets/devices/*.yaml` files describe exactly the same devices in
/// declarative form; a test checks that parity so the two paths (code and
/// declarative) never diverge.
library;

import 'device_definition.dart';

/// Catalogue of known devices.
///
/// Every definition uses a generic name: no commercial brand or model is
/// referenced.
abstract final class DeviceRegistry {
  /// Definitions shipped with the core.
  ///
  /// The order is stable: simplest devices first.
  static final List<DeviceDefinition> _builtin =
      List<DeviceDefinition>.unmodifiable(<DeviceDefinition>[
    DeviceDefinition(
      id: 'two-button-controller',
      name: 'Two-button controller',
      manufacturer: 'Generic',
      serviceUuids: const <String>[
        '0000fff0-0000-1000-8000-00805f9b34fb',
      ],
      characteristics: const <String, String>{
        'buttons': '0000fff1-0000-1000-8000-00805f9b34fb',
        'battery': '0000180f-0000-1000-8000-00805f9b34fb',
      },
      decoderId: 'raw-bytes',
      rawToButton: const <int, int>{0x01: 0x01, 0x02: 0x02},
      wakeOnPress: true,
      sleepAfterSeconds: 300,
    ),
    DeviceDefinition(
      id: 'six-button-shifter',
      name: 'Six-button shifter',
      manufacturer: 'Generic',
      serviceUuids: const <String>[
        '0000ffe0-0000-1000-8000-00805f9b34fb',
      ],
      characteristics: const <String, String>{
        'buttons': '0000ffe1-0000-1000-8000-00805f9b34fb',
        'haptics': '0000ffe2-0000-1000-8000-00805f9b34fb',
        'battery': '0000180f-0000-1000-8000-00805f9b34fb',
      },
      decoderId: 'raw-bytes',
      rawToButton: const <int, int>{
        0x10: 0x01, // towards the top of the cassette
        0x11: 0x02, // towards the bottom of the cassette
        0x12: 0x10, // navigate up
        0x13: 0x11, // navigate down
        0x14: 0x14, // confirm
        0x15: 0x15, // back
      },
      wakeOnPress: true,
      sleepAfterSeconds: 600,
    ),
    DeviceDefinition(
      id: 'generic-gamepad',
      name: 'Generic gamepad',
      manufacturer: 'Generic',
      serviceUuids: const <String>[
        '0000ff00-0000-1000-8000-00805f9b34fb',
      ],
      characteristics: const <String, String>{
        'buttons': '0000ff01-0000-1000-8000-00805f9b34fb',
        'analog': '0000ff02-0000-1000-8000-00805f9b34fb',
        'battery': '0000180f-0000-1000-8000-00805f9b34fb',
      },
      decoderId: 'uart-framed',
      rawToButton: const <int, int>{
        0x01: 0x18, // steer left
        0x02: 0x19, // steer right
        0x03: 0x1A, // brake
        0x04: 0x33, // pause
        0x05: 0x34, // resume
        0x06: 0x38, // change mode
      },
      wakeOnPress: false,
      sleepAfterSeconds: 60,
    ),
  ]);

  /// List of the definitions shipped with the core.
  static List<DeviceDefinition> get builtin => _builtin;

  /// Looks up a definition by exact id.
  ///
  /// Returns `null` when no built-in device carries that id.
  static DeviceDefinition? byId(String id) {
    for (final definition in _builtin) {
      if (definition.id == id) return definition;
    }
    return null;
  }

  /// Looks up the first definition advertising the [uuid] service.
  ///
  /// The comparison tolerates case, braces and the short UUID form (see
  /// [uuidEquals]). Returns `null` when no device matches.
  static DeviceDefinition? matchingService(String uuid) {
    for (final definition in _builtin) {
      if (definition.servesService(uuid)) return definition;
    }
    return null;
  }

  /// Looks up the first definition advertising one of the [uuids] services.
  ///
  /// Useful when a device exposes several services: the order of the supplied
  /// UUIDs determines the matching priority.
  static DeviceDefinition? matchingAnyService(Iterable<String> uuids) {
    for (final uuid in uuids) {
      final match = matchingService(uuid);
      if (match != null) return match;
    }
    return null;
  }
}
