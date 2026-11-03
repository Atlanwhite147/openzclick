/// Console relay: the same actions, driven from a browser.
///
/// A page cannot open a listening socket, so a browser can never be the bridge a
/// training application discovers. What it can do is the opposite: connect to the
/// bridge running on the machine where the application runs and drive it. This
/// transport is that door — a WebSocket server that accepts a console, receives
/// its actions, and pushes the bridge state back.
///
/// The protocol is deliberately small, because it only carries what the interface
/// shows: a JSON object per message. Actions travel as
/// `{"action":"shiftUp"}`; the bridge answers with its state,
/// `{"type":"state","gear":6,"gearCount":12,...}`.
///
/// A page is not a trusted peer: it is opened from any origin, so the relay only
/// accepts a console presenting the code the bridge displays, and it never grants
/// anything that the buttons of the bridge itself could not do.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:openzclick_core/openzclick_core.dart';

import 'console_page.dart';
import 'events.dart';
import 'transport.dart';

/// WebSocket server that lets a browser drive the bridge.
///
/// Lifecycle follows [ManagedTransport]: nothing listens before [start].
class WebSocketRelayTransport extends ManagedTransport {
  /// Creates the relay.
  ///
  /// [token] is the code a console must present (`?token=` in the URL). A
  /// random four letter code is generated when none is given, which is what the
  /// interface displays.
  WebSocketRelayTransport({
    String? token,
    this.port = defaultPort,
    InternetAddress? bindAddress,
  })  : token = token ?? generateToken(),
        bindAddress = bindAddress ?? InternetAddress.anyIPv4;

  /// Preferred port, next to the TCP one so a rider types two close numbers.
  static const int defaultPort = 47124;

  /// Path the console socket connects to.
  static const String consolePath = '/console';

  /// Code a console must present.
  final String token;

  /// Requested port, `0` for an ephemeral one.
  final int port;

  /// Address the server listens on.
  final InternetAddress bindAddress;

  final Map<String, WebSocket> _consoles = <String, WebSocket>{};
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  HttpServer? _server;
  int _counter = 0;
  Map<String, Object?> _state = const <String, Object?>{};

  @override
  String get id => 'ws_relay';

  /// Effective listening port, `0` before [start].
  int get listeningPort => _server?.port ?? 0;

  /// Number of connected consoles.
  int get consoleCount => _consoles.length;

  /// Generates the four letter code displayed by the interface.
  ///
  /// Unambiguous on purpose: no `0`/`O`, no `1`/`I`, because the code is read
  /// from a screen and typed on a phone.
  static String generateToken() {
    const String alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    final Random random = Random.secure();
    return List<String>.generate(
      4,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  /// URL a console connects to, `null` while the relay is stopped.
  ///
  /// [host] is the address the rider sees; the relay cannot know which of its
  /// interfaces the phone can reach.
  String? urlFor(String host) {
    if (!isRunning) return null;
    return 'ws://$host:$listeningPort$consolePath?token=$token';
  }

  /// Address a phone opens to get the console, on the same origin as the
  /// socket.
  ///
  /// This is what the QR code points at. It has to be `http://` on this
  /// machine: a hosted page is `https://` and browsers refuse to open a
  /// `ws://` socket from one, which is why the hosted page could never drive a
  /// bridge on a home network.
  String? pageUrlFor(String host) {
    if (!isRunning) return null;
    return 'http://$host:$listeningPort/?token=$token';
  }

  /// Serves the console document, on the same origin and port as the socket.
  Future<void> _servePage(HttpRequest request) async {
    final HttpResponse response = request.response;
    response.headers.contentType = ContentType.html;
    response.headers.set('cache-control', 'no-store');
    // The page and the socket share an origin, so the document has to be
    // reachable by the socket's own callers and by nothing else.
    response
        .write(consolePageHtml(token: request.uri.queryParameters['token']));
    await response.close();
  }

  @override
  Future<void> onStart() async {
    final HttpServer server = await HttpServer.bind(bindAddress, port);
    _server = server;
    server.listen(_onRequest, onError: (Object e) {
      publishError('console relay: $e');
    });
  }

  @override
  Future<void> onStop() async {
    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final List<WebSocket> consoles = _consoles.values.toList(growable: false);
    _consoles.clear();
    for (final WebSocket socket in consoles) {
      await socket.close(WebSocketStatus.goingAway, 'bridge stopped');
      publish(TransportDisconnected(
        transportId: id,
        peerId: _peerIdOf(socket) ?? 'unknown',
        reason: 'bridge stopped',
      ));
    }
    final HttpServer? server = _server;
    _server = null;
    await server?.close(force: true);
  }

  /// Sends [action] to every connected console, so the page can show what the
  /// controller just did.
  @override
  Future<void> emit(Action action) async {
    _broadcast(<String, Object?>{
      'type': 'action',
      'action': action.name,
      'label': action.label,
    });
  }

  /// Publishes the bridge state to every console.
  ///
  /// Replaces the previous state: a console that connects later receives the
  /// current one in its welcome message, which keeps the page correct without a
  /// request of its own.
  Future<void> publishState(Map<String, Object?> state) async {
    _state = Map<String, Object?>.unmodifiable(state);
    _broadcast(<String, Object?>{'type': 'state', ..._state});
  }

  Future<void> _onRequest(HttpRequest request) async {
    final String path = request.uri.path;
    if (path == '/' || path == '/index.html') {
      await _servePage(request);
      return;
    }
    if (path != consolePath) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    if (request.uri.queryParameters['token'] != token) {
      // No hint about the expected code: a wrong one is only wrong.
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final WebSocket socket = await WebSocketTransformer.upgrade(request);
    _counter += 1;
    final String peerId = 'console-$_counter';
    _consoles[peerId] = socket;
    publish(TransportConnected(
      transportId: id,
      peerId: peerId,
      label: request.connectionInfo?.remoteAddress.address,
    ));
    socket.add(
      jsonEncode(<String, Object?>{
        'type': 'welcome',
        'id': peerId,
        'version': 1,
        'state': _state,
      }),
    );
    _subscriptions.add(
      socket.listen(
        (dynamic data) => _onMessage(peerId, data),
        onDone: () => _onClosed(peerId, socket),
        onError: (Object e) {
          publishError('console $peerId: $e', peerId: peerId);
          _onClosed(peerId, socket);
        },
        cancelOnError: true,
      ),
    );
  }

  void _onMessage(String peerId, dynamic data) {
    if (data is! String) {
      publishError('console $peerId: binary message ignored', peerId: peerId);
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      publishError('console $peerId: not JSON', peerId: peerId);
      return;
    }
    if (decoded is! Map<String, Object?>) {
      publishError('console $peerId: not an object', peerId: peerId);
      return;
    }
    final Object? name = decoded['action'];
    if (name is! String) {
      if (decoded['type'] != 'ping') {
        publishError('console $peerId: no action', peerId: peerId);
      }
      return;
    }
    final Action action = _actionByName(name);
    if (action == Action.none) {
      publishError('console $peerId: unknown action "$name"', peerId: peerId);
      return;
    }
    publish(TransportActionReceived(
      transportId: id,
      action: action,
      peerId: peerId,
    ));
  }

  void _onClosed(String peerId, WebSocket socket) {
    if (_consoles.remove(peerId) == null) return;
    publish(TransportDisconnected(transportId: id, peerId: peerId));
    unawaited(socket.close());
  }

  void _broadcast(Map<String, Object?> message) {
    if (_consoles.isEmpty) return;
    final String payload = jsonEncode(message);
    for (final WebSocket socket in _consoles.values.toList(growable: false)) {
      socket.add(payload);
    }
  }

  String? _peerIdOf(WebSocket socket) {
    for (final MapEntry<String, WebSocket> entry in _consoles.entries) {
      if (identical(entry.value, socket)) return entry.key;
    }
    return null;
  }

  static Action _actionByName(String name) {
    for (final Action action in Action.values) {
      if (action.name == name) return action;
    }
    return Action.none;
  }
}
