import 'package:openzclick_core/src/protocol/controller_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ControllerHandshake', () {
    test('plain request is the RideOn marker', () {
      expect(ControllerHandshake.plainRequest(),
          <int>[82, 105, 100, 101, 79, 110]);
    });

    // The opening frame is the answer the pod itself gives when it grants a
    // plain session: `52 69 64 65 4F 6E 02 03 C8 00 …`, measured on a Click v2,
    // firmware 1.1.0. zwiftboard opens with exactly these eight bytes.
    test('a plain session opens with RideOn then 02 03', () {
      expect(ControllerHandshake.plainStart(),
          <int>[82, 105, 100, 101, 79, 110, 0x02, 0x03]);
    });

    test('the activation starts with the granted plain session', () {
      final List<List<int>> frames = ControllerHandshake.activationSequence();
      expect(frames.length, 3);
      expect(frames.first, ControllerHandshake.plainStart());
      expect(frames[1], ControllerHandshake.activationFirst);
      expect(frames.last, ControllerHandshake.activationSecond);
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
      final List<int> frame = <int>[
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        3,
        ...List<int>.filled(64, 7)
      ];
      expect(ControllerHandshake.parseDevicePublicKey(frame), isNull);
    });

    test('rejects a response with a wrong length', () {
      final List<int> frame = <int>[
        ...ControllerHandshake.rideOn,
        ...ControllerHandshake.responseStart,
        1,
        2,
        3,
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
      final ClickButtonMask? buttons =
          ControllerCodec.parseClickNotification(notification(up: 0));
      expect(buttons, const ClickButtonMask(up: true, down: false));
    });

    test('field 2 at zero means the down button is pressed', () {
      final ClickButtonMask? buttons =
          ControllerCodec.parseClickNotification(notification(down: 0));
      expect(buttons, const ClickButtonMask(up: false, down: true));
    });

    test('non-zero values mean released', () {
      final ClickButtonMask? buttons =
          ControllerCodec.parseClickNotification(notification(up: 1, down: 2));
      expect(buttons, ClickButtonMask.released);
    });

    test('both buttons can be pressed at once', () {
      final ClickButtonMask? buttons =
          ControllerCodec.parseClickNotification(notification(up: 0, down: 0));
      expect(buttons, const ClickButtonMask(up: true, down: true));
    });

    test('unknown fields are ignored', () {
      final List<int> body = <int>[0x08, 0, 0x18, 5, 0x20, 9];
      expect(
        ControllerCodec.parseClickNotification(body),
        const ClickButtonMask(up: true, down: false),
      );
    });

    test('an empty body means nothing pressed', () {
      expect(ControllerCodec.parseClickNotification(<int>[]),
          ClickButtonMask.released);
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

    // Frames copied byte for byte from the application's own device report, on
    // a Click v2, firmware 1.1.0, serial 0A-34C459DD3C3D, 2026-11-12. They are
    // what a real pod sends, not a reading of the specification.
    group('measured frames', () {
      List<int> frame(String hex) => <int>[
            for (final String byte in hex.split(' '))
              int.parse(byte, radix: 16),
          ];

      test('the resting frame presses nothing', () {
        final ClickMessage message =
            ControllerCodec.decode(frame('23 08 ff ff ff ff 0f'))!
                as ClickMessage;
        expect(message.buttons.isEmpty, isTrue);
        expect(message.buttons.toString(), 'ClickButtonMask(none)');
      });

      test('a held Z is bit 7 and nothing else', () {
        final ClickMessage message =
            ControllerCodec.decode(frame('23 08 ff fe ff ff 0f'))!
                as ClickMessage;
        expect(message.buttons.pressedBits, <int>[ControllerButtonBits.z]);
        expect(message.buttons.toString(), 'ClickButtonMask(z)');
      });

      test('a held plus is bit 12 and nothing else', () {
        final ClickMessage message =
            ControllerCodec.decode(frame('23 08 ff df ff ff 0f'))!
                as ClickMessage;
        expect(message.buttons.pressedBits, <int>[ControllerButtonBits.plus]);
        expect(message.buttons.up, isTrue);
      });
    });

    test('decodes a battery frame', () {
      final ControllerMessage? message =
          ControllerCodec.decode(<int>[ControllerMessageType.battery, 87]);
      expect((message! as BatteryMessage).percent, 87);
    });

    test('reports empty and disconnect notices', () {
      expect(
        (ControllerCodec.decode(<int>[ControllerMessageType.empty])!
                as ControlMessage)
            .type,
        21,
      );
      expect(
        (ControllerCodec.decode(<int>[ControllerMessageType.disconnect])!
                as ControlMessage)
            .type,
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
      expect(
          ControllerCodec.decode(<int>[ControllerMessageType.battery]), isNull);
    });
  });
}
