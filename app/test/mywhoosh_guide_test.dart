import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/main.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick/ui/mywhoosh_guide.dart';

import 'fake_publisher.dart';

Future<void> pumpGuide(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(children: <Widget>[MyWhooshGuideCard(state: state)]),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a stopped bridge asks to be started, and offers the button', (
    WidgetTester tester,
  ) async {
    final FakePublisher publisher = FakePublisher();
    final AppState state = AppState(publisher: publisher);
    addTearDown(state.dispose);

    await pumpGuide(tester, state);

    expect(find.text('Ride with MyWhoosh'), findsOneWidget);
    expect(find.text('Start the bridge'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
  });

  testWidgets('offers the parked gear without making it look required', (
    WidgetTester tester,
  ) async {
    // MyWhoosh does its own virtual shifting, so an unanswered chain does not
    // stop anyone riding. Presenting it as a pre-condition sends riders to fix
    // a setup that already works.
    final FakePublisher publisher = FakePublisher();
    final AppState state = AppState(publisher: publisher);
    addTearDown(state.dispose);

    await pumpGuide(tester, state);
    expect(
      find.textContaining('Optional: tell the app where your chain sits'),
      findsOneWidget,
    );

    state.setParkedGear(chainring: 34, cog: 19);
    await tester.pump();
    expect(
      find.textContaining('Optional: tell the app where your chain sits'),
      findsNothing,
    );
  });

  testWidgets('the start button starts the publication', (
    WidgetTester tester,
  ) async {
    final FakePublisher publisher = FakePublisher();
    final AppState state = AppState(publisher: publisher);
    addTearDown(state.dispose);

    await pumpGuide(tester, state);
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();

    expect(publisher.running, isTrue);
    expect(find.widgetWithText(FilledButton, 'Start'), findsNothing);
    expect(find.textContaining('Announced on your network'), findsOneWidget);
  });

  testWidgets('MyWhoosh steps are the ones MyWhoosh itself documents', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);

    await pumpGuide(tester, state);

    // A novice needs the actual gesture, in the actual application.
    expect(
      find.textContaining('OpenBikeControl icon, top right'),
      findsOneWidget,
    );
    expect(find.textContaining('answer Yes'), findsOneWidget);
  });

  testWidgets('an attached application is reported, not left to guess', (
    WidgetTester tester,
  ) async {
    final FakePublisher publisher = FakePublisher()
      ..running = true
      ..listeningPort = 47123
      ..address = '192.168.1.24'
      ..peers = 1;
    final AppState state = AppState(publisher: publisher);
    addTearDown(state.dispose);

    await pumpGuide(tester, state);

    expect(find.text('MyWhoosh is connected'), findsOneWidget);
    expect(find.textContaining('Your two buttons now shift'), findsOneWidget);
  });

  testWidgets('the troubleshooting section names the real obstacles', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);

    await pumpGuide(tester, state);
    await tester.tap(find.text('MyWhoosh does not find it'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not one on Ethernet'), findsOneWidget);
    expect(find.textContaining('Bonjour'), findsOneWidget);
  });

  testWidgets('the parked gear box answers without leaving the screen', (
    WidgetTester tester,
  ) async {
    // The box used to name the Gears tab and stop there, which sends a novice
    // hunting for a tab in the middle of a first-time setup.
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);

    await pumpGuide(tester, state);
    await tester.tap(find.text('Answer now'));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<int>), findsNWidgets(2));

    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('34 T').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('19 T').last);
    await tester.pumpAndSettle();

    expect(state.physicalSetup.isComplete, isTrue);
    expect(find.textContaining('scaled from where the chain'), findsNothing);
  });

  testWidgets('the dialog can be dismissed without answering', (
    WidgetTester tester,
  ) async {
    // A rider who opened it by mistake, or who does not know their cog yet,
    // must not be trapped: the question is asked again from the gear screen.
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);

    await pumpGuide(tester, state);
    await tester.tap(find.text('Answer now'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(state.physicalSetup.isComplete, isFalse);
    expect(find.text('Answer now'), findsOneWidget);
  });

  testWidgets('the guide is the first screen, so it is seen without looking', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OpenZclickApp());
    await tester.pumpAndSettle();

    expect(find.text('Ride with MyWhoosh'), findsOneWidget);
    // The gear screen is still one tap away, and still works.
    await tester.tap(find.text('Gears'));
    await tester.pumpAndSettle();
    expect(find.text('Gear'), findsOneWidget);
  });
}
