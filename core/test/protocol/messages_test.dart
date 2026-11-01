import 'package:openzclick_core/src/protocol/openzclick_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ObcMessageType', () {
    test('codes match the contract', () {
      expect(ObcMessageType.buttonState.code, 0x01);
      expect(ObcMessageType.deviceStatus.code, 0x02);
      expect(ObcMessageType.haptic.code, 0x03);
      expect(ObcMessageType.appInfo.code, 0x04);
    });

    test('codes are unique', () {
      final Set<int> codes =
          ObcMessageType.values.map((ObcMessageType t) => t.code).toSet();
      expect(codes, hasLength(ObcMessageType.values.length));
    });

    test('fromCode resolves each type', () {
      expect(ObcMessageType.fromCode(0x01), ObcMessageType.buttonState);
      expect(ObcMessageType.fromCode(0x02), ObcMessageType.deviceStatus);
      expect(ObcMessageType.fromCode(0x03), ObcMessageType.haptic);
      expect(ObcMessageType.fromCode(0x04), ObcMessageType.appInfo);
    });

    test('fromCode returns null for an unknown code', () {
      expect(ObcMessageType.fromCode(0x00), isNull);
      expect(ObcMessageType.fromCode(0x05), isNull);
      expect(ObcMessageType.fromCode(0xFF), isNull);
    });
  });

  group('ButtonStateMessage - encoding', () {
    test('a minimal frame is the type byte alone', () {
      final ButtonStateMessage message = ButtonStateMessage(<int, int>{});
      expect(message.encode(), <int>[0x01]);
    });

    test('encoding is sorted by ascending identifier', () {
      final ButtonStateMessage message = ButtonStateMessage(<int, int>{
        ButtonIds.confirm: 1,
        ButtonIds.shiftDown: 0,
        ButtonIds.shiftUp: 1,
      });
      expect(message.encode(), <int>[
        0x01, // type byte
        ButtonIds.shiftUp, 0x01,
        ButtonIds.shiftDown, 0x00,
        ButtonIds.confirm, 0x01,
      ]);
    });

    test('analog values are kept as is', () {
      final ButtonStateMessage message = ButtonStateMessage(<int, int>{
        ButtonIds.brake: 200,
        ButtonIds.steeringAngle: 255,
      });
      expect(message.encode(), <int>[
        0x01,
        ButtonIds.brake,
        200,
        ButtonIds.steeringAngle,
        255,
      ]);
    });

    test('nine buttons fit in the 20-byte maximum frame', () {
      final Map<int, int> buttons = <int, int>{
        for (int i = 0; i < ButtonStateMessage.maxButtons; i++) 0x10 + i: 1,
      };
      final List<int> frame = ButtonStateMessage(buttons).encode();
      expect(ButtonStateMessage.maxButtons, 9);
      expect(ButtonStateMessage.maxFrameLength, 20);
      expect(frame, hasLength(19));
      expect(frame.skip(1), hasLength(18));
    });

    test('ten buttons exceed the maximum frame', () {
      final Map<int, int> buttons = <int, int>{
        for (int i = 0; i < 10; i++) 0x10 + i: 1,
      };
      expect(
        () => ButtonStateMessage(buttons).encode(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an out-of-byte value is rejected', () {
      expect(
        () => ButtonStateMessage(<int, int>{ButtonIds.shiftUp: 256}).encode(),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ButtonStateMessage(<int, int>{ButtonIds.shiftUp: -1}).encode(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an out-of-byte identifier is rejected', () {
      expect(
        () => ButtonStateMessage(<int, int>{0x100: 1}).encode(),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ButtonStateMessage - decoding', () {
    test('round trip of a button table', () {
      final Map<int, int> buttons = <int, int>{
        ButtonIds.shiftUp: 1,
        ButtonIds.shiftDown: 0,
        ButtonIds.steerLeft: 128,
      };
      final List<int> frame = ButtonStateMessage(buttons).encode();
      final ButtonStateMessage decoded = ButtonStateMessage.decode(frame);
      expect(decoded.buttons, buttons);
    });

    test('the decoded table is immutable', () {
      final ButtonStateMessage decoded = ButtonStateMessage.decode(<int>[
        0x01,
        ButtonIds.confirm,
        1,
      ]);
      expect(
        () => decoded.buttons[ButtonIds.shiftUp] = 1,
        throwsUnsupportedError,
      );
    });

    test('a different frame type is rejected', () {
      final List<int> deviceStatus = const DeviceStatusMessage(
        battery: 50,
        connected: true,
      ).encode();
      expect(
        () => ButtonStateMessage.decode(deviceStatus),
        throwsA(isA<FormatException>()),
      );
    });

    test('an empty frame is rejected', () {
      expect(
        () => ButtonStateMessage.decode(<int>[]),
        throwsA(isA<FormatException>()),
      );
    });

    test('an odd-length body is rejected', () {
      expect(
        () => ButtonStateMessage.decode(<int>[0x01, 0x10, 0x01, 0x11]),
        throwsA(isA<FormatException>()),
      );
    });

    test('a frame longer than 20 bytes is rejected', () {
      final List<int> oversized = <int>[
        0x01, // 22-byte body: 23 in total
        for (int i = 0; i < 11; i++) ...<int>[0x10 + i, 0x01],
      ];
      expect(oversized, hasLength(23));
      expect(
        () => ButtonStateMessage.decode(oversized),
        throwsA(isA<FormatException>()),
      );
    });

    test('toMessage exposes the decoded variant', () {
      final ButtonState message =
          ButtonStateMessage(<int, int>{ButtonIds.shiftUp: 1}).toMessage();
      expect(message, isA<ButtonState>());
      expect(message.type, ObcMessageType.buttonState);
      expect(message.buttons, <int, int>{ButtonIds.shiftUp: 1});
    });
  });

  group('DeviceStatusMessage', () {
    test('encoding of a connected state', () {
      const DeviceStatusMessage message = DeviceStatusMessage(
        battery: 85,
        connected: true,
      );
      expect(message.encode(), <int>[0x02, 85, 0x01]);
    });

    test('encoding of a disconnected state', () {
      const DeviceStatusMessage message = DeviceStatusMessage(
        battery: 0,
        connected: false,
      );
      expect(message.encode(), <int>[0x02, 0x00, 0x00]);
    });

    test('unknown battery encodes as 0xFF', () {
      const DeviceStatusMessage message = DeviceStatusMessage(
        battery: DeviceStatusMessage.unknownBattery,
        connected: true,
      );
      expect(message.encode(), <int>[0x02, 0xFF, 0x01]);
    });

    test('round trip on the bounds', () {
      for (final int battery in <int>[0, 1, 50, 100, 0xFF]) {
        const List<bool> flags = <bool>[true, false];
        for (final bool connected in flags) {
          final DeviceStatusMessage message = DeviceStatusMessage(
            battery: battery,
            connected: connected,
          );
          final DeviceStatusMessage decoded =
              DeviceStatusMessage.decode(message.encode());
          expect(decoded.battery, battery);
          expect(decoded.connected, connected);
        }
      }
    });

    test('an out-of-bounds battery is rejected at encoding', () {
      expect(
        () => const DeviceStatusMessage(battery: 101, connected: true).encode(),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => const DeviceStatusMessage(battery: -1, connected: true).encode(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an invalid battery is rejected at decoding', () {
      expect(
        () => DeviceStatusMessage.decode(<int>[0x02, 200, 0x01]),
        throwsA(isA<FormatException>()),
      );
    });

    test('an invalid connection flag is rejected', () {
      expect(
        () => DeviceStatusMessage.decode(<int>[0x02, 50, 0x02]),
        throwsA(isA<FormatException>()),
      );
    });

    test('a body of the wrong length is rejected', () {
      expect(
        () => DeviceStatusMessage.decode(<int>[0x02, 50, 0x01, 0x00]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DeviceStatusMessage.decode(<int>[0x02, 50]),
        throwsA(isA<FormatException>()),
      );
    });

    test('toMessage exposes the decoded variant', () {
      final DeviceStatus message =
          const DeviceStatusMessage(battery: 42, connected: true).toMessage();
      expect(message.type, ObcMessageType.deviceStatus);
      expect(message.battery, 42);
      expect(message.connected, isTrue);
    });
  });

  group('HapticMessage', () {
    test('encoding', () {
      const HapticMessage message = HapticMessage(
        pattern: 0x02,
        duration10ms: 10,
        intensity: 200,
      );
      expect(message.encode(), <int>[0x03, 0x02, 10, 200]);
    });

    test('round trip on the bounds', () {
      for (final int value in <int>[0, 1, 128, 255]) {
        final HapticMessage message = HapticMessage(
          pattern: value,
          duration10ms: value,
          intensity: value,
        );
        final HapticMessage decoded = HapticMessage.decode(message.encode());
        expect(decoded.pattern, value);
        expect(decoded.duration10ms, value);
        expect(decoded.intensity, value);
      }
    });

    test('out-of-byte values are rejected', () {
      expect(
        () => const HapticMessage(
          pattern: 256,
          duration10ms: 1,
          intensity: 1,
        ).encode(),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => const HapticMessage(
          pattern: 1,
          duration10ms: 1,
          intensity: -1,
        ).encode(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a body of the wrong length is rejected', () {
      expect(
        () => HapticMessage.decode(<int>[0x03, 1, 2]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => HapticMessage.decode(<int>[0x03, 1, 2, 3, 4]),
        throwsA(isA<FormatException>()),
      );
    });

    test('toMessage exposes the decoded variant', () {
      final HapticCommand message = const HapticMessage(
        pattern: 1,
        duration10ms: 5,
        intensity: 90,
      ).toMessage();
      expect(message.type, ObcMessageType.haptic);
      expect(message.pattern, 1);
      expect(message.duration10ms, 5);
      expect(message.intensity, 90);
    });
  });

  group('AppInfoMessage', () {
    test('encoding of a complete frame', () {
      final AppInfoMessage message = AppInfoMessage(
        appId: 'target-a',
        appVersion: '1.2.0',
        supportedButtons: <int>[ButtonIds.shiftUp, ButtonIds.navigateUp],
      );
      expect(message.encode(), <int>[
        0x04, // type byte
        0x01, // format version
        0x08, ...'target-a'.codeUnits,
        0x05, ...'1.2.0'.codeUnits,
        0x02, ButtonIds.shiftUp, ButtonIds.navigateUp,
      ]);
    });

    test('round trip', () {
      final AppInfoMessage message = AppInfoMessage(
        appId: 'target-a',
        appVersion: '1.2.0',
        supportedButtons: ButtonIds.all,
      );
      final AppInfoMessage decoded = AppInfoMessage.decode(message.encode());
      expect(decoded.appId, 'target-a');
      expect(decoded.appVersion, '1.2.0');
      expect(decoded.supportedButtons, ButtonIds.all);
    });

    test('empty strings and empty list', () {
      final AppInfoMessage message = AppInfoMessage(
        appId: '',
        appVersion: '',
        supportedButtons: const <int>[],
      );
      expect(message.encode(), <int>[0x04, 0x01, 0x00, 0x00, 0x00]);
      final AppInfoMessage decoded = AppInfoMessage.decode(message.encode());
      expect(decoded.appId, isEmpty);
      expect(decoded.appVersion, isEmpty);
      expect(decoded.supportedButtons, isEmpty);
    });

    test('non-ASCII strings are encoded as UTF-8', () {
      final AppInfoMessage message = AppInfoMessage(
        appId: 'λμν',
        appVersion: '1.0-beta',
        supportedButtons: const <int>[ButtonIds.confirm],
      );
      final List<int> frame = message.encode();
      expect(frame[2], 6, reason: '"λμν" is 6 bytes in UTF-8');
      final AppInfoMessage decoded = AppInfoMessage.decode(frame);
      expect(decoded.appId, 'λμν');
      expect(decoded.appVersion, '1.0-beta');
    });

    test('the decoded button list is immutable', () {
      final AppInfoMessage decoded = AppInfoMessage.decode(<int>[
        0x04,
        0x01,
        0x01,
        0x61,
        0x00,
        0x00,
      ]);
      expect(decoded.appId, 'a');
      expect(decoded.supportedButtons, isEmpty);
      expect(
        () => decoded.supportedButtons.add(ButtonIds.shiftUp),
        throwsUnsupportedError,
      );
    });

    test('an over-long string is rejected at encoding', () {
      final AppInfoMessage message = AppInfoMessage(
        appId: 'a' * 256,
        appVersion: '1',
        supportedButtons: const <int>[],
      );
      expect(message.encode, throwsA(isA<ArgumentError>()));
    });

    test('too many supported buttons are rejected at encoding', () {
      final AppInfoMessage message = AppInfoMessage(
        appId: 'a',
        appVersion: '1',
        supportedButtons: List<int>.filled(256, ButtonIds.shiftUp),
      );
      expect(message.encode, throwsA(isA<ArgumentError>()));
    });

    test('an out-of-byte button identifier is rejected', () {
      final AppInfoMessage message = AppInfoMessage(
        appId: 'a',
        appVersion: '1',
        supportedButtons: <int>[0x100],
      );
      expect(message.encode, throwsA(isA<ArgumentError>()));
    });

    test('a truncated identifier is rejected at decoding', () {
      // Declared identifier length larger than the available body.
      expect(
        () => AppInfoMessage.decode(<int>[0x04, 0x01, 0x07, 0x61, 0x62, 0x63]),
        throwsA(isA<FormatException>()),
      );
      // Empty body: missing length.
      expect(
        () => AppInfoMessage.decode(<int>[0x04]),
        throwsA(isA<FormatException>()),
      );
    });

    test('an inconsistent version length is rejected', () {
      expect(
        () => AppInfoMessage.decode(<int>[
          0x04,
          0x01,
          0x01,
          0x61,
          0x09,
          0x31,
          0x00,
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('a button count larger than the body is rejected', () {
      expect(
        () => AppInfoMessage.decode(<int>[
          0x04,
          0x01,
          0x01,
          0x61,
          0x01,
          0x62,
          0x03,
          0x10,
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('leftover bytes are rejected', () {
      expect(
        () => AppInfoMessage.decode(<int>[
          0x04,
          0x01,
          0x01,
          0x61,
          0x01,
          0x62,
          0x00,
          0x99,
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('a non-UTF-8 identifier is rejected', () {
      expect(
        () => AppInfoMessage.decode(<int>[
          0x04,
          0x01,
          0x02,
          0xFF,
          0xFE,
          0x00,
          0x00,
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('an unknown format version is rejected', () {
      expect(
        () => AppInfoMessage.decode(<int>[
          0x04,
          0x02,
          0x00,
          0x00,
          0x00,
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('toMessage exposes the decoded variant', () {
      final AppInfo message = AppInfoMessage(
        appId: 'target-a',
        appVersion: '1.0',
        supportedButtons: const <int>[ButtonIds.pause],
      ).toMessage();
      expect(message.type, ObcMessageType.appInfo);
      expect(message.appId, 'target-a');
      expect(message.appVersion, '1.0');
      expect(message.supportedButtons, <int>[ButtonIds.pause]);
    });
  });
}
