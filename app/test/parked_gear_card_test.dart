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

  testWidgets('records the chainring the rider picks', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_wrap(state));

    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('50 T').last);
    await tester.pumpAndSettle();

    expect(state.physicalSetup.parkedChainringTeeth, 50);
  });

  testWidgets('shows the wheel size once the setup is complete', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    state.setParkedGear(chainring: 34, cog: 19);
    await tester.pumpWidget(_wrap(state));

    expect(find.text('Chain on 34/19'), findsOneWidget);
    expect(find.textContaining('Trainer wheel size right now'), findsOneWidget);
  });

  testWidgets('offers the quietest gear that still reaches every gear', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    state.setParkedGear(chainring: 50, cog: 11);
    await tester.pumpWidget(_wrap(state));

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
}
