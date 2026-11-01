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
}
