import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick/ui/parked_gear_card.dart';
import 'package:openzclick_core/openzclick_core.dart';

Widget _wrap(AppState state) => MaterialApp(
  home: Scaffold(body: ParkedGearCard(state: state)),
);

void main() {
  testWidgets('asks where the chain is before anything else', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(state));

    expect(find.text('Where is your chain?'), findsOneWidget);
    expect(find.text('Chainring'), findsOneWidget);
    expect(find.text('Cog'), findsOneWidget);
  });

  testWidgets('holds a half answer instead of dropping it', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(state));

    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('50 T').last);
    await tester.pumpAndSettle();

    // Nothing is recorded yet, because the wheel size cannot be built from one
    // tooth count; but the choice is kept on screen so the rider can finish.
    expect(state.physicalSetup.parkedChainringTeeth, isNull);
    expect(find.text('Where is your chain?'), findsOneWidget);
    expect(find.text('50 T'), findsWidgets);

    await tester.tap(find.byType(DropdownButton<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('17 T').last);
    await tester.pumpAndSettle();

    expect(state.physicalSetup.parkedChainringTeeth, 50);
    expect(state.physicalSetup.parkedCogTeeth, 17);
  });

  testWidgets('answers as soon as both halves are known', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(state));

    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('34 T').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('19 T').last);
    await tester.pumpAndSettle();

    expect(state.physicalSetup.isComplete, isTrue);
    expect(find.text('Chain on 34/19'), findsOneWidget);
  });

  testWidgets('collapses to one line once answered', (
    WidgetTester tester,
  ) async {
    // Answered once per bike, never again: a card that keeps the same size
    // forever pushes the shift buttons off a phone.
    final AppState state = AppState();
    addTearDown(state.dispose);
    state.setParkedGear(chainring: 34, cog: 19);
    await tester.pumpWidget(_wrap(state));

    expect(find.text('Chain on 34/19'), findsOneWidget);
    expect(find.textContaining('scaled from this'), findsOneWidget);
    expect(find.text('Where is your chain?'), findsNothing);
    expect(find.byType(DropdownButton<int>), findsNothing);
  });

  testWidgets('one tap reopens the question for a change of bike', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    state.setParkedGear(chainring: 34, cog: 19);
    await tester.pumpWidget(_wrap(state));

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
  });

  testWidgets('offers the quietest gear that still reaches every gear', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    state.setParkedGear(chainring: 50, cog: 11);
    await tester.pumpWidget(_wrap(state));
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    final ParkedGear recommended = state.recommendedParkedGear!;
    expect(find.text('Quietest: ${recommended.name}'), findsOneWidget);

    await tester.tap(find.text('Quietest: ${recommended.name}'));
    await tester.pumpAndSettle();
    expect(
      state.physicalSetup.parkedChainringTeeth,
      recommended.chainringTeeth,
    );
  });

  testWidgets('explains a gear it cannot build instead of hiding it', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    // Parked in the big ring on the smallest cog, the easiest gears need a
    // wheel so small that a training application would draw a stopped rider.
    state.setParkedGear(chainring: 50, cog: 11);
    state.engine = GearEngine(profile: GearProfile.road12, initialGear: 0);
    await tester.pumpWidget(_wrap(state));

    expect(find.textContaining('cannot be built from 50/11'), findsOneWidget);
  });

  testWidgets('says the wheel size in the collapsed line too', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    state.setParkedGear(chainring: 34, cog: 19);
    await tester.pumpWidget(_wrap(state));

    expect(find.textContaining('wheel'), findsOneWidget);
    expect(find.textContaining('mm'), findsOneWidget);
  });
}
