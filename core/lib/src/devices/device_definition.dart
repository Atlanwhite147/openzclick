/// Declarative model of a controller device.
///
/// A [DeviceDefinition] describes everything needed to recognise a device and
/// translate its notifications into normalised buttons, without any
/// device-specific code:
///
/// * the Bluetooth services advertised by the device;
/// * the expected characteristics, indexed by role (`buttons`, `analog`,
///   `battery`, `haptics`, ...);
/// * the identifier of the frame decoder to apply;
/// * the `raw byte -> normalised button id` table;
/// * the wake-on-press and automatic-sleep policy.
///
/// The class validates its invariants at construction time: an inconsistent
/// definition throws [DeviceDefinitionException] immediately, which keeps
/// invalid data from propagating down to the transport layer.
///
/// No commercial product identifier appears here: the built-in definitions use
/// generic names (`two-button-controller`, ...).
library;

/// Exception thrown when a device definition is incomplete, wrongly typed or
/// inconsistent.
class DeviceDefinitionException implements Exception {
  /// Creates the exception with an explanatory [message].
  const DeviceDefinitionException(this.message);

  /// Human-readable description of the problem.
  final String message;

  @override
  String toString() => 'DeviceDefinitionException: $message';
}

/// Pattern accepted for a definition id: lowercase letters, digits and dashes,
/// with no leading or trailing dash (kebab-case form).
final RegExp _idPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

/// Pattern accepted for a decoder id: lowercase letters, digits, dashes or
/// underscores.
final RegExp _decoderPattern = RegExp(r'^[a-z0-9]+(?:[-_][a-z0-9]+)*$');

/// Pattern accepted for a characteristic role name.
final RegExp _rolePattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// Bluetooth UUID pattern: short 16-bit form, 32-bit form or full 128-bit form
/// with dashes.
final RegExp _uuidPattern = RegExp(
  r'^(?:[0-9a-f]{4}|[0-9a-f]{8}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
  r'[0-9a-f]{4}-[0-9a-f]{12})$',
);

/// Suffix of the Bluetooth base UUID used for short UUIDs.
const String _bluetoothBaseSuffix = '-0000-1000-8000-00805f9b34fb';

/// Normalises a UUID for comparison: lowercase, without braces or stray
/// whitespace.
String normalizeUuid(String uuid) =>
    uuid.trim().replaceAll('{', '').replaceAll('}', '').toLowerCase();

/// Extracts the short (16-bit) form of a UUID when possible.
///
/// Returns `null` when the UUID does not belong to the standard Bluetooth
/// base.
String? _shortUuid(String normalized) {
  if (normalized.length == 4) return normalized;
  if (normalized.length == 8 && normalized.startsWith('0000')) {
    return normalized.substring(4);
  }
  if (normalized.length == 36 &&
      normalized.startsWith('0000') &&
      normalized.endsWith(_bluetoothBaseSuffix)) {
    return normalized.substring(4, 8);
  }
  return null;
}

/// Compares two UUIDs, tolerating case, braces and the short form.
///
/// So `FFF0`, `0000fff0-0000-1000-8000-00805f9b34fb` and
/// `{0000FFF0-0000-1000-8000-00805F9B34FB}` all designate the same service.
bool uuidEquals(String a, String b) {
  final left = normalizeUuid(a);
  final right = normalizeUuid(b);
  if (left == right) return true;
  final shortLeft = _shortUuid(left);
  final shortRight = _shortUuid(right);
  return shortLeft != null && shortRight != null && shortLeft == shortRight;
}

/// Immutable definition of a controller device.
class DeviceDefinition {
  /// Builds a validated definition.
  ///
  /// The provided collections are copied into unmodifiable views. Throws
  /// [DeviceDefinitionException] when an invariant is violated.
  DeviceDefinition({
    required this.id,
    required this.name,
    required this.manufacturer,
    required List<String> serviceUuids,
    required Map<String, String> characteristics,
    required this.decoderId,
    Map<int, int> rawToButton = const <int, int>{},
    this.wakeOnPress = false,
    this.sleepAfterSeconds,
  })  : serviceUuids = List<String>.unmodifiable(
          serviceUuids.map(normalizeUuid),
        ),
        characteristics = Map<String, String>.unmodifiable(characteristics),
        rawToButton = Map<int, int>.unmodifiable(rawToButton) {
    _validate();
  }

  /// Builds a definition from a declarative map (coming from YAML).
  ///
  /// Recognised keys (variants are tolerated):
  ///
  /// | key | alias | type |
  /// | --- | --- | --- |
  /// | `id` | - | kebab-case string |
  /// | `name` | - | string |
  /// | `manufacturer` | - | string |
  /// | `services` | `service_uuids`, `serviceUuids` | list of UUIDs |
  /// | `characteristics` | - | map role -> UUID |
  /// | `decoder` | `decoder_id`, `decoderId` | string |
  /// | `raw_to_button` | `rawToButton` | map byte -> id |
  /// | `wake_on_press` | `wakeOnPress` | boolean (default `false`) |
  /// | `sleep_after_seconds` | `sleepAfterSeconds` | integer (`0` = never) |
  ///
  /// Unknown keys are ignored, so a file may carry annotations meant for other
  /// tools without breaking loading. Type or value errors throw
  /// [DeviceDefinitionException].
  factory DeviceDefinition.fromMap(Map<String, Object?> map) {
    return DeviceDefinition(
      id: _requiredString(map, const <String>['id'], 'id'),
      name: _requiredString(map, const <String>['name'], 'name'),
      manufacturer: _requiredString(
        map,
        const <String>['manufacturer'],
        'manufacturer',
      ),
      serviceUuids: _readServices(map),
      characteristics: _readCharacteristics(map),
      decoderId: _requiredString(
        map,
        const <String>['decoder', 'decoder_id', 'decoderId'],
        'decoder',
      ),
      rawToButton: _readRawToButton(map),
      wakeOnPress: _optionalBool(
        map,
        const <String>['wake_on_press', 'wakeOnPress'],
      ),
      sleepAfterSeconds: _optionalSleep(
        map,
        const <String>['sleep_after_seconds', 'sleepAfterSeconds'],
      ),
    );
  }

  /// Stable id of the definition, in kebab-case (for example
  /// `two-button-controller`).
  final String id;

  /// Human-readable name, shown in the interface.
  final String name;

  /// Manufacturer or product line, as free text.
  final String manufacturer;

  /// UUIDs of the Bluetooth services advertised by the device, lowercased.
  final List<String> serviceUuids;

  /// Expected characteristics, indexed by role (`buttons`, `analog`, ...).
  final Map<String, String> characteristics;

  /// Id of the frame decoder (`raw-bytes`, `uart-framed`, ...).
  final String decoderId;

  /// Table `raw byte -> normalised button id`.
  ///
  /// Normalised ids are the ones defined by the protocol contract; a byte
  /// missing from the table is ignored by the decoder.
  final Map<int, int> rawToButton;

  /// True when the device wakes up on the first press.
  final bool wakeOnPress;

  /// Sleep delay in seconds, or `null` when the device stays awake.
  final int? sleepAfterSeconds;

  /// Normalised id matching a raw byte, or `null`.
  int? buttonIdFor(int rawByte) => rawToButton[rawByte];

  /// True when the definition recognises one of its services in [uuid].
  bool servesService(String uuid) =>
      serviceUuids.any((service) => uuidEquals(service, uuid));

  /// True when the device stays awake permanently.
  bool get staysAwake => sleepAfterSeconds == null;

  void _validate() {
    if (!_idPattern.hasMatch(id)) {
      throw DeviceDefinitionException(
        'invalid id "$id": lowercase letters, digits and dashes only '
        '(kebab-case form)',
      );
    }
    if (name.trim().isEmpty) {
      throw const DeviceDefinitionException('name must not be empty');
    }
    if (manufacturer.trim().isEmpty) {
      throw const DeviceDefinitionException(
        'manufacturer must not be empty',
      );
    }
    if (serviceUuids.isEmpty) {
      throw const DeviceDefinitionException(
        'at least one Bluetooth service is required',
      );
    }
    for (final service in serviceUuids) {
      if (!_uuidPattern.hasMatch(service)) {
        throw DeviceDefinitionException(
            'invalid service UUID "$service"');
      }
    }
    if (characteristics.isEmpty) {
      throw const DeviceDefinitionException(
        'at least one characteristic is required',
      );
    }
    for (final entry in characteristics.entries) {
      if (!_rolePattern.hasMatch(entry.key)) {
        throw DeviceDefinitionException(
          'invalid characteristic role "${entry.key}": lowercase letters, '
          'digits and underscores, starting with a letter',
        );
      }
      final value = normalizeUuid(entry.value);
      if (!_uuidPattern.hasMatch(value)) {
        throw DeviceDefinitionException(
          'invalid UUID "${entry.value}" for role "${entry.key}"',
        );
      }
    }
    if (!_decoderPattern.hasMatch(decoderId)) {
      throw DeviceDefinitionException(
        'invalid decoder id "$decoderId"',
      );
    }
    for (final entry in rawToButton.entries) {
      if (entry.key < 0 || entry.key > 0xFF) {
        throw DeviceDefinitionException(
          'raw byte out of range (0..255): ${entry.key}',
        );
      }
      if (entry.value <= 0 || entry.value > 0xFF) {
        throw DeviceDefinitionException(
          'button id out of range (1..255): ${entry.value} '
          'for byte ${entry.key}',
        );
      }
    }
    final sleep = sleepAfterSeconds;
    if (sleep != null && sleep <= 0) {
      throw DeviceDefinitionException(
        'sleep delay must be strictly positive (got $sleep)',
      );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceDefinition &&
        other.id == id &&
        other.name == name &&
        other.manufacturer == manufacturer &&
        other.decoderId == decoderId &&
        other.wakeOnPress == wakeOnPress &&
        other.sleepAfterSeconds == sleepAfterSeconds &&
        _listEquals(other.serviceUuids, serviceUuids) &&
        _mapEquals(other.characteristics, characteristics) &&
        _mapEquals(other.rawToButton, rawToButton);
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        manufacturer,
        decoderId,
        wakeOnPress,
        sleepAfterSeconds,
        Object.hashAllUnordered(serviceUuids),
        Object.hashAllUnordered(
          characteristics.entries.map((e) => Object.hash(e.key, e.value)),
        ),
        Object.hashAllUnordered(
          rawToButton.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  @override
  String toString() =>
      'DeviceDefinition(id: $id, name: $name, manufacturer: $manufacturer)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}

Object? _pick(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    if (map.containsKey(key)) return map[key];
  }
  return null;
}

String _requiredString(
  Map<String, Object?> map,
  List<String> keys,
  String label,
) {
  final value = _pick(map, keys);
  if (value == null) {
    throw DeviceDefinitionException('missing required field "$label"');
  }
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is num) return value.toString();
  throw DeviceDefinitionException(
    'field "$label" must be text (got: $value)',
  );
}

bool _optionalBool(Map<String, Object?> map, List<String> keys) {
  final value = _pick(map, keys);
  if (value == null) return false;
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (const <String>['true', 'yes', 'yes', '1'].contains(normalized)) {
      return true;
    }
    if (const <String>['false', 'no', 'no', '0'].contains(normalized)) {
      return false;
    }
  }
  throw DeviceDefinitionException(
    'field "${keys.first}" must be a boolean (got: $value)',
  );
}

int? _optionalSleep(Map<String, Object?> map, List<String> keys) {
  final value = _pick(map, keys);
  if (value == null) return null;
  final seconds = _asInt(value, keys.first);
  if (seconds == 0) return null;
  if (seconds < 0) {
    throw DeviceDefinitionException(
      'field "${keys.first}" is negative ($seconds): use 0 to disable',
    );
  }
  return seconds;
}

int _asInt(Object? value, String label) {
  if (value is int) return value;
  if (value is String) {
    final parsed = _parseIntegerLiteral(value);
    if (parsed != null) return parsed;
  }
  throw DeviceDefinitionException(
    'field "$label" must be an integer (got: $value)',
  );
}

/// Parses an integer literal: decimal, hexadecimal (`0x`) or binary (`0b`).
///
/// Separator underscores (`1_000`) and spaces are ignored, which makes loading
/// tolerant of hand-written files.
int? _parseIntegerLiteral(String raw) {
  var text = raw.trim().replaceAll('_', '').replaceAll(' ', '');
  if (text.isEmpty) return null;
  var sign = 1;
  if (text.startsWith('-')) {
    sign = -1;
    text = text.substring(1);
  } else if (text.startsWith('+')) {
    text = text.substring(1);
  }
  int? value;
  if (text.startsWith('0x') || text.startsWith('0X')) {
    value = int.tryParse(text.substring(2), radix: 16);
  } else if (text.startsWith('0b') || text.startsWith('0B')) {
    value = int.tryParse(text.substring(2), radix: 2);
  } else {
    value = int.tryParse(text);
  }
  return value == null ? null : sign * value;
}

List<String> _readServices(Map<String, Object?> map) {
  final value = _pick(map, const <String>[
    'services',
    'service_uuids',
    'serviceUuids',
  ]);
  if (value == null) {
    throw const DeviceDefinitionException(
      'missing required field "services"',
    );
  }
  if (value is String) return <String>[_cleanUuid(value)];
  if (value is List<Object?>) {
    if (value.isEmpty) {
      throw const DeviceDefinitionException(
        'field "services" is empty: at least one UUID is required',
      );
    }
    return value.map((item) => _cleanUuid('$item')).toList(growable: false);
  }
  throw DeviceDefinitionException(
    'field "services" must be a list (got: $value)',
  );
}

String _cleanUuid(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw const DeviceDefinitionException('empty UUID in services');
  }
  return trimmed;
}

Map<String, String> _readCharacteristics(Map<String, Object?> map) {
  final value = _pick(map, const <String>['characteristics']);
  if (value == null) {
    throw const DeviceDefinitionException(
      'missing required field "characteristics"',
    );
  }
  if (value is! Map<Object?, Object?>) {
    throw DeviceDefinitionException(
      'field "characteristics" must be a map '
      'role -> UUID (got: $value)',
    );
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    final role = '${entry.key}'.trim();
    final uuid = '${entry.value}'.trim();
    if (role.isEmpty || uuid.isEmpty) {
      throw const DeviceDefinitionException(
        'incomplete characteristic: both role and UUID are required',
      );
    }
    result[role] = uuid;
  }
  return result;
}

Map<int, int> _readRawToButton(Map<String, Object?> map) {
  final value = _pick(map, const <String>['raw_to_button', 'rawToButton']);
  if (value == null) return const <int, int>{};
  if (value is! Map<Object?, Object?>) {
    throw DeviceDefinitionException(
      'field "raw_to_button" must be a map '
      'byte -> id (got: $value)',
    );
  }
  final result = <int, int>{};
  for (final entry in value.entries) {
    final raw = _asInt(entry.key, 'raw_to_button (key)');
    final button = _asInt(entry.value, 'raw_to_button (value)');
    if (result.containsKey(raw)) {
      throw DeviceDefinitionException(
        'duplicate raw byte in "raw_to_button": $raw',
      );
    }
    result[raw] = button;
  }
  return result;
}
