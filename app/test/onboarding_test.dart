import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick/ui/onboarding.dart';

Widget _wrap(
  AppState state, {
  VoidCallback? onDone,
  void Function(int)? onTab,
}) {
  return MaterialApp(
    home: OnboardingScreen(onDone: onDone ?? () {}, onOpenTab: onTab),
  );
}

void main() {
  testWidgets('the guide opens on the first step, and says where it is', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(state));

    expect(find.text('Wake the pod and connect it'), findsOneWidget);
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-tick-current')), findsOneWidget);
  });

  testWidgets('each step says one thing, and the last one starts the ride', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    bool done = false;
    await tester.pumpWidget(_wrap(state, onDone: () => done = true));

    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text('Step 4 of 4'), findsOneWidget);
    expect(done, isFalse);

    await tester.tap(find.text('Start riding'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('skipping is a decision, not a trap', (
    WidgetTester tester,
  ) async {
    // A rider who wants to look around first must be able to say so once, not
    // every launch.
    final AppState state = AppState();
    addTearDown(state.dispose);
    bool done = false;
    await tester.pumpWidget(_wrap(state, onDone: () => done = true));

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('a step that names a screen can go there', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    int? opened;
    await tester.pumpWidget(_wrap(state, onTab: (int tab) => opened = tab));

    await tester.tap(find.text('Open Controllers'));
    await tester.pumpAndSettle();
    expect(opened, 2);
  });

  testWidgets('the flag is what decides, and it survives', (
    WidgetTester tester,
  ) async {
    // The guide is shown once. The decision lives in the state, which persists
    // it, so a returning rider lands on the tabs directly.
    final AppState state = AppState();
    addTearDown(state.dispose);
    expect(state.onboardingDone, isFalse);
    state.completeOnboarding();
    expect(state.onboardingDone, isTrue);
    state.replayOnboarding();
    expect(state.onboardingDone, isFalse);
  });
}
