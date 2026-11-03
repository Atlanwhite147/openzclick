import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick/net/console_endpoint.dart';
import 'package:openzclick/net/network_publisher.dart';

/// Waits until [condition] holds, or fails after a second.
Future<void> until(bool Function() condition) async {
  for (int attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition never held');
}

void main() {
  test('a bridge publishes the address and the code a console needs', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
      requestedConsolePort: 0,
    );
    await publisher.start();
    addTearDown(publisher.dispose);

    expect(publisher.consoleToken, hasLength(4));
    final String? url = publisher.consoleUrl('192.168.1.24');
    expect(url, isNotNull);
    expect(url, contains('ws://192.168.1.24:'));
    expect(url, contains('token=${publisher.consoleToken}'));
    expect(
      url,
      endsWith('${ConsoleEndpoint.path}?token=${publisher.consoleToken}'),
    );
  });

  test('a browser console drives the bridge with its buttons', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
      requestedConsolePort: 0,
    );
    await publisher.start();
    addTearDown(publisher.dispose);

    final List<Action> received = <Action>[];
    final StreamSubscription<Action> subscription = publisher.consoleActions
        .listen(received.add);
    addTearDown(subscription.cancel);

    final String url = publisher.consoleUrl('127.0.0.1')!;
    final WebSocket socket = await WebSocket.connect(url);
    addTearDown(socket.close);
    await until(() => publisher.consoles == 1);

    // The console is an input like any other: one message, one action.
    socket.add(jsonEncode(<String, Object?>{'action': Action.shiftDown.name}));
    await until(() => received.isNotEmpty);
    expect(received.single, Action.shiftDown);
  });

  test('a console that leaves is no longer counted', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
      requestedConsolePort: 0,
    );
    await publisher.start();
    addTearDown(publisher.dispose);

    final WebSocket socket = await WebSocket.connect(
      publisher.consoleUrl('127.0.0.1')!,
    );
    await until(() => publisher.consoles == 1);
    await socket.close();
    await until(() => publisher.consoles == 0);
  });

  test('the bridge state reaches the console that asks for it', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
      requestedConsolePort: 0,
    );
    await publisher.start();
    addTearDown(publisher.dispose);

    final WebSocket socket = await WebSocket.connect(
      publisher.consoleUrl('127.0.0.1')!,
    );
    addTearDown(socket.close);
    final Stream<dynamic> messages = socket.asBroadcastStream();
    final Future<dynamic> welcome = messages.first;

    await publisher.publishConsoleState(
      profileId: 'road12',
      gearIndex: 6,
      gearCount: 12,
      mode: RidingMode.sim.name,
      lastAction: 'Shift up',
    );
    final Map<String, Object?> first =
        jsonDecode(await welcome as String) as Map<String, Object?>;
    expect(first['type'], 'welcome');

    final Map<String, Object?> state = await messages
        .map((dynamic raw) => jsonDecode(raw as String) as Map<String, Object?>)
        .firstWhere(
          (Map<String, Object?> message) => message['type'] == 'state',
        );
    expect(state['gearIndex'], 6);
    expect(state['gearNumber'], 7);
    expect(state['profileId'], 'road12');
  });

  test('a console port of -1 serves no console at all', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
      requestedConsolePort: -1,
    );
    await publisher.start();
    addTearDown(publisher.dispose);

    expect(publisher.consoleToken, isEmpty);
    expect(publisher.consoleUrl('127.0.0.1'), isNull);
  });
}
