import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/ble/controller_connection.dart';
import 'package:openzclick/net/console_endpoint.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:openzclick/ui/one_tap.dart';

import 'fake_publisher.dart';

void main() {
  group('the bridge this page came from', () {
    test('a page served by a bridge knows its address and its token', () {
      // The whole point of one button: nothing to type, nothing to scan. A bridge
      // serves this page on the port it already listens on, and puts the token in
      // the query string it handed out.
      expect(
        ConsoleEndpoint.fromOwnPage(
          Uri.parse('http://192.168.1.24:47124/?token=abcd'),
        ),
        (host: '192.168.1.24:47124', code: 'abcd'),
      );
    });

    test('a hosted page knows nothing, and says so', () {
      // `https` is a page nobody's bridge served: dialling it would be guessing.
      expect(
        ConsoleEndpoint.fromOwnPage(
          Uri.parse('https://example.org/?token=abcd'),
        ),
        isNull,
      );
    });

    test('a page opened without a token is not a bridge page', () {
      expect(
        ConsoleEndpoint.fromOwnPage(Uri.parse('http://192.168.1.24:47124/')),
        isNull,
      );
    });
  });

  group('the one button', () {
    testWidgets('it says what is missing before anything is pressed', (
      WidgetTester tester,
    ) async {
      final FakePublisher publisher = FakePublisher();
      final AppState state = AppState(publisher: publisher);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OneTapRide(state: state)),
        ),
      );

      expect(find.text('Start riding'), findsOneWidget);
      expect(find.text('Pod not connected'), findsOneWidget);
      expect(find.text('No bridge'), findsOneWidget);
    });

    testWidgets('it becomes a verdict once both halves are up', (
      WidgetTester tester,
    ) async {
      final FakePublisher publisher = FakePublisher();
      final AppState state = AppState(publisher: publisher);
      addTearDown(state.dispose);
      state.controller.status = ControllerStatus.ready;
      await publisher.start();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OneTapRide(state: state)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Riding'), findsOneWidget);
      expect(find.text('Pod connected'), findsOneWidget);
      expect(find.text('Bridge linked'), findsOneWidget);
    });
  });
}
