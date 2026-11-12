import 'package:openzclick_core/src/protocol/openzclick_protocol.dart';
import 'package:test/test.dart';

/// Valid button state frame: a shift up press.
List<int> buttonFrame() => ButtonStateMessage(<int, int>{
      ButtonIds.shiftUp: 1,
    }).encode();

/// Valid device status frame.
List<int> statusFrame() =>
    const DeviceStatusMessage(battery: 85, connected: true).encode();

/// Valid haptic frame.
List<int> hapticFrame() => const HapticMessage(
      pattern: 1,
      duration10ms: 2,
      intensity: 3,
    ).encode();

void main() {
  group('ObcCodec.tryDecode - incomplete cases', () {
    test('an empty buffer yields nothing', () {
      expect(ObcCodec.tryDecode(<int>[]), isNull);
      expect(ObcCodec.discardCount(<int>[]), 0);
    });

    test('a lone type byte waits for its body', () {
      expect(ObcCodec.tryDecode(<int>[0x02]), isNull);
      expect(ObcCodec.discardCount(<int>[0x02]), 0);
    });

    test('a partially received body waits for more', () {
      final List<int> partial = statusFrame().sublist(0, 2);
      expect(ObcCodec.tryDecode(partial), isNull);
      expect(ObcCodec.discardCount(partial), 0);
    });

    test('the frame decodes once the buffer is completed', () {
      final List<int> frame = statusFrame();
      expect(ObcCodec.tryDecode(frame.sublist(0, 2)), isNull);
      final ({ObcMessage message, int consumed})? result =
          ObcCodec.tryDecode(frame);
      expect(result, isNotNull);
      expect(result!.consumed, frame.length);
    });
  });

  group('ObcCodec.tryDecode - complete frames', () {
    test('button state', () {
      final List<int> frame = buttonFrame();
      final result = ObcCodec.tryDecode(frame);
      expect(result, isNotNull);
      expect(result!.consumed, frame.length);
      final ObcMessage message = result.message;
      expect(message, isA<ButtonState>());
      expect(message.type, ObcMessageType.buttonState);
      expect(
        (message as ButtonState).buttons,
        <int, int>{ButtonIds.shiftUp: 1},
      );
    });

    test('device status', () {
      final result = ObcCodec.tryDecode(statusFrame());
      expect(result, isNotNull);
      expect(result!.consumed, 3);
      final ObcMessage message = result.message;
      expect(message, isA<DeviceStatus>());
      final DeviceStatus status = message as DeviceStatus;
      expect(status.battery, 85);
      expect(status.connected, isTrue);
      expect(status.type, ObcMessageType.deviceStatus);
    });

    test('haptic command', () {
      final result = ObcCodec.tryDecode(hapticFrame());
      expect(result, isNotNull);
      expect(result!.consumed, 4);
      final HapticCommand command = result.message as HapticCommand;
      expect(command.pattern, 1);
      expect(command.duration10ms, 2);
      expect(command.intensity, 3);
    });

    test('app info', () {
      final List<int> frame = AppInfoMessage(
        appId: 'target-a',
        appVersion: '1.0',
        supportedButtons: const <int>[ButtonIds.shiftUp, ButtonIds.confirm],
      ).encode();
      final result = ObcCodec.tryDecode(frame);
      expect(result, isNotNull);
      expect(result!.consumed, frame.length);
      final AppInfo info = result.message as AppInfo;
      expect(info.appId, 'target-a');
      expect(info.appVersion, '1.0');
      expect(
          info.supportedButtons, <int>[ButtonIds.shiftUp, ButtonIds.confirm]);
      expect(info.type, ObcMessageType.appInfo);
    });

    test('a complete frame leaves nothing to drop', () {
      expect(ObcCodec.discardCount(statusFrame()), 0);
    });
  });

  group('ObcCodec.tryDecode - resynchronization', () {
    test('leading unknown bytes are ignored', () {
      final List<int> frame = statusFrame();
      final List<int> buffer = <int>[0xAA, 0x55, 0x00, ...frame];
      final result = ObcCodec.tryDecode(buffer);
      expect(result, isNotNull);
      expect(result!.consumed, 3 + frame.length);
      expect(result.message, isA<DeviceStatus>());
    });

    test('a buffer with no known type is entirely droppable', () {
      final List<int> buffer = <int>[0xAA, 0x55, 0x99];
      expect(ObcCodec.tryDecode(buffer), isNull);
      expect(ObcCodec.discardCount(buffer), 3);
    });

    test('bytes preceding an incomplete frame can be dropped', () {
      final List<int> buffer = <int>[0xFF, 0x02, 0x32];
      expect(ObcCodec.tryDecode(buffer), isNull);
      expect(ObcCodec.discardCount(buffer), 1);
    });

    test('an impossible body length is skipped, the stream continues', () {
      // 0x02 needs exactly two body bytes: three of them cannot be a status.
      final List<int> buffer = <int>[0x02, 0x01, 0x05, 0x07];
      final result = ObcCodec.tryDecode(buffer);
      expect(result, isNotNull);
      expect(result!.consumed, 4);
      expect(result.message, isA<ButtonState>());
    });

    test('an isolated unknown type is dropped', () {
      expect(ObcCodec.tryDecode(<int>[0x05]), isNull);
      expect(ObcCodec.discardCount(<int>[0x05]), 1);
    });

    test('a 19-byte 0x01 frame is accepted as a whole', () {
      final Map<int, int> buttons = <int, int>{
        for (int i = 0; i < ButtonStateMessage.maxButtons; i++) 0x10 + i: 1,
      };
      final List<int> frame = ButtonStateMessage(buttons).encode();
      expect(frame, hasLength(19));
      final result = ObcCodec.tryDecode(frame);
      expect(result, isNotNull);
      expect(result!.consumed, 19);
      expect((result.message as ButtonState).buttons, buttons);
    });

    test('a button frame beyond the maximum never locks the stream', () {
      final List<int> oversized = <int>[
        0x01,
        for (int i = 0; i < 11; i++) ...<int>[0x10 + i, 0x01],
      ];
      final result = ObcCodec.tryDecode(oversized);
      expect(result, isNotNull);
      expect(
        (result!.message as ButtonState).buttons,
        hasLength(lessThanOrEqualTo(ButtonStateMessage.maxButtons)),
      );
    });
  });

  group('ObcCodec.tryDecode - continuous stream', () {
    test('two successive frames decode one after the other', () {
      final List<int> first = statusFrame();
      final List<int> second = hapticFrame();
      final List<int> buffer = <int>[...first, ...second];

      final firstResult = ObcCodec.tryDecode(buffer)!;
      expect(firstResult.message, isA<DeviceStatus>());
      expect(firstResult.consumed, first.length);

      final List<int> rest = buffer.sublist(firstResult.consumed);
      final secondResult = ObcCodec.tryDecode(rest)!;
      expect(secondResult.message, isA<HapticCommand>());
      expect(secondResult.consumed, second.length);
      expect(rest.sublist(secondResult.consumed), isEmpty);
    });

    test('two button frames coalesced in one read stay apart', () {
      final List<int> first =
          ButtonStateMessage(<int, int>{ButtonIds.shiftUp: 1}).encode();
      final List<int> second =
          ButtonStateMessage(<int, int>{ButtonIds.shiftDown: 1}).encode();
      final List<int> buffer = <int>[...first, ...second];

      final firstResult = ObcCodec.tryDecode(buffer)!;
      expect(firstResult.consumed, first.length);
      expect(
        (firstResult.message as ButtonState).buttons,
        <int, int>{ButtonIds.shiftUp: 1},
      );

      final secondResult =
          ObcCodec.tryDecode(buffer.sublist(firstResult.consumed))!;
      expect(
        (secondResult.message as ButtonState).buttons,
        <int, int>{ButtonIds.shiftDown: 1},
      );
    });

    test('partial frames at the end of the stream are kept', () {
      final List<int> first = buttonFrame();
      final List<int> second = statusFrame();
      final List<int> buffer = <int>[
        ...first,
        ...second.sublist(0, 1),
      ];
      final firstResult = ObcCodec.tryDecode(buffer)!;
      expect(firstResult.consumed, first.length);
      final List<int> rest = buffer.sublist(firstResult.consumed);
      expect(ObcCodec.tryDecode(rest), isNull);
      expect(ObcCodec.discardCount(rest), 0,
          reason: 'the 0x02 frame is on its way');
    });

    test('a stream of four different types drains completely', () {
      final List<int> buffer = <int>[
        ...buttonFrame(),
        ...statusFrame(),
        ...hapticFrame(),
        ...AppInfoMessage(
          appId: 'target-a',
          appVersion: '2.0',
          supportedButtons: const <int>[ButtonIds.confirm],
        ).encode(),
      ];
      final List<ObcMessageType> seen = <ObcMessageType>[];
      List<int> pending = buffer;
      while (pending.isNotEmpty) {
        final result = ObcCodec.tryDecode(pending);
        if (result == null) {
          break;
        }
        seen.add(result.message.type);
        pending = pending.sublist(result.consumed);
      }
      expect(pending, isEmpty);
      expect(seen, <ObcMessageType>[
        ObcMessageType.buttonState,
        ObcMessageType.deviceStatus,
        ObcMessageType.haptic,
        ObcMessageType.appInfo,
      ]);
    });
  });

  group('button mask frames measured on a Click v2', () {
    // Frames captured from the controller over WinRT, firmware 1.1.0: the
    // notification is `23 08 <varint>`, every mask bit set at rest and the bit
    // of the pressed button cleared. The old decoder expected type 55 and threw
    // all of these away, which is why presses reached the application as
    // nothing at all.
    ControllerMessage? decodeFrame(List<int> frame) =>
        ControllerCodec.decode(frame);

    test('the up button clears bit 12', () {
      final ControllerMessage? message = decodeFrame(
        <int>[0x23, 0x08, 0xff, 0xdf, 0xff, 0xff, 0x0f],
      );
      expect(message, isA<ClickMessage>());
      expect(
          (message! as ClickMessage).buttons,
          const ClickButtonMask(
            up: true,
            down: false,
          ));
    });

    test('the down button clears bit 5', () {
      final ControllerMessage? message = decodeFrame(
        <int>[0x23, 0x08, 0xdf, 0xff, 0xff, 0xff, 0x0f],
      );
      expect(
          (message! as ClickMessage).buttons,
          const ClickButtonMask(
            up: false,
            down: true,
          ));
    });

    test('an all-ones mask is a released controller', () {
      final ControllerMessage? message = decodeFrame(
        <int>[0x23, 0x08, 0xff, 0xff, 0xff, 0xff, 0x0f],
      );
      expect((message! as ClickMessage).buttons, ClickButtonMask.released);
    });

    test('a mask without field 1 is not read as a press', () {
      expect(decodeFrame(<int>[0x23, 0x10, 0x00]), isNull);
    });

    test('Y, Z and A do not move a gear, but the frame keeps them', () {
      // Each bit was measured alone: Y clears 6, Z clears 7, A clears 4. They
      // are not the buttons the rider shifts with, so a press must reach the
      // application as no gear change. The mask still carries the position: a
      // frame reduced to two booleans threw away the only evidence the left
      // pod's arrows would give.
      for (final int bit in <int>[
        ControllerButtonBits.y,
        ControllerButtonBits.z,
        ControllerButtonBits.a,
      ]) {
        final int mask = 0xFFFFFFFF & ~(1 << bit);
        final ClickButtonMask? buttons = ControllerCodec.parseButtonMask(
          <int>[0x08, ..._varint(mask)],
        );
        expect(buttons!.isPressed(bit), isTrue, reason: 'bit $bit');
        expect(buttons.up, isFalse, reason: 'bit $bit');
        expect(buttons.down, isFalse, reason: 'bit $bit');
      }
    });

    test('the plus button is the one that shifts up', () {
      final int mask = 0xFFFFFFFF & ~(1 << ControllerButtonBits.plus);
      final ClickButtonMask? buttons = ControllerCodec.parseButtonMask(
        <int>[0x08, ..._varint(mask)],
      );
      expect(buttons, const ClickButtonMask(up: true, down: false));
    });

    test('the B button is the one that shifts down', () {
      final int mask = 0xFFFFFFFF & ~(1 << ControllerButtonBits.b);
      final ClickButtonMask? buttons = ControllerCodec.parseButtonMask(
        <int>[0x08, ..._varint(mask)],
      );
      expect(buttons, const ClickButtonMask(up: false, down: true));
    });
  });
}

/// Protobuf varint encoding, used to rebuild the masks the controller sent.
List<int> _varint(int value) {
  final List<int> out = <int>[];
  int v = value;
  while (v > 0x7F) {
    out.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}
