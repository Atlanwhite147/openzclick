import 'dart:convert';

/// Binary protocol message types, carried by the first byte of each frame.
enum ObcMessageType {
  /// Button state (`0x01`).
  buttonState(0x01),

  /// Device status, battery and connection (`0x02`).
  deviceStatus(0x02),

  /// Haptic command (`0x03`).
  haptic(0x03),

  /// Target application info (`0x04`).
  appInfo(0x04);

  const ObcMessageType(this.code);

  /// Value of the type byte on the wire.
  final int code;

  /// Maps a type byte to its enum value.
  ///
  /// Returns `null` if [code] matches no known type.
  static ObcMessageType? fromCode(int code) {
    for (final ObcMessageType type in ObcMessageType.values) {
      if (type.code == code) {
        return type;
      }
    }
    return null;
  }
}

/// Length of the header common to all frames: a type byte followed by a body
/// length byte.
const int obcHeaderLength = 2;

/// Builds a complete `[type][length][body]` frame.
List<int> _frame(int typeCode, List<int> body) {
  if (body.length > 0xFF) {
    throw ArgumentError.value(
      body.length,
      'body',
      'body must fit in the length byte (0..255)',
    );
  }
  return <int>[typeCode, body.length, ...body];
}

/// Checks a frame header and returns its body.
///
/// Throws a [FormatException] if the type does not match [expectedType] or if
/// the declared length does not match the number of bytes supplied.
List<int> _checkedBody(List<int> bytes, int expectedType) {
  if (bytes.length < obcHeaderLength) {
    throw FormatException(
      'truncated frame: ${bytes.length} byte(s), $obcHeaderLength-byte header '
      'expected',
    );
  }
  final int type = bytes[0];
  if (type != expectedType) {
    throw FormatException(
      'unexpected message type: 0x${type.toRadixString(16)}, '
      '0x${expectedType.toRadixString(16)} expected',
    );
  }
  final int declared = bytes[1];
  final int actual = bytes.length - obcHeaderLength;
  if (declared != actual) {
    throw FormatException(
      'declared length $declared inconsistent with $actual body byte(s)',
    );
  }
  return bytes.sublist(obcHeaderLength);
}

/// Checks that a value fits in one byte.
void _requireByte(int value, String name) {
  if (value < 0 || value > 0xFF) {
    throw ArgumentError.value(value, name, 'must fit in one byte (0..255)');
  }
}

/// Button state of a controller.
///
/// Each entry maps a normalized identifier (see `ButtonIds`) to its value:
/// `0` released, `1` pressed, `2..255` analog value.
class ButtonStateMessage {
  /// Maximum length of a `0x01` frame, header included.
  ///
  /// Beyond that the frame is treated as malformed: it is dropped and the
  /// stream is resynchronized.
  static const int maxFrameLength = 20;

  /// Maximum number of buttons per frame (one byte pair per button).
  static const int maxButtons =
      (maxFrameLength - obcHeaderLength) ~/ 2;

  /// Button table, normalized identifier to value.
  final Map<int, int> buttons;

  /// Creates a message from [buttons].
  ButtonStateMessage(Map<int, int> buttons)
      : buttons = Map<int, int>.unmodifiable(buttons);

  /// Serializes the message into a complete frame.
  ///
  /// Buttons are emitted by ascending identifier, which makes the encoding
  /// deterministic whatever the insertion order of the table.
  List<int> encode() {
    final List<int> ids = buttons.keys.toList()..sort();
    if (ids.length > maxButtons) {
      throw ArgumentError.value(
        ids.length,
        'buttons',
        'at most $maxButtons buttons per 0x01 frame',
      );
    }
    final List<int> body = <int>[];
    for (final int id in ids) {
      _requireByte(id, 'buttonId');
      final int value = buttons[id]!;
      _requireByte(value, 'buttonValue');
      body
        ..add(id)
        ..add(value);
    }
    return _frame(ObcMessageType.buttonState.code, body);
  }

  /// Decodes a complete `0x01` frame.
  ///
  /// Throws a [FormatException] if the frame is truncated, if its type or
  /// length is inconsistent, or if the body is not a series of pairs.
  static ButtonStateMessage decode(List<int> bytes) {
    final List<int> body = _checkedBody(bytes, ObcMessageType.buttonState.code);
    if (bytes.length > maxFrameLength) {
      throw FormatException(
        '0x01 frame of ${bytes.length} bytes, maximum $maxFrameLength',
      );
    }
    if (body.length.isOdd) {
      throw FormatException(
        'odd-length 0x01 body (${body.length}): identifier/value pairs '
        'expected',
      );
    }
    final Map<int, int> buttons = <int, int>{};
    for (int i = 0; i < body.length; i += 2) {
      buttons[body[i]] = body[i + 1];
    }
    return ButtonStateMessage(buttons);
  }

  /// Converts the message into the decoded [ButtonState] variant.
  ButtonState toMessage() => ButtonState(buttons);

  @override
  String toString() => 'ButtonStateMessage($buttons)';
}

/// Device status: battery level and link with the application.
class DeviceStatusMessage {
  /// Battery value meaning "unknown".
  static const int unknownBattery = 0xFF;

  /// Battery level, `0..100` or [unknownBattery].
  final int battery;

  /// True if the device reports itself as connected to the target
  /// application.
  final bool connected;

  /// Creates a status message.
  const DeviceStatusMessage({required this.battery, required this.connected});

  /// Serializes the message into a complete frame.
  List<int> encode() {
    if (battery != unknownBattery && (battery < 0 || battery > 100)) {
      throw ArgumentError.value(
        battery,
        'battery',
        'must be 0..100 or $unknownBattery',
      );
    }
    return _frame(ObcMessageType.deviceStatus.code, <int>[
      battery,
      connected ? 1 : 0,
    ]);
  }

  /// Decodes a complete `0x02` frame.
  static DeviceStatusMessage decode(List<int> bytes) {
    final List<int> body = _checkedBody(bytes, ObcMessageType.deviceStatus.code);
    if (body.length != 2) {
      throw FormatException(
        '0x02 body of ${body.length} byte(s), 2 expected',
      );
    }
    final int battery = body[0];
    if (battery != unknownBattery && battery > 100) {
      throw FormatException('invalid battery level: $battery');
    }
    if (body[1] > 1) {
      throw FormatException('invalid connection flag: ${body[1]}');
    }
    return DeviceStatusMessage(battery: battery, connected: body[1] == 1);
  }

  /// Converts the message into the decoded [DeviceStatus] variant.
  DeviceStatus toMessage() =>
      DeviceStatus(battery: battery, connected: connected);

  @override
  String toString() =>
      'DeviceStatusMessage(battery: $battery, connected: $connected)';
}

/// Haptic command sent to the controller.
class HapticMessage {
  /// Vibration pattern, `0..255`.
  final int pattern;

  /// Duration in 10 ms units, `0..255`.
  final int duration10ms;

  /// Intensity, `0..255`.
  final int intensity;

  /// Creates a haptic command.
  const HapticMessage({
    required this.pattern,
    required this.duration10ms,
    required this.intensity,
  });

  /// Serializes the message into a complete frame.
  List<int> encode() {
    _requireByte(pattern, 'pattern');
    _requireByte(duration10ms, 'duration10ms');
    _requireByte(intensity, 'intensity');
    return _frame(ObcMessageType.haptic.code, <int>[
      pattern,
      duration10ms,
      intensity,
    ]);
  }

  /// Decodes a complete `0x03` frame.
  static HapticMessage decode(List<int> bytes) {
    final List<int> body = _checkedBody(bytes, ObcMessageType.haptic.code);
    if (body.length != 3) {
      throw FormatException(
        '0x03 body of ${body.length} byte(s), 3 expected',
      );
    }
    return HapticMessage(
      pattern: body[0],
      duration10ms: body[1],
      intensity: body[2],
    );
  }

  /// Converts the message into the decoded [HapticCommand] variant.
  HapticCommand toMessage() => HapticCommand(
        pattern: pattern,
        duration10ms: duration10ms,
        intensity: intensity,
      );

  @override
  String toString() => 'HapticMessage(pattern: $pattern, '
      'duration10ms: $duration10ms, intensity: $intensity)';
}

/// Information published by the target application.
class AppInfoMessage {
  /// Application identifier, UTF-8 encoded.
  final String appId;

  /// Application version, UTF-8 encoded.
  final String appVersion;

  /// Button identifiers supported by the application.
  final List<int> supportedButtons;

  /// Creates an application info message.
  AppInfoMessage({
    required this.appId,
    required this.appVersion,
    required List<int> supportedButtons,
  }) : supportedButtons = List<int>.unmodifiable(supportedButtons);

  /// Serializes the message into a complete frame.
  ///
  /// The body is `[len(appId)][appId][len(version)][version][n][buttons...]`.
  List<int> encode() {
    final List<int> idBytes = utf8.encode(appId);
    final List<int> versionBytes = utf8.encode(appVersion);
    if (idBytes.length > 0xFF) {
      throw ArgumentError.value(
        idBytes.length,
        'appId',
        'identifier too long (at most 255 UTF-8 bytes)',
      );
    }
    if (versionBytes.length > 0xFF) {
      throw ArgumentError.value(
        versionBytes.length,
        'appVersion',
        'version too long (at most 255 UTF-8 bytes)',
      );
    }
    if (supportedButtons.length > 0xFF) {
      throw ArgumentError.value(
        supportedButtons.length,
        'supportedButtons',
        'at most 255 supported buttons',
      );
    }
    for (final int id in supportedButtons) {
      _requireByte(id, 'supportedButton');
    }
    final List<int> body = <int>[
      idBytes.length,
      ...idBytes,
      versionBytes.length,
      ...versionBytes,
      supportedButtons.length,
      ...supportedButtons,
    ];
    if (body.length > 0xFF) {
      throw ArgumentError.value(
        body.length,
        'body',
        'body must fit in the length byte (0..255)',
      );
    }
    return _frame(ObcMessageType.appInfo.code, body);
  }

  /// Decodes a complete `0x04` frame.
  ///
  /// Throws a [FormatException] if the declared lengths are inconsistent with
  /// the body size, if the UTF-8 is invalid, or if bytes are left unconsumed.
  static AppInfoMessage decode(List<int> bytes) {
    final List<int> body = _checkedBody(bytes, ObcMessageType.appInfo.code);
    int cursor = 0;

    int takeLength() {
      if (cursor >= body.length) {
        throw FormatException('truncated 0x04 body: missing length');
      }
      return body[cursor++];
    }

    List<int> takeBytes(int length, String field) {
      if (cursor + length > body.length) {
        throw FormatException(
          'truncated 0x04 body: $length byte(s) expected for $field, '
          '${body.length - cursor} available',
        );
      }
      final List<int> slice = body.sublist(cursor, cursor + length);
      cursor += length;
      return slice;
    }

    String readString(String field) {
      final int length = takeLength();
      final List<int> raw = takeBytes(length, field);
      try {
        return utf8.decode(raw);
      } on FormatException {
        throw FormatException('$field is not valid UTF-8');
      }
    }

    final String appId = readString('appId');
    final String appVersion = readString('appVersion');
    final int count = takeLength();
    final List<int> buttons = takeBytes(count, 'supportedButtons');
    if (cursor != body.length) {
      throw FormatException(
        'inconsistent 0x04 body: ${body.length - cursor} byte(s) '
        'left unconsumed',
      );
    }
    return AppInfoMessage(
      appId: appId,
      appVersion: appVersion,
      supportedButtons: buttons,
    );
  }

  /// Converts the message into the decoded [AppInfo] variant.
  AppInfo toMessage() => AppInfo(
        appId: appId,
        appVersion: appVersion,
        supportedButtons: supportedButtons,
      );

  @override
  String toString() => 'AppInfoMessage(appId: $appId, '
      'appVersion: $appVersion, supportedButtons: $supportedButtons)';
}

/// Decoded message, ready to be consumed by the upper layers.
sealed class ObcMessage {
  /// Builds a decoded message.
  const ObcMessage();

  /// Message type as it was on the wire.
  ObcMessageType get type;
}

/// Decoded button state.
class ButtonState extends ObcMessage {
  /// Button table, normalized identifier to value.
  final Map<int, int> buttons;

  /// Creates a button state.
  ButtonState(Map<int, int> buttons)
      : buttons = Map<int, int>.unmodifiable(buttons);

  @override
  ObcMessageType get type => ObcMessageType.buttonState;

  @override
  String toString() => 'ButtonState($buttons)';
}

/// Decoded device status.
class DeviceStatus extends ObcMessage {
  /// Battery level, `0..100` or [DeviceStatusMessage.unknownBattery].
  final int battery;

  /// True if the device reports itself as connected.
  final bool connected;

  /// Creates a device status.
  const DeviceStatus({required this.battery, required this.connected});

  @override
  ObcMessageType get type => ObcMessageType.deviceStatus;

  @override
  String toString() => 'DeviceStatus(battery: $battery, connected: $connected)';
}

/// Decoded haptic command.
class HapticCommand extends ObcMessage {
  /// Vibration pattern, `0..255`.
  final int pattern;

  /// Duration in 10 ms units, `0..255`.
  final int duration10ms;

  /// Intensity, `0..255`.
  final int intensity;

  /// Creates a decoded haptic command.
  const HapticCommand({
    required this.pattern,
    required this.duration10ms,
    required this.intensity,
  });

  @override
  ObcMessageType get type => ObcMessageType.haptic;

  @override
  String toString() => 'HapticCommand(pattern: $pattern, '
      'duration10ms: $duration10ms, intensity: $intensity)';
}

/// Decoded application info.
class AppInfo extends ObcMessage {
  /// Application identifier.
  final String appId;

  /// Application version.
  final String appVersion;

  /// Supported button identifiers.
  final List<int> supportedButtons;

  /// Creates application info.
  AppInfo({
    required this.appId,
    required this.appVersion,
    required List<int> supportedButtons,
  }) : supportedButtons = List<int>.unmodifiable(supportedButtons);

  @override
  ObcMessageType get type => ObcMessageType.appInfo;

  @override
  String toString() => 'AppInfo(appId: $appId, appVersion: $appVersion, '
      'supportedButtons: $supportedButtons)';
}
