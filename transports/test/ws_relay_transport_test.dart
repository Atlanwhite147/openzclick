import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';
import 'package:test/test.dart';

/// Reads messages from the relay until one matches [predicate].
Future<Map<String, Object?>> nextMessage(
  StreamQueue<Object?> queue, {
  bool Function(Map<String, Object?> message)? predicate,
}) async {
  while (true) {
    final Object? data = await queue.next;
    if (data is! String) continue;
    final Object? decoded = jsonDecode(data);
    if (decoded is! Map<String, Object?>) continue;
    if (predicate == null || predicate(decoded)) return decoded;
  }
}

/// Minimal queue over a WebSocket stream, so a test can await messages one by
/// one without losing the ones that arrive early.
class StreamQueue<T> {
  StreamQueue(Stream<T> stream) {
    _subscription = stream.listen(
      (T value) {
        if (_waiting.isNotEmpty) {
          _waiting.removeAt(0).complete(value);
        } else {
          _buffered.add(value);
        }
      },
      onError: (Object e) {
        for (final Completer<T> completer in _waiting) {
          completer.completeError(e);
        }
        _waiting.clear();
      },
    );
  }

  late final StreamSubscription<T> _subscription;
  final List<T> _buffered = <T>[];
  final List<Completer<T>> _waiting = <Completer<T>>[];

  Future<T> get next {
    if (_buffered.isNotEmpty) {
      return Future<T>.value(_buffered.removeAt(0));
    }
    final Completer<T> completer = Completer<T>();
    _waiting.add(completer);
    return completer.future.timeout(const Duration(seconds: 5));
  }

  Future<void> cancel() => _subscription.cancel();
}

Future<WebSocketRelayTransport> startRelay({
  String? token,
  int port = 0,
}) async {
  final WebSocketRelayTransport relay = WebSocketRelayTransport(
    token: token,
    port: port,
    bindAddress: InternetAddress.loopbackIPv4,
  );
  await relay.start();
  return relay;
}

Future<WebSocket> connectConsole(
  WebSocketRelayTransport relay, {
  String? token,
}) async {
  final String code = token ?? relay.token;
  return WebSocket.connect(
    'ws://127.0.0.1:${relay.listeningPort}${WebSocketRelayTransport.consolePath}'
    '?token=$code',
  );
}

void main() {
  test('a console receives the welcome message and the bridge state', () async {
    final WebSocketRelayTransport relay = await startRelay();
    addTearDown(relay.dispose);
    await relay.publishState(<String, Object?>{'gear': 6, 'gearCount': 12});

    final WebSocket socket = await connectConsole(relay);
    addTearDown(socket.close);
    final StreamQueue<Object?> queue = StreamQueue<Object?>(socket);
    addTearDown(queue.cancel);

    final Map<String, Object?> welcome = await nextMessage(queue);
    expect(welcome['type'], 'welcome');
    expect(welcome['version'], 1);
    expect(welcome['state'], <String, Object?>{'gear': 6, 'gearCount': 12});
  });

  test('an action typed in the console reaches the bridge', () async {
    final WebSocketRelayTransport relay = await startRelay();
    addTearDown(relay.dispose);
    final List<TransportActionReceived> received = <TransportActionReceived>[];
    final StreamSubscription<TransportEvent> subscription = relay.events.listen(
      (TransportEvent event) {
        if (event is TransportActionReceived) received.add(event);
      },
    );
    addTearDown(subscription.cancel);

    final WebSocket socket = await connectConsole(relay);
    addTearDown(socket.close);
    socket.add(jsonEncode(<String, Object?>{'action': 'shiftUp'}));

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, hasLength(1));
    expect(received.single.action, Action.shiftUp);
    expect(received.single.transportId, 'ws_relay');
  });

  test('the bridge pushes its actions and state to every console', () async {
    final WebSocketRelayTransport relay = await startRelay();
    addTearDown(relay.dispose);
    final WebSocket socket = await connectConsole(relay);
    addTearDown(socket.close);
    final StreamQueue<Object?> queue = StreamQueue<Object?>(socket);
    addTearDown(queue.cancel);
    await nextMessage(queue); // welcome

    await relay.emit(Action.shiftDown);
    final Map<String, Object?> action = await nextMessage(
      queue,
      predicate: (Map<String, Object?> message) => message['type'] == 'action',
    );
    expect(action['action'], 'shiftDown');

    await relay.publishState(<String, Object?>{'gear': 7});
    final Map<String, Object?> state = await nextMessage(
      queue,
      predicate: (Map<String, Object?> message) => message['type'] == 'state',
    );
    expect(state['gear'], 7);
  });

  test('a wrong code is refused', () async {
    final WebSocketRelayTransport relay = await startRelay(token: 'abcd');
    addTearDown(relay.dispose);

    await expectLater(
      connectConsole(relay, token: 'zzzz'),
      throwsA(isA<WebSocketException>()),
    );
    expect(relay.consoleCount, 0);
  });

  test('an unknown action is reported and changes nothing', () async {
    final WebSocketRelayTransport relay = await startRelay();
    addTearDown(relay.dispose);
    final List<TransportEvent> events = <TransportEvent>[];
    final StreamSubscription<TransportEvent> subscription = relay.events.listen(
      events.add,
    );
    addTearDown(subscription.cancel);

    final WebSocket socket = await connectConsole(relay);
    addTearDown(socket.close);
    socket.add(jsonEncode(<String, Object?>{'action': 'teleport'}));

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(events.whereType<TransportActionReceived>(), isEmpty);
    expect(
      events.whereType<TransportError>().single.message,
      contains('unknown action'),
    );
  });

  test('a console that leaves is reported and does not leak', () async {
    final WebSocketRelayTransport relay = await startRelay();
    addTearDown(relay.dispose);
    final List<TransportEvent> events = <TransportEvent>[];
    final StreamSubscription<TransportEvent> subscription = relay.events.listen(
      events.add,
    );
    addTearDown(subscription.cancel);

    final WebSocket socket = await connectConsole(relay);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(relay.consoleCount, 1);

    await socket.close();
    for (int attempt = 0; attempt < 50 && relay.consoleCount > 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(relay.consoleCount, 0);
    expect(events.whereType<TransportDisconnected>(), isNotEmpty);
  });

  test('the code is short, typed once, and unambiguous', () {
    for (int attempt = 0; attempt < 20; attempt++) {
      final String token = WebSocketRelayTransport.generateToken();
      expect(token, hasLength(4));
      expect(token, isNot(matches(RegExp('[01oi]'))));
    }
  });
}
