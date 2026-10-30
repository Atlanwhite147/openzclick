import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/main.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick_core/openzclick_core.dart';

void main() {
  testWidgets('trainer screen shows the default gear', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OpenZclickApp());
    await tester.pumpAndSettle();

    expect(find.text('Gear'), findsOneWidget);
    expect(find.textContaining('/ 12'), findsWidgets);
  });

  testWidgets('shift up changes the displayed gear', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OpenZclickApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shift up'));
    await tester.pumpAndSettle();

    expect(find.text('7 / 12'), findsOneWidget);
  });

  test('a single tap on up shifts up', () async {
    final AppState state = AppState(
      doubleTapWindow: const Duration(milliseconds: 20),
    );
    final int before = state.engine.gearIndex;
    state.handleButtons(const ClickButtons(up: true, down: false));
    state.handleButtons(ClickButtons.released);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(state.engine.gearIndex, before + 1);
    state.dispose();
  });

  test('a single tap on down shifts down', () async {
    final AppState state = AppState(
      doubleTapWindow: const Duration(milliseconds: 20),
    );
    final int before = state.engine.gearIndex;
    state.handleButtons(const ClickButtons(up: false, down: true));
    state.handleButtons(ClickButtons.released);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(state.engine.gearIndex, before - 1);
    state.dispose();
  });

  test('a double tap chooses a direction instead of shifting', () async {
    final AppState state = AppState(
      doubleTapWindow: const Duration(milliseconds: 40),
    );
    final int before = state.engine.gearIndex;
    state.handleButtons(const ClickButtons(up: true, down: false));
    state.handleButtons(ClickButtons.released);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    state.handleButtons(const ClickButtons(up: true, down: false));
    state.handleButtons(ClickButtons.released);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(state.engine.gearIndex, before);
    expect(state.lastAction, Action.steerLeft);
    state.dispose();
  });

  test('state starts in simulation mode with the road profile', () {
    final AppState state = AppState();
    expect(state.engine.gearCount, 12);
    expect(state.engine.mode.name, 'sim');
    state.dispose();
  });
}

// Button wiring is checked without Bluetooth: the state accepts a button
// event directly, exactly as the connection would deliver it.
