import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/main.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// The gear number, read from its own key rather than from a surrounding
/// string: the readout is now a large number and a smaller denominator, and a
/// test looking for "7 / 12" would pin the layout instead of the behaviour.
String gearShown(WidgetTester tester) {
  final Widget widget = tester.widget(find.byKey(const Key('gear-number')));
  return (widget as Text).data!;
}

void main() {
  testWidgets('the gear screen shows the default gear', (
    WidgetTester tester,
  ) async {
    // The application disposes the state it was handed, so the test does not.
    final AppState state = AppState();
    // Past the first-start guide: these tests are about the shell.
    state.completeOnboarding();
    await tester.pumpWidget(OpenZclickApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gears'));
    await tester.pumpAndSettle();

    expect(find.text('Gear'), findsOneWidget);
    expect(gearShown(tester), '6');
  });

  testWidgets('shift up changes the displayed gear', (
    WidgetTester tester,
  ) async {
    // The application disposes the state it was handed, so the test does not.
    final AppState state = AppState();
    // Past the first-start guide: these tests are about the shell.
    state.completeOnboarding();
    await tester.pumpWidget(OpenZclickApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gears'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shift up'));
    await tester.pumpAndSettle();

    expect(gearShown(tester), '7');
  });

  testWidgets('there are four tabs, and none of them is a developer tool', (
    WidgetTester tester,
  ) async {
    // The test bench sat in the navigation bar beside the gear, which is what
    // made the application look like something to configure rather than use.
    // The application disposes the state it was handed, so the test does not.
    final AppState state = AppState();
    // Past the first-start guide: these tests are about the shell.
    state.completeOnboarding();
    await tester.pumpWidget(OpenZclickApp(state: state));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('Diagnostics'), findsNothing);
  });

  test('a single tap on up shifts up', () async {
    final AppState state = AppState(
      doubleTapWindow: const Duration(milliseconds: 20),
    );
    final int before = state.engine.gearIndex;
    state.handleButtons(const ClickButtonMask(up: true, down: false));
    state.handleButtons(ClickButtonMask.released);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(state.engine.gearIndex, before + 1);
    state.dispose();
  });

  test('a single tap on down shifts down', () async {
    final AppState state = AppState(
      doubleTapWindow: const Duration(milliseconds: 20),
    );
    final int before = state.engine.gearIndex;
    state.handleButtons(const ClickButtonMask(up: false, down: true));
    state.handleButtons(ClickButtonMask.released);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(state.engine.gearIndex, before - 1);
    state.dispose();
  });

  test('two quick presses are two gear changes', () async {
    // Reported from MyWhoosh on 2026-11-12: going down several gears needed a
    // pause between presses. The second press inside the double-tap window was
    // being spent on a direction choice instead of the next gear.
    final AppState state = AppState(
      doubleTapWindow: const Duration(milliseconds: 40),
    );
    final int before = state.engine.gearIndex;
    state.handleButtons(const ClickButtonMask(up: true, down: false));
    state.handleButtons(ClickButtonMask.released);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    state.handleButtons(const ClickButtonMask(up: true, down: false));
    state.handleButtons(ClickButtonMask.released);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(state.engine.gearIndex, before + 2);
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
