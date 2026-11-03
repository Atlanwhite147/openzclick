import 'dart:async';

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick/main.dart';
import 'package:openzclick/net/publisher_port.dart';
import 'package:openzclick/state/app_state.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// A publisher that reports a running bridge with a console, so the card can be
/// read without opening a socket.
class RunningBridge implements PublisherPort {
  @override
  void Function()? onChanged;

  @override
  bool running = true;

  @override
  bool advertise = true;

  @override
  int port = 47123;

  @override
  int? listeningPort = 47123;

  @override
  String? address = '192.168.1.24';

  @override
  int peers = 0;

  @override
  String? error;

  @override
  int consoles = 0;

  @override
  int? get consolePort => running ? 47124 : null;

  @override
  String get consoleToken => 'abcd';

  @override
  String? consoleUrl(String host) =>
      running ? 'ws://$host:47124/console?token=abcd' : null;

  @override
  Stream<Action> get consoleActions => const Stream<Action>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

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

void main() {
  testWidgets('the target screen tells where a browser console dials', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState(publisher: RunningBridge());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TargetScreen(state: state)),
      ),
    );

    expect(find.text('Browser console'), findsOneWidget);
    // The QR code must land on the page the bridge serves itself, in http on
    // the bridge's own port. A hosted page is https://, and a browser refuses
    // to open the console socket (ws://) from one: the scan used to produce a
    // page that could never reach the bridge, with no way to tell why.
    expect(
      find.textContaining('http://192.168.1.24:47124/?token=abcd'),
      findsOneWidget,
    );
    expect(find.textContaining('?bridge='), findsNothing);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('a stopped bridge says what to start', (
    WidgetTester tester,
  ) async {
    final RunningBridge bridge = RunningBridge()..running = false;
    final AppState state = AppState(publisher: bridge);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TargetScreen(state: state)),
      ),
    );

    expect(find.textContaining('Start the publication'), findsOneWidget);
  });
}
