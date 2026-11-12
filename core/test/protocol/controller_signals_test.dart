import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

void main() {
  group('the controller announcing that it stopped', () {
    test('both stop frames are recognised', () {
      // `clickbridge` listens for exactly these two before it restarts the unit.
      // Missing one means waiting for a pod that has already gone quiet, which
      // costs the rest of the ride.
      expect(
        ControllerSignals.stopped(<int>[0xFF, 0x05, 0x00, 0xEA, 0x05]),
        isTrue,
      );
      expect(
        ControllerSignals.stopped(<int>[0xFF, 0x05, 0x00, 0xFA, 0x05]),
        isTrue,
      );
    });

    test('a longer frame that merely starts with it counts too', () {
      // The announcement arrives padded with the fields that follow it.
      expect(
        ControllerSignals.stopped(<int>[0xFF, 0x05, 0x00, 0xEA, 0x05, 0x00]),
        isTrue,
      );
    });

    test('a button frame is not a stop', () {
      // The idle frame sits on the other channel and repeats four times a press:
      // reading it as a stop would restart the pod on every button.
      expect(
        ControllerSignals.stopped(
            <int>[0x23, 0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F]),
        isFalse,
      );
      expect(ControllerSignals.stopped(<int>[0xFF, 0x05]), isFalse);
      expect(ControllerSignals.stopped(<int>[]), isFalse);
    });

    test('the restart frame is one byte, and the arming frame three', () {
      expect(ControllerHandshake.reset, <int>[0x18]);
      expect(ControllerHandshake.startAfterOpening, <int>[0xFF, 0x04, 0x00]);
    });
  });
}
