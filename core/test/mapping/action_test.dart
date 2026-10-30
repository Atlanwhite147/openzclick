import 'package:openzclick_core/src/mapping/action.dart';
import 'package:test/test.dart';

void main() {
  group('Action', () {
    test('full list, ordered as in the contract', () {
      expect(Action.values, <Action>[
        Action.shiftUp,
        Action.shiftDown,
        Action.gearSet,
        Action.steerLeft,
        Action.steerRight,
        Action.navigateUp,
        Action.navigateDown,
        Action.confirm,
        Action.back,
        Action.menu,
        Action.home,
        Action.emote,
        Action.screenshot,
        Action.pause,
        Action.resume,
        Action.increaseDifficulty,
        Action.decreaseDifficulty,
        Action.changeMode,
        Action.toggleHud,
        Action.none,
      ]);
      expect(Action.values.length, 20);
    });

    test('every action has a non-empty, distinct label', () {
      final Set<String> labels = <String>{};
      for (final Action action in Action.values) {
        expect(action.label.trim(), isNotEmpty, reason: action.name);
        labels.add(action.label);
      }
      expect(labels.length, Action.values.length);
    });

    test('toggle actions are flagged as such', () {
      expect(Action.pause.isToggle, isTrue);
      expect(Action.menu.isToggle, isTrue);
      expect(Action.toggleHud.isToggle, isTrue);
      expect(Action.shiftUp.isToggle, isFalse);
      expect(Action.increaseDifficulty.isToggle, isFalse);
      expect(Action.none.isToggle, isFalse);
    });
  });
}
