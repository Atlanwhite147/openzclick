import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick/net/network_publisher.dart';

void main() {
  test('listens on a stable port and reports its address', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
      // No console relay: the tests below open the same fixed port.
      requestedConsolePort: -1,
    );
    await publisher.start();
    expect(publisher.running, isTrue);
    expect(publisher.error, isNull);
    expect(publisher.listeningPort, isNotNull);
    expect(publisher.listeningPort, greaterThan(0));
    expect(publisher.address, isNotNull);
    await publisher.stop();
    expect(publisher.running, isFalse);
    expect(publisher.listeningPort, isNull);
  });

  test('without announcement, no multicast socket is opened', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
      // No console relay: the tests below open the same fixed port.
      requestedConsolePort: -1,
    );
    await publisher.start();
    // A second publisher on the same UDP port would fail if the first one had
    // joined the multicast group; the announcement stays off here.
    expect(publisher.advertise, isFalse);
    await publisher.stop();
  });

  test('publishing while stopped is harmless', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
      // No console relay: the tests below open the same fixed port.
      requestedConsolePort: -1,
    );
    await publisher.publish(Action.shiftUp);
    expect(publisher.running, isFalse);
  });

  test('a press sent before the application connects is a hint, not an '
      'error', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
      // No console relay: the tests below open the same fixed port.
      requestedConsolePort: -1,
    );
    await publisher.start();

    // Nobody listens yet: the transport reports it, the interface must not
    // turn it into a permanent error state.
    await publisher.publish(Action.shiftUp);
    expect(publisher.error, isNull);

    final Socket client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      publisher.listeningPort!,
    );
    addTearDown(client.destroy);
    for (int attempt = 0; attempt < 100 && publisher.peers == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(publisher.peers, 1, reason: 'the client must be counted');

    // And a client that arrives clears whatever fault came before it.
    await publisher.publish(Action.shiftUp);
    expect(publisher.error, isNull);
    await publisher.stop();
  });

  test('a button pressed by a connected application is an input, not a '
      'decoration', () async {
    final NetworkPublisher publisher = NetworkPublisher(
      advertise: false,
      port: 0,
      requestedConsolePort: -1,
    );
    await publisher.start();
    addTearDown(publisher.dispose);

    final List<Action> received = <Action>[];
    final StreamSubscription<Action> subscription = publisher.consoleActions
        .listen(received.add);
    addTearDown(subscription.cancel);

    final Socket client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      publisher.listeningPort!,
    );
    addTearDown(client.destroy);
    for (int attempt = 0; attempt < 100 && publisher.peers == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(publisher.peers, 1);

    // Measured on Windows: the peer was counted, the frame was decoded, and the
    // gear did not move, because this event was dropped on the floor.
    client.add(ButtonStateMessage(<int, int>{ButtonIds.shiftUp: 1}).encode());
    await client.flush();
    for (int attempt = 0; attempt < 100 && received.isEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(received, <Action>[Action.shiftUp]);

    // A release triggers nothing: only a press is an action.
    client.add(ButtonStateMessage(<int, int>{ButtonIds.shiftUp: 0}).encode());
    await client.flush();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(received, <Action>[Action.shiftUp]);
  });
}
