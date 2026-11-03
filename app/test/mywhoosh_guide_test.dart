import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/main.dart';
import 'package:openzclick/net/publisher_port.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick/ui/mywhoosh_guide.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// A publisher whose state the test drives, so the guide can be read in each
/// situation a rider meets: stopped, running, and with MyWhoosh attached.
class FakePublisher implements PublisherPort {
  @override
  void Function()? onChanged;

  @override
  bool running = false;

  @override
  bool advertise = true;

  @override
  int port = 47123;

  @override
  int? listeningPort;

  @override
  String? address;

  @override
  int peers = 0;

  @override
  String? error;

  @override
  int consoles = 0;

  @override
  int? get consolePort => null;

  @override
  String get consoleToken => '';

  @override
  String? consoleUrl(String host) => null;

  @override
  Stream<Action> get consoleActions => const Stream<Action>.empty();

  @override
  Future<void> start() async {
    running = true;
    listeningPort = port;
    address = '192.168.1.24';
    onChanged?.call();
  }

  @override
  Future<void> stop() async {
    running = false;
    listeningPort = null;
    onChanged?.call();
  }

  @override
  Future<void> publish(Action action) async {}

  @override
  Future<void> publishConsoleState({
    required String profileId,
    required int gearIndex,
    required int gearCount,
    required String mode,
    required String lastAction,
  }) async {}

  @override
  Future<void> dispose() async {}
}

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
