import 'package:flutter/material.dart' hide Action;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openzclick/ui/screens/controllers_screen.dart';
import 'package:openzclick/platform/version.dart';
import 'package:openzclick/state/app_state.dart';

import 'fake_publisher.dart';

void main() {
  testWidgets('the pairing screen warns about a Click before it is paired', (
    WidgetTester tester,
  ) async {
    // The Click v2 stays silent until it has been paired once in Zwift, for
    // about three minutes. A rider who does not know that sees a controller
    // that connects and then does nothing, and blames the bridge.
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ControllersScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('First time with a Zwift Click?'),
      200,
    );
    expect(find.text('First time with a Zwift Click?'), findsOneWidget);
    expect(find.textContaining('about three minutes'), findsOneWidget);
  });

  testWidgets('a scan that finds nothing says so instead of nothing', (
    WidgetTester tester,
  ) async {
    // The scan used to return to this exact screen whether it had found a
    // controller or not: the rider pressed Scan, the page did not move, and the
    // only conclusion left was that the button was broken.
    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);
    state.controller.scanFoundNothing = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ControllersScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing answered'), findsOneWidget);
  });

  testWidgets('the pairing screen hands over the material for an issue', (
    WidgetTester tester,
  ) async {
    // The bridge is written on a machine with no Bluetooth radio, so a dropout
    // can only be understood from what the rider's device actually exposes.
    // Asking for a description gets skimmed; asking for a pasted blob works.
    final List<String> copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final AppState state = AppState(publisher: FakePublisher());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ControllersScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Copy device report'), 200);
    await tester.tap(find.text('Copy device report'));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains('openzclick device report'));
    // The version travels with it: without one, a maintainer is reading an
    // unknown build.
    expect(copied.single, contains(appVersion));
    expect(find.textContaining('Device report copied'), findsOneWidget);
  });
}
