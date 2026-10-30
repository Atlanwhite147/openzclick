import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

void main() {
  late List<Action> actions;
  late ButtonGestureDetector detector;

  setUp(() {
    actions = <Action>[];
    detector = ButtonGestureDetector(
      onAction: actions.add,
      doubleTapWindow: const Duration(milliseconds: 40),
    );
  });

  tearDown(() => detector.dispose());

  test('a single tap on up shifts up after the window', () async {
    detector.feed(const ClickButtons(up: true, down: false));
    detector.feed(ClickButtons.released);
    expect(actions, isEmpty, reason: 'decision is deferred');
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(actions, <Action>[Action.shiftUp]);
  });

  test('a single tap on down shifts down', () async {
    detector.feed(const ClickButtons(up: false, down: true));
    detector.feed(ClickButtons.released);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(actions, <Action>[Action.shiftDown]);
  });

  test('a double tap on up chooses the left direction', () async {
    detector.feed(const ClickButtons(up: true, down: false));
    detector.feed(ClickButtons.released);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    detector.feed(const ClickButtons(up: true, down: false));
    detector.feed(ClickButtons.released);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(actions, <Action>[Action.steerLeft]);
  });

  test('a double tap on down chooses the right direction', () async {
    detector.feed(const ClickButtons(up: false, down: true));
    detector.feed(ClickButtons.released);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    detector.feed(const ClickButtons(up: false, down: true));
    detector.feed(ClickButtons.released);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(actions, <Action>[Action.steerRight]);
  });

  test('both buttons held together produce nothing', () async {
    detector.feed(const ClickButtons(up: true, down: true));
    await Future<void>.delayed(const Duration(milliseconds: 70));
    detector.feed(ClickButtons.released);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(actions, <Action>[Action.shiftUp, Action.shiftDown]);
  });
}
