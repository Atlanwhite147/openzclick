import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick/ui/gear_panel.dart';

Widget _wrap(AppState state) => MaterialApp(
  home: Scaffold(body: GearPanel(state: state)),
);

/// The label of the button, which is where its enabled state is readable.
bool _enabled(WidgetTester tester, String label) {
  final FilledButton button = tester.widget(
    find.ancestor(of: find.text(label), matching: find.byType(FilledButton)),
  );
  return button.onPressed != null;
}

void main() {
  testWidgets('the two shift buttons are the only controls on the panel', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(state));

    expect(find.byType(FilledButton), findsNWidgets(2));
    expect(find.text('Shift up'), findsOneWidget);
    expect(find.text('Shift down'), findsOneWidget);
  });

  testWidgets('the gear number is the largest thing on the screen', (
    WidgetTester tester,
  ) async {
    // While riding, the gear is the one number a rider glances at. Everything
    // else on this panel is read once.
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(state));

    final Text gear = tester.widget(find.byKey(const Key('gear-number')));
    expect(gear.data, '6');
    expect(gear.style!.fontSize, greaterThan(30));
  });

  testWidgets('the largest gear disables Shift up instead of ignoring it', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    for (int i = 0; i < state.engine.gearCount; i++) {
      state.engine.shiftUp();
    }
    await tester.pumpWidget(_wrap(state));

    expect(state.engine.atHighest, isTrue);
    expect(_enabled(tester, 'Shift up'), isFalse);
    expect(_enabled(tester, 'Shift down'), isTrue);
  });

  testWidgets('the smallest gear disables Shift down', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    for (int i = 0; i < state.engine.gearCount; i++) {
      state.engine.shiftDown();
    }
    await tester.pumpWidget(_wrap(state));

    expect(state.engine.atLowest, isTrue);
    expect(_enabled(tester, 'Shift down'), isFalse);
    expect(_enabled(tester, 'Shift up'), isTrue);
  });

  testWidgets('the mode is readable without opening the settings', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(state));

    expect(find.text('SIM'), findsOneWidget);
    state.toggleMode();
    await tester.pumpAndSettle();
    expect(find.textContaining('ERG'), findsOneWidget);
  });

  testWidgets('the settings are folded away until asked for', (
    WidgetTester tester,
  ) async {
    // Six buttons of equal weight made the screen look like a control panel for
    // engineers; the four settings are now behind one expander.
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(state));

    expect(find.text('Gear set and riding mode'), findsOneWidget);
    expect(find.text('Ratio'), findsNothing);

    await tester.tap(find.text('Gear set and riding mode'));
    await tester.pumpAndSettle();
    expect(find.text('Ratio'), findsOneWidget);
    expect(find.text('Change chainring'), findsOneWidget);
  });

  testWidgets('pressing shift up moves the number on screen', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(state));

    await tester.tap(find.text('Shift up'));
    await tester.pumpAndSettle();

    final Text gear = tester.widget(find.byKey(const Key('gear-number')));
    expect(gear.data, '7');
  });
}
