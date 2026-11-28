import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/settings/display_mode.dart';
import 'package:openzclick/ui/shell.dart';
import 'package:openzclick/platform/capabilities.dart';
import 'package:openzclick/state/app_state.dart';

import 'fake_publisher.dart';

void main() {
  testWidgets('every screen says whether the ride will work', (
    WidgetTester tester,
  ) async {
    // Without this the answer to "why is nothing happening" lives on a tab the
    // rider has to guess.
    final FakePublisher publisher = FakePublisher();
    final AppState state = AppState(publisher: publisher)
      ..setDisplayMode(DisplayMode.advanced);
    addTearDown(state.dispose);
    // These tests are about the tabs: the first-start guide would sit in front
    // of them, and it has its own tests.
    state.completeOnboarding();

    await tester.pumpWidget(MaterialApp(home: HomeShell(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('Not ready'), findsOneWidget);

    await publisher.start();
    await tester.pumpAndSettle();

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Not ready'), findsNothing);
  });

  testWidgets('a started bridge is ready even with the chain unanswered', (
    WidgetTester tester,
  ) async {
    // The route a rider actually rides today: MyWhoosh keeps its own gear model
    // and applies the resistance itself, so the bridge only forwards button
    // presses. A rider who skipped the chain question shifts perfectly, and
    // telling them the ride is not ready would send them debugging a working
    // setup. This is the case a Zwift Cog user hits: one cog, nothing to answer.
    expect(Capabilities.drivesTrainerItself, isFalse);

    final FakePublisher publisher = FakePublisher();
    final AppState state = AppState(publisher: publisher)
      ..setDisplayMode(DisplayMode.advanced);
    addTearDown(state.dispose);
    // These tests are about the tabs: the first-start guide would sit in front
    // of them, and it has its own tests.
    state.completeOnboarding();

    await tester.pumpWidget(MaterialApp(home: HomeShell(state: state)));
    await publisher.start();
    await tester.pumpAndSettle();

    expect(state.physicalSetup.isComplete, isFalse);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('an unanswered chain is asked as optional, not as a fault', (
    WidgetTester tester,
  ) async {
    // A red icon and a bare question read as "you cannot ride yet". The setting
    // only matters where the bridge drives the trainer itself.
    final FakePublisher publisher = FakePublisher();
    final AppState state = AppState(publisher: publisher)
      ..setDisplayMode(DisplayMode.advanced);
    addTearDown(state.dispose);
    // These tests are about the tabs: the first-start guide would sit in front
    // of them, and it has its own tests.
    state.completeOnboarding();

    await tester.pumpWidget(MaterialApp(home: HomeShell(state: state)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gears'));
    await tester.pumpAndSettle();

    expect(find.text('Where is your chain? (optional)'), findsOneWidget);
    expect(find.text('Where is your chain?'), findsNothing);
  });

  testWidgets('the lamp is also the way to the fix', (
    WidgetTester tester,
  ) async {
    // "Not ready" without a next step is a dead end: the rider is told something
    // is wrong and left to find the tab. The lamp says where to go.
    // The lamp is a feature of the advanced interface: the simple screen says
    // the same thing in a sentence, and has its own tests.
    final FakePublisher publisher = FakePublisher();
    final AppState state = AppState(publisher: publisher)
      ..setDisplayMode(DisplayMode.advanced);
    addTearDown(state.dispose);
    state.completeOnboarding();

    await tester.pumpWidget(MaterialApp(home: HomeShell(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('Not ready'), findsOneWidget);
    // Nothing from the Network screen is on screen yet.
    expect(find.text('Publish on the network'), findsNothing);

    await tester.tap(find.text('Not ready'));
    await tester.pumpAndSettle();

    // The bridge is started from Network, so that is where the lamp sends them:
    // a section only that screen carries proves the tab actually changed.
    expect(find.text('Publish on the network'), findsOneWidget);
  });
}
