import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/main.dart';
import 'package:openzclick/state/app_state.dart';

import 'fake_publisher.dart';

void main() {
  testWidgets('every screen says whether the ride will work', (
    WidgetTester tester,
  ) async {
    // Without this the answer to "why is nothing happening" lives on a tab the
    // rider has to guess.
    final FakePublisher publisher = FakePublisher();
    final AppState state = AppState(publisher: publisher);
    addTearDown(state.dispose);

    await tester.pumpWidget(MaterialApp(home: HomeShell(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('Not ready'), findsOneWidget);

    await publisher.start();
    state.setParkedGear(chainring: 34, cog: 19);
    await tester.pumpAndSettle();

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Not ready'), findsNothing);
  });

  testWidgets('the bridge alone is not enough to call the ride ready', (
    WidgetTester tester,
  ) async {
    // A started bridge with an unknown parked gear shifts every gear by up to a
    // factor of two, which the rider cannot see.
    final FakePublisher publisher = FakePublisher();
    final AppState state = AppState(publisher: publisher);
    addTearDown(state.dispose);

    await tester.pumpWidget(MaterialApp(home: HomeShell(state: state)));
    await publisher.start();
    await tester.pumpAndSettle();

    expect(find.text('Not ready'), findsOneWidget);
  });
}
