import 'package:flutter/material.dart' hide Action;

import 'package:openzclick/main.dart' show ControllersScreen;
import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/ble/controller_connection.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick_core/openzclick_core.dart';

import 'fake_publisher.dart';

void main() {
  test('a low battery becomes one sentence, and only when it crosses', () {
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);
    state.controller.status = ControllerStatus.ready;

    state.controller.batteryPercent = 60;
    state.controller.onChanged?.call();
    expect(state.batteryWarning, isNull);

    state.controller.batteryPercent = 18;
    state.controller.onChanged?.call();
    expect(state.batteryWarning, contains('18 %'));
    expect(state.batteryWarning, contains('before the next ride'));

    // A second frame at the same level must not produce a second warning.
    state.controller.batteryPercent = 17;
    state.controller.onChanged?.call();
    expect(state.batteryWarning, contains('17 %'), reason: 'level is shown');
    expect(state.battery.notice, BatteryNotice.low, reason: 'still one notice');
  });

  test('a disconnection forgets the level instead of keeping a stale one', () {
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);
    state.controller.status = ControllerStatus.ready;
    state.controller.batteryPercent = 6;
    state.controller.onChanged?.call();
    expect(state.batteryWarning, contains('end of this ride'));

    state.controller.status = ControllerStatus.idle;
    state.controller.onChanged?.call();

    expect(state.batteryWarning, isNull);
    expect(state.battery.percent, isNull);
  });

  testWidgets('the warning is shown on the controllers screen', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);
    state.controller.status = ControllerStatus.ready;
    // Below the critical mark (8 %), so the sentence says the ride may not
    // finish rather than asking for a charge later.
    state.controller.batteryPercent = 5;
    state.controller.onChanged?.call();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ControllersScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('It may stop before the end'), findsOneWidget);
  });
}
