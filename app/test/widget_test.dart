import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/main.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick_core/openzclick_core.dart';

void main() {
  testWidgets('trainer screen shows the default gear', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenZclickApp());
    await tester.pumpAndSettle();

    expect(find.text('Gear'), findsOneWidget);
    expect(find.textContaining('/ 12'), findsWidgets);
  });

  testWidgets('shift up changes the displayed gear', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenZclickApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shift up'));
    await tester.pumpAndSettle();

    expect(find.text('7 / 12'), findsOneWidget);
  });

  test('a pressed up button shifts up once', () {
    final AppState state = AppState();
    final int before = state.engine.gearIndex;
    state.handleButtons(const ClickButtons(up: true, down: false));
    expect(state.engine.gearIndex, before + 1);
    state.dispose();
  });

  test('a pressed down button shifts down once', () {
    final AppState state = AppState();
    final int before = state.engine.gearIndex;
    state.handleButtons(const ClickButtons(up: false, down: true));
    expect(state.engine.gearIndex, before - 1);
    state.dispose();
  });

  test('both buttons pressed do not shift', () {
    final AppState state = AppState();
    final int before = state.engine.gearIndex;
    state.handleButtons(const ClickButtons(up: true, down: true));
    expect(state.engine.gearIndex, before);
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
