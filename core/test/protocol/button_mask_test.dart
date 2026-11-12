import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

void main() {
  group('ClickButtonMask', () {
    test('a set bit means pressed, the opposite of the wire', () {
      const ClickButtonMask pressed = ClickButtonMask(up: true);
      expect(pressed.isPressed(ControllerButtonBits.plus), isTrue);
      expect(pressed.isPressed(ControllerButtonBits.b), isFalse);
      expect(pressed.isEmpty, isFalse);
      expect(ClickButtonMask.released.isEmpty, isTrue);
      expect(ClickButtonMask.released.pressedBits, isEmpty);
    });

    test('the named buttons land on the measured positions', () {
      // A typo in one offset would move a gear on the wrong button, and the
      // symptom would only show on hardware: pin the numbers themselves.
      expect(1 << ControllerButtonBits.a, 1 << 4);
      expect(1 << ControllerButtonBits.b, 1 << 5);
      expect(1 << ControllerButtonBits.y, 1 << 6);
      expect(1 << ControllerButtonBits.z, 1 << 7);
      expect(1 << ControllerButtonBits.plus, 1 << 12);
      expect(const ClickButtonMask(up: true).pressed, 1 << 12);
      expect(const ClickButtonMask(down: true).pressed, 1 << 5);
    });

    test('every position is kept, not only the two that shift', () {
      final ClickButtonMask mask = ClickButtonMask.bits(
        (1 << ControllerButtonBits.a) | (1 << ControllerButtonBits.plus),
      );
      expect(mask.pressedBits, <int>[
        ControllerButtonBits.a,
        ControllerButtonBits.plus,
      ]);
      expect(mask.up, isTrue);
      expect(mask.down, isFalse);
    });

    test('an unmeasured position is named as a number, not guessed', () {
      // The left pod's arrows have no measured offset yet. Naming them here
      // would put a guess in the diagnostics a hardware session reads.
      expect(ControllerButtonBits.nameOf(ControllerButtonBits.plus), 'plus');
      expect(ControllerButtonBits.nameOf(17), 'bit 17');
      expect(
        ClickButtonMask.bits(1 << 17).toString(),
        'ClickButtonMask(bit 17)',
      );
      expect(ClickButtonMask.released.toString(), 'ClickButtonMask(none)');
    });

    test('two frames that say the same thing are the same state', () {
      expect(
        ClickButtonMask.bits(1 << ControllerButtonBits.plus),
        const ClickButtonMask(up: true),
      );
      expect(
          ClickButtonMask.bits(0).hashCode, ClickButtonMask.released.hashCode);
      expect(
        ClickButtonMask.bits(1 << 3),
        isNot(ClickButtonMask.released),
      );
    });
  });

  group('changed bits', () {
    test('a press is what the previous frame did not already say', () {
      // The frame the pods mirror: the right pod repeats the left one's state,
      // and acting on the state rather than on its change counts the press
      // twice.
      const ClickButtonMask rest = ClickButtonMask.released;
      const ClickButtonMask held = ClickButtonMask(up: true);

      expect(held.newlyPressedSince(rest), held);
      expect(held.newlyPressedSince(held).isEmpty, isTrue);
    });

    test('a released button appears as a release, not as a press', () {
      const ClickButtonMask held = ClickButtonMask(up: true, down: true);
      const ClickButtonMask partial = ClickButtonMask(down: true);

      expect(partial.newlyPressedSince(held).isEmpty, isTrue);
      expect(
        partial.releasedSince(held),
        const ClickButtonMask(up: true),
      );
    });

    test('a button pressed while another is held is still a new press', () {
      const ClickButtonMask held = ClickButtonMask(up: true);
      const ClickButtonMask both = ClickButtonMask(up: true, down: true);

      expect(both.newlyPressedSince(held), const ClickButtonMask(down: true));
    });

    test('the positions the mask does not touch are never reported', () {
      final ClickButtonMask y =
          ClickButtonMask.bits(1 << ControllerButtonBits.y);
      expect(y.newlyPressedSince(ClickButtonMask.released), y);
      expect(y.releasedSince(y).isEmpty, isTrue);
    });
  });

  group('the decoded frame', () {
    test('a frame wider than 32 bits reports no phantom press', () {
      // Only a 32-bit window is described by the specification. A firmware that
      // sent a wider varint must not invent positions 32 and above.
      final ClickButtonMask? buttons = ControllerCodec.parseButtonMask(
        <int>[0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01],
      );
      expect(buttons, isNotNull);
      expect(buttons!.pressedBits, isEmpty);
    });

    test('a mask at rest is no press at all', () {
      final ClickButtonMask? buttons = ControllerCodec.parseButtonMask(
        <int>[0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F],
      );
      expect(buttons, ClickButtonMask.released);
    });
  });
}
