import 'package:openzclick_core/src/protocol/controller_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ControllerHandshake', () {
    test('plain request is the RideOn marker', () {
      expect(ControllerHandshake.plainRequest(), <int>[82, 105, 100, 101, 79, 110]);
    });

    test('encrypted request appends the 64-byte public key', () {
      final List<int> key = List<int>.generate(64, (int i) => i);
      final List<int> frame = ControllerHandshake.encryptedRequest(key);
      expect(frame.length, 8 + 64);
      expect(frame.sublist(0, 6), ControllerHandshake.rideOn);
      expect(frame.sublist(6, 8), ControllerHandshake.requestStart);
      expect(frame.sublist(8), key);
    });

    test('encrypted request rejects a wrong key length', () {
      expect(
        () => ControllerHandshake.encryptedRequest(<int>[1, 2, 3]),
        throwsArgumentError,
      );
    });

    test('parses a device public key response', () {
      final List<int> key = List<int>.generate(64, (int i) => 255 - i);
      final List<int> frame = <int>[
        ...ControllerHandshake.rideOn,
        ...ControllerHandshake.responseStart,
        ...key,
      ];
      expect(ControllerHandshake.parseDevicePublicKey(frame), key);
    });

    test('rejects a response with a wrong prefix', () {
      final List<int> frame = <int>[0, 0, 0, 0, 0, 0, 1, 3, ...List<int>.filled(64, 7)];
      expect(ControllerHandshake.parseDevicePublicKey(frame), isNull);
    });

    test('rejects a response with a wrong length', () {
      final List<int> frame = <int>[
        ...ControllerHandshake.rideOn,
        ...ControllerHandshake.responseStart,
        1, 2, 3,
      ];
      expect(ControllerHandshake.parseDevicePublicKey(frame), isNull);
    });
  });

  group('ControllerCodec button notifications', () {
    // Protobuf: tag = (field << 3) | wireType, both fields are varints.
    List<int> notification({int? up, int? down}) => <int>[
          if (up != null) ...<int>[0x08, up],
          if (down != null) ...<int>[0x10, down],
        ];

    test('field 1 at zero means the up button is pressed', () {
      final ClickButtons? buttons =
          ControllerCodec.parseClickNotification(notification(up: 0));
      expect(buttons, const ClickButtons(up: true, down: false));
    });

    test('field 2 at zero means the down button is pressed', () {
      final ClickButtons? buttons =
          ControllerCodec.parseClickNotification(notification(down: 0));
      expect(buttons, const ClickButtons(up: false, down: true));
    });

    test('non-zero values mean released', () {
      final ClickButtons? buttons =
          ControllerCodec.parseClickNotification(notification(up: 1, down: 2));
      expect(buttons, ClickButtons.released);
    });

    test('both buttons can be pressed at once', () {
      final ClickButtons? buttons =
          ControllerCodec.parseClickNotification(notification(up: 0, down: 0));
      expect(buttons, const ClickButtons(up: true, down: true));
    });

    test('unknown fields are ignored', () {
      final List<int> body = <int>[0x08, 0, 0x18, 5, 0x20, 9];
      expect(
        ControllerCodec.parseClickNotification(body),
        const ClickButtons(up: true, down: false),
      );
    });

    test('an empty body means nothing pressed', () {
      expect(ControllerCodec.parseClickNotification(<int>[]), ClickButtons.released);
    });
  });

  group('ControllerCodec frames', () {
    test('decodes a click frame', () {
      final ControllerMessage? message = ControllerCodec.decode(<int>[
        ControllerMessageType.click,
        0x08,
        0,
      ]);
      expect(message, isA<ClickMessage>());
      expect((message! as ClickMessage).buttons.up, isTrue);
    });

    test('decodes a battery frame', () {
      final ControllerMessage? message =
          ControllerCodec.decode(<int>[ControllerMessageType.battery, 87]);
      expect((message! as BatteryMessage).percent, 87);
    });

    test('reports empty and disconnect notices', () {
      expect(
        (ControllerCodec.decode(<int>[ControllerMessageType.empty])! as ControlMessage).type,
        21,
      );
      expect(
        (ControllerCodec.decode(<int>[ControllerMessageType.disconnect])! as ControlMessage).type,
        0xFE,
      );
    });

    test('returns null on an empty frame', () {
      expect(ControllerCodec.decode(<int>[]), isNull);
    });

    test('returns null on an unknown type', () {
      expect(ControllerCodec.decode(<int>[0x99, 1, 2]), isNull);
    });

    test('returns null on a truncated battery frame', () {
      expect(ControllerCodec.decode(<int>[ControllerMessageType.battery]), isNull);
    });
  });
}
