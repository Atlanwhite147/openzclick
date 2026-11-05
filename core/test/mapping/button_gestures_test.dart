import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

void main() {
  late List<Action> actions;

  ButtonGestureDetector detector({
    GestureMode mode = GestureMode.immediate,
    GestureBindings up = defaultUpBindings,
    GestureBindings down = defaultDownBindings,
    Duration doubleTapWindow = const Duration(milliseconds: 40),
    Duration longPressAfter = const Duration(milliseconds: 120),
  }) {
    final ButtonGestureDetector made = ButtonGestureDetector(
      onAction: actions.add,
      mode: mode,
      up: up,
      down: down,
      doubleTapWindow: doubleTapWindow,
      longPressAfter: longPressAfter,
    );
    addTearDown(made.dispose);
    return made;
  }

  setUp(() => actions = <Action>[]);

  group('immediate mode', () {
    test('a press shifts at once, without waiting for a window', () {
      // The whole point of this mode: a gear change is the gesture a rider
      // repeats most, so it must not cost a third of a second.
      detector().feed(const ClickButtons(up: true, down: false));
      expect(actions, <Action>[Action.shiftUp]);
    });

    test('the second press of a double tap adds the direction choice', () {
      final ButtonGestureDetector g = detector();
      g.feed(const ClickButtons(up: true, down: false));
      g.feed(ClickButtons.released);
      g.feed(const ClickButtons(up: true, down: false));
      g.feed(ClickButtons.released);
      expect(actions, <Action>[Action.shiftUp, Action.steerLeft]);
    });

    test('two presses further apart are two shifts', () async {
      final ButtonGestureDetector g = detector();
      g.feed(const ClickButtons(up: true, down: false));
      g.feed(ClickButtons.released);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      g.feed(const ClickButtons(up: true, down: false));
      g.feed(ClickButtons.released);
      expect(actions, <Action>[Action.shiftUp, Action.shiftUp]);
    });

    test('the down button keeps its own gestures', () {
      final ButtonGestureDetector g = detector();
      g.feed(const ClickButtons(up: false, down: true));
      g.feed(const ClickButtons(up: false, down: true));
      expect(actions, <Action>[Action.shiftDown]);
      g.feed(ClickButtons.released);
      g.feed(const ClickButtons(up: false, down: true));
      expect(actions, <Action>[Action.shiftDown, Action.steerRight]);
    });
  });

  group('deferred mode', () {
    test('a single tap waits for the window, then acts', () async {
      final ButtonGestureDetector g = detector(mode: GestureMode.deferred);
      g.feed(const ClickButtons(up: true, down: false));
      g.feed(ClickButtons.released);
      expect(actions, isEmpty, reason: 'decision is deferred');
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(actions, <Action>[Action.shiftUp]);
    });

    test('a double tap produces the direction choice only', () async {
      final ButtonGestureDetector g = detector(mode: GestureMode.deferred);
      g.feed(const ClickButtons(up: true, down: false));
      g.feed(ClickButtons.released);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      g.feed(const ClickButtons(up: true, down: false));
      g.feed(ClickButtons.released);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(actions, <Action>[Action.steerLeft]);
    });

    test('both buttons pressed together are two independent decisions',
        () async {
      final ButtonGestureDetector g = detector(mode: GestureMode.deferred);
      g.feed(const ClickButtons(up: true, down: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      g.feed(ClickButtons.released);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(actions, <Action>[Action.shiftUp, Action.shiftDown]);
    });
  });

  group('long press', () {
    test('in deferred mode a hold produces only its long-press action',
        () async {
      // The pair that makes sense: with the tap deferred, the hold can cancel
      // it, so a rider holding for the menu does not shift first.
      final ButtonGestureDetector g = detector(
        mode: GestureMode.deferred,
        up: defaultUpBindings.withLongPress(Action.menu),
      );
      g.feed(const ClickButtons(up: true, down: false));
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(actions, <Action>[Action.menu]);
      g.feed(ClickButtons.released);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(actions, <Action>[Action.menu], reason: 'no shift after a hold');
    });

    test('in immediate mode the tap has already gone: a hold adds its action',
        () async {
      // Documented trade of the fast mode: the shift leaves on the press, so a
      // hold cannot take it back. Applications offering a long press should use
      // the deferred mode, and the interface only offers one with the other.
      final ButtonGestureDetector g = detector(
        up: defaultUpBindings.withLongPress(Action.menu),
      );
      g.feed(const ClickButtons(up: true, down: false));
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(actions, <Action>[Action.shiftUp, Action.menu]);
    });

    test('a short press never fires the long-press action', () async {
      final ButtonGestureDetector g = detector(
        up: defaultUpBindings.withLongPress(Action.menu),
      );
      g.feed(const ClickButtons(up: true, down: false));
      g.feed(ClickButtons.released);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(actions, <Action>[Action.shiftUp]);
      expect(actions.contains(Action.menu), isFalse);
    });

    test('an unconfigured long press stays silent', () async {
      final ButtonGestureDetector g = detector();
      g.feed(const ClickButtons(up: true, down: false));
      await Future<void>.delayed(const Duration(milliseconds: 160));
      g.feed(ClickButtons.released);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(actions, <Action>[Action.shiftUp]);
    });

    test('both buttons can hold different actions', () async {
      final ButtonGestureDetector g = detector(
        mode: GestureMode.deferred,
        up: defaultUpBindings.withLongPress(Action.emote),
        down: defaultDownBindings.withLongPress(Action.confirm),
      );
      g.feed(const ClickButtons(up: true, down: true));
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(actions, <Action>[Action.emote, Action.confirm]);
      g.feed(ClickButtons.released);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(actions.length, 2, reason: 'one long press, one action');
    });
  });

  group('contract', () {
    test('a long press must outlast the double-tap window', () {
      expect(
        () => ButtonGestureDetector(
          onAction: actions.add,
          doubleTapWindow: const Duration(milliseconds: 400),
          longPressAfter: const Duration(milliseconds: 300),
        ),
        throwsArgumentError,
      );
    });

    test('dispose cancels a pending deferred decision', () async {
      final ButtonGestureDetector g = ButtonGestureDetector(
        onAction: actions.add,
        mode: GestureMode.deferred,
        doubleTapWindow: const Duration(milliseconds: 40),
      );
      g.feed(const ClickButtons(up: true, down: false));
      g.feed(ClickButtons.released);
      g.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(actions, isEmpty);
    });
  });
}
