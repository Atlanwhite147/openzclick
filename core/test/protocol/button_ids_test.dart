import 'package:openzclick_core/src/protocol/openzclick_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ButtonIds - contract values', () {
    test('shifting identifiers are 0x01..0x05', () {
      expect(ButtonIds.shiftUp, 0x01);
      expect(ButtonIds.shiftDown, 0x02);
      expect(ButtonIds.gearSet, 0x03);
      expect(ButtonIds.chainringSet, 0x04);
      expect(ButtonIds.cassetteSet, 0x05);
    });

    test('navigation identifiers are 0x10..0x17', () {
      expect(ButtonIds.navigateUp, 0x10);
      expect(ButtonIds.navigateDown, 0x11);
      expect(ButtonIds.navigateLeft, 0x12);
      expect(ButtonIds.navigateRight, 0x13);
      expect(ButtonIds.confirm, 0x14);
      expect(ButtonIds.back, 0x15);
      expect(ButtonIds.menu, 0x16);
      expect(ButtonIds.home, 0x17);
    });

    test('steering and brake identifiers are 0x18..0x1B', () {
      expect(ButtonIds.steerLeft, 0x18);
      expect(ButtonIds.steerRight, 0x19);
      expect(ButtonIds.brake, 0x1A);
      expect(ButtonIds.steeringAngle, 0x1B);
    });

    test('social and capture identifiers are 0x20 and 0x24', () {
      expect(ButtonIds.emote, 0x20);
      expect(ButtonIds.screenshot, 0x24);
    });

    test('session identifiers are 0x30..0x38', () {
      expect(ButtonIds.increaseDifficulty, 0x30);
      expect(ButtonIds.decreaseDifficulty, 0x31);
      expect(ButtonIds.skipInterval, 0x32);
      expect(ButtonIds.pause, 0x33);
      expect(ButtonIds.resume, 0x34);
      expect(ButtonIds.lap, 0x35);
      expect(ButtonIds.changeMode, 0x38);
    });

    test('the display identifier is 0x44', () {
      expect(ButtonIds.hudToggle, 0x44);
    });
  });

  group('ButtonIds - table consistency', () {
    test('the "all" list holds the 27 contract identifiers', () {
      expect(ButtonIds.all, hasLength(27));
      expect(ButtonIds.all, <int>[
        ButtonIds.shiftUp,
        ButtonIds.shiftDown,
        ButtonIds.gearSet,
        ButtonIds.chainringSet,
        ButtonIds.cassetteSet,
        ButtonIds.navigateUp,
        ButtonIds.navigateDown,
        ButtonIds.navigateLeft,
        ButtonIds.navigateRight,
        ButtonIds.confirm,
        ButtonIds.back,
        ButtonIds.menu,
        ButtonIds.home,
        ButtonIds.steerLeft,
        ButtonIds.steerRight,
        ButtonIds.brake,
        ButtonIds.steeringAngle,
        ButtonIds.emote,
        ButtonIds.screenshot,
        ButtonIds.increaseDifficulty,
        ButtonIds.decreaseDifficulty,
        ButtonIds.skipInterval,
        ButtonIds.pause,
        ButtonIds.resume,
        ButtonIds.lap,
        ButtonIds.changeMode,
        ButtonIds.hudToggle,
      ]);
    });

    test('identifiers are unique', () {
      expect(ButtonIds.all.toSet(), hasLength(ButtonIds.all.length));
      expect(ButtonIds.names.keys.toSet(), hasLength(ButtonIds.all.length));
    });

    test('the "all" list is sorted by ascending value', () {
      final List<int> sorted = ButtonIds.all.toList()..sort();
      expect(ButtonIds.all, sorted);
    });

    test('each identifier fits in one byte, excluding 0x00 and 0xFF', () {
      for (final int id in ButtonIds.all) {
        expect(id, greaterThan(0x00));
        expect(id, lessThan(0xFF));
      }
    });

    test('the name table covers exactly the "all" list', () {
      expect(ButtonIds.names.keys.toSet(), ButtonIds.all.toSet());
    });

    test('each name is the expected English code identifier', () {
      expect(ButtonIds.names[ButtonIds.shiftUp], 'shiftUp');
      expect(ButtonIds.names[ButtonIds.shiftDown], 'shiftDown');
      expect(ButtonIds.names[ButtonIds.gearSet], 'gearSet');
      expect(ButtonIds.names[ButtonIds.chainringSet], 'chainringSet');
      expect(ButtonIds.names[ButtonIds.cassetteSet], 'cassetteSet');
      expect(ButtonIds.names[ButtonIds.navigateUp], 'navigateUp');
      expect(ButtonIds.names[ButtonIds.navigateDown], 'navigateDown');
      expect(ButtonIds.names[ButtonIds.navigateLeft], 'navigateLeft');
      expect(ButtonIds.names[ButtonIds.navigateRight], 'navigateRight');
      expect(ButtonIds.names[ButtonIds.confirm], 'confirm');
      expect(ButtonIds.names[ButtonIds.back], 'back');
      expect(ButtonIds.names[ButtonIds.menu], 'menu');
      expect(ButtonIds.names[ButtonIds.home], 'home');
      expect(ButtonIds.names[ButtonIds.steerLeft], 'steerLeft');
      expect(ButtonIds.names[ButtonIds.steerRight], 'steerRight');
      expect(ButtonIds.names[ButtonIds.brake], 'brake');
      expect(ButtonIds.names[ButtonIds.steeringAngle], 'steeringAngle');
      expect(ButtonIds.names[ButtonIds.emote], 'emote');
      expect(ButtonIds.names[ButtonIds.screenshot], 'screenshot');
      expect(
        ButtonIds.names[ButtonIds.increaseDifficulty],
        'increaseDifficulty',
      );
      expect(
        ButtonIds.names[ButtonIds.decreaseDifficulty],
        'decreaseDifficulty',
      );
      expect(ButtonIds.names[ButtonIds.skipInterval], 'skipInterval');
      expect(ButtonIds.names[ButtonIds.pause], 'pause');
      expect(ButtonIds.names[ButtonIds.resume], 'resume');
      expect(ButtonIds.names[ButtonIds.lap], 'lap');
      expect(ButtonIds.names[ButtonIds.changeMode], 'changeMode');
      expect(ButtonIds.names[ButtonIds.hudToggle], 'hudToggle');
    });
  });

  group('ButtonIds - helpers', () {
    test('isKnown recognizes the contract identifiers', () {
      for (final int id in ButtonIds.all) {
        expect(ButtonIds.isKnown(id), isTrue, reason: 'id 0x$id');
      }
    });

    test('isKnown rejects bytes outside the table', () {
      expect(ButtonIds.isKnown(0x00), isFalse);
      expect(ButtonIds.isKnown(0x06), isFalse);
      expect(ButtonIds.isKnown(0x1C), isFalse);
      expect(ButtonIds.isKnown(0x25), isFalse);
      expect(ButtonIds.isKnown(0x45), isFalse);
      expect(ButtonIds.isKnown(0xFF), isFalse);
    });

    test('nameOf returns the name or null', () {
      expect(ButtonIds.nameOf(ButtonIds.confirm), 'confirm');
      expect(ButtonIds.nameOf(0x7F), isNull);
    });

    test('isShifting only covers the shifting range', () {
      expect(ButtonIds.isShifting(ButtonIds.shiftUp), isTrue);
      expect(ButtonIds.isShifting(ButtonIds.shiftDown), isTrue);
      expect(ButtonIds.isShifting(ButtonIds.gearSet), isTrue);
      expect(ButtonIds.isShifting(ButtonIds.chainringSet), isTrue);
      expect(ButtonIds.isShifting(ButtonIds.cassetteSet), isTrue);
      expect(ButtonIds.isShifting(ButtonIds.navigateUp), isFalse);
      expect(ButtonIds.isShifting(ButtonIds.confirm), isFalse);
      expect(ButtonIds.isShifting(0x00), isFalse);
    });

    test('isAnalog only covers analog-value commands', () {
      expect(ButtonIds.isAnalog(ButtonIds.steerLeft), isTrue);
      expect(ButtonIds.isAnalog(ButtonIds.steerRight), isTrue);
      expect(ButtonIds.isAnalog(ButtonIds.brake), isTrue);
      expect(ButtonIds.isAnalog(ButtonIds.steeringAngle), isTrue);
      expect(ButtonIds.isAnalog(ButtonIds.confirm), isFalse);
      expect(ButtonIds.isAnalog(ButtonIds.shiftUp), isFalse);
      expect(ButtonIds.isAnalog(ButtonIds.hudToggle), isFalse);
    });
  });
}
