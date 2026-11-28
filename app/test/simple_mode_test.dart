import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick_core/openzclick_core.dart';

import 'package:openzclick/settings/display_mode.dart';
import 'package:openzclick/settings/settings_store.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick/ui/shell.dart';

import 'fake_publisher.dart';

/// The two interfaces: one screen, or the five tabs.
///
/// The rule these tests hold is the one a rider stated in plain words: "in the
/// simple mode it comes down to connecting and riding, with a few practical
/// notes". Anything that has to be configured to ride does not belong on that
/// screen, and the way to check is to look for it and not find it.
void main() {
  Future<AppState> pumpShell(
    WidgetTester tester, {
    DisplayMode mode = DisplayMode.simple,
  }) async {
    final FakePublisher publisher = FakePublisher();
    final AppState state = AppState(publisher: publisher);
    state.completeOnboarding();
    if (mode != DisplayMode.simple) state.setDisplayMode(mode);
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: HomeShell(state: state)));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('a fresh install lands on the simple screen, with no tabs', (
    WidgetTester tester,
  ) async {
    final AppState state = await pumpShell(tester);

    expect(state.displayMode, DisplayMode.simple);
    expect(find.byType(NavigationDestination), findsNothing);
    // The one thing the screen is for, then the state, in plain words.
    expect(find.text('Pair controller'), findsOneWidget);
    expect(find.text('Ready when you are'), findsOneWidget);
  });

  testWidgets('the simple screen is pairing, starting and a few notes', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    // What a rider needs: how to wake the pod, and the steps, folded.
    expect(find.text('Press + on the pod to wake it'), findsOneWidget);
    expect(find.text('How to ride with MyWhoosh'), findsOneWidget);
    expect(find.text('Nothing connects?'), findsOneWidget);

    // What a rider does not need, and what used to be in front of them.
    expect(find.text('Gear'), findsNothing);
    expect(find.text('Shift up'), findsNothing);
    expect(find.text('Protocol test bench'), findsNothing);
    expect(find.text('Publish on the network'), findsNothing);
    expect(find.text('Button mapping'), findsNothing);
    expect(find.text('Gears'), findsNothing);
  });

  testWidgets('the switch is in the top bar, on both screens', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    expect(find.byKey(const Key('display-mode')), findsOneWidget);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
  });

  testWidgets('switching to advanced brings the five tabs back', (
    WidgetTester tester,
  ) async {
    final AppState state = await pumpShell(tester);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    expect(state.displayMode, DisplayMode.advanced);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    // The switch stays where it was, so going back is never a hunt.
    expect(find.byKey(const Key('display-mode')), findsOneWidget);

    await tester.tap(find.text('Simple'));
    await tester.pumpAndSettle();
    expect(state.displayMode, DisplayMode.simple);
    expect(find.byType(NavigationDestination), findsNothing);
  });

  // A plain `test`, not `testWidgets`: the state saves through a 250 ms timer,
  // and the widget binding's fake clock would hold it forever.
  test('the choice survives a restart', () async {
    // Read from the stored snapshot, not guessed: a rider who picked advanced
    // wants advanced tomorrow, and the opposite just as much.
    final MemorySettingsStore store = MemorySettingsStore();
    await store.save(
      SettingsSnapshot(
        profileId: 'road12',
        gearIndex: 4,
        positions: const <Action, List<double>>{},
        publishOnStart: false,
        injectOnStart: false,
        displayMode: DisplayMode.advanced,
      ),
    );

    final AppState state = AppState();
    addTearDown(state.dispose);
    await state.restore(store);
    expect(state.displayMode, DisplayMode.advanced);

    state.setDisplayMode(DisplayMode.simple);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final SettingsSnapshot? saved = await store.load();
    expect(saved!.displayMode, DisplayMode.simple);
  });

  test('an unknown stored mode falls back to simple', () {
    // A downgrade, or a hand edited file, must not leave a rider on a blank
    // screen: simple is the safe answer.
    expect(DisplayMode.fromId(null), DisplayMode.simple);
    expect(DisplayMode.fromId(''), DisplayMode.simple);
    expect(DisplayMode.fromId('expert'), DisplayMode.simple);
    expect(DisplayMode.fromId('advanced'), DisplayMode.advanced);
  });
}
