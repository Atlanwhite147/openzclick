import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/main.dart';
import 'package:openzclick/net/desktop_injection_native.dart';
import 'package:openzclick/settings/settings_store.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick_core/openzclick_core.dart';

import 'fake_publisher.dart';

/// The key editor only exists where a desktop backend does — Linux and Windows.
///
/// Not a disguise of the host: the widget itself is absent on macOS and iOS, so
/// asserting it there would be asserting something no rider can see.
final bool _hasDesktopBackend = createDesktopInjection() != null;

void main() {
  testWidgets('a rider can change the key of an action', (
    WidgetTester tester,
  ) async {
    // The shipped table covers three applications; a rider on another one needs
    // to be able to say which key their application expects, without editing
    // code.
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);
    expect(state.effectiveKeys[Action.shiftUp], 'k');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TargetScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adjust the keys'));
    await tester.pumpAndSettle();

    final Finder field = find.widgetWithText(TextFormField, 'Shift up');
    expect(field, findsOneWidget);
    await tester.enterText(field, 'x');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(state.effectiveKeys[Action.shiftUp], 'x');
    expect(state.hasKeyOverrides, isTrue);
    // The publisher is rebuilt with the new table, not only the screen.
    expect(state.injection.keys?[Action.shiftUp], 'x');
  }, skip: !_hasDesktopBackend);

  testWidgets('emptying a field restores the shipped key', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);
    state.setKey(Action.shiftUp, 'x');
    expect(state.hasKeyOverrides, isTrue);

    state.setKey(Action.shiftUp, '   ');

    expect(state.hasKeyOverrides, isFalse);
    expect(state.effectiveKeys[Action.shiftUp], 'k');
    expect(state.injection.keys?[Action.shiftUp], 'k');
  }, skip: !_hasDesktopBackend);

  testWidgets('changing the application drops the changes of the old one', (
    WidgetTester tester,
  ) async {
    // The overrides are per application: keeping `x` for MyWhoosh while the
    // rider switches to Rouvy would send a key nobody configured.
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);
    state.setKey(Action.shiftUp, 'x');

    state.setKeyProfile('rouvy');

    expect(state.keyProfile.id, 'rouvy');
    expect(state.hasKeyOverrides, isFalse);
    expect(state.effectiveKeys[Action.shiftUp], '.');
  });

  test('the changed keys survive a restart', () async {
    final MemorySettingsStore store = MemorySettingsStore();
    final AppState first = AppState(publisher: FakePublisher());
    first.setKeyProfile('rouvy');
    first.setKey(Action.shiftDown, 'v');
    await first.restore(store);
    first.setKey(Action.shiftDown, 'v');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    first.dispose();

    final AppState second = AppState(publisher: FakePublisher());
    addTearDown(second.dispose);
    await second.restore(store);

    expect(second.keyProfile.id, 'rouvy');
    expect(second.effectiveKeys[Action.shiftDown], 'v');
  }, skip: !_hasDesktopBackend);
}
