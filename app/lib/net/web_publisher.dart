/// Publication in a browser: the page is the console of a bridge running
/// elsewhere.
///
/// A page cannot open a listening socket, announce a service or act as a
/// Bluetooth peripheral, so it can never be the bridge a training application
/// discovers. What it can do is dial the bridge: the buttons of the page, and the
/// controller the page pairs over Web Bluetooth, travel to the bridge over a
/// WebSocket, and the bridge publishes them as it always does. This is also the
/// only route that works on an iPhone, where no browser exposes Web Bluetooth.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:web/web.dart' as web;

import 'console_endpoint.dart';
import 'publisher_port.dart';

/// Publication state of the browser build: a client of the bridge.
class WebPublisher implements PublisherPort, ConsoleClient {
  /// Builds the publisher.
  WebPublisher({this.advertise = true, this.port = defaultPort});

  /// Console port of the native bridge, used when the rider types an address
  /// without a port.
  static const int defaultPort = ConsoleEndpoint.defaultPort;

  /// Path of the console endpoint on the bridge.
  static const String consolePath = ConsoleEndpoint.path;

  final StreamController<Map<String, Object?>> _states =
      StreamController<Map<String, Object?>>.broadcast();

  web.WebSocket? _socket;
  String? _address;
  String? _error;

  @override
  void Function()? onChanged;

  /// True when connected to a bridge.
  @override
  bool get running => consoleConnected;

  @override
  final bool advertise;

  @override
  final int port;

  /// Always `null`: a page cannot listen.
  @override
  int? get listeningPort => null;

  /// Address of the connected bridge, `null` when not connected.
  @override
  String? get address => _address;

  /// One console: this page.
  @override
  int get peers => consoleConnected ? 1 : 0;

  /// Number of consoles: this page is one when connected.
  @override
  int get consoles => peers;

  /// The page serves no console of its own.
  @override
  int? get consolePort => null;

  @override
  String? get error => _error;

  /// Code the page presents: none, the bridge issues it.
  @override
  String get consoleToken => '';

  /// The page dials; it serves no console of its own.
  @override
  String? consoleUrl(String host) => null;

  /// Actions of other consoles: on this host the page *is* the console.
  @override
  Stream<Action> get consoleActions => const Stream<Action>.empty();

  /// State published by the bridge, read by the gear engine.
  @override
  Stream<Map<String, Object?>> get bridgeStates => _states.stream;

  @override
  bool get consoleConnected => _socket != null;

  @override
  String? get consoleAddress => _address;

  @override
  String? get consoleError => _error;

  void _notify() => onChanged?.call();

  /// Starting the publication dials nothing: the interface gives the address.
  @override
  Future<void> start() async {
    // Deliberately not a silent no-op: a rider who flipped the switch must
    // learn that a page cannot listen, and what to do instead.
    _error =
        'A browser cannot listen on the network: enter the address of the '
        'bridge running on your local network';
    _notify();
  }

  @override
  Future<void> stop() => disconnectConsole();

  /// Sends [action] to the bridge. Ignored while disconnected.
  @override
  Future<void> publish(Action action) async {
    final web.WebSocket? socket = _socket;
    if (socket == null) return;
    socket.send(jsonEncode(<String, Object?>{'action': action.name}).toJS);
  }

  @override
  Future<void> publishConsoleState({
    required String profileId,
    required int gearIndex,
    required int gearCount,
    required String mode,
    required String lastAction,
  }) async {
    // The bridge owns the state the consoles display: nothing to publish from
    // the page.
  }

  /// Builds the WebSocket URL from whatever the rider typed.
  ///
  /// The rule lives in [ConsoleEndpoint], which is pure text handling and tested
  /// on the host rather than in a browser.
  static String buildUrl(String host, String code) =>
      ConsoleEndpoint.build(host, code);

  @override
  Future<void> connectConsole(String host, String code) async {
    await disconnectConsole();
    final String url = buildUrl(host, code);
    _address = url;
    _error = null;
    try {
      final web.WebSocket socket = web.WebSocket(url);
      socket.binaryType = 'arraybuffer';
      _socket = socket;
      socket.onopen = ((web.Event _) {
        _error = null;
        _notify();
      }).toJS;
      socket.onmessage = ((web.MessageEvent event) {
        final JSAny? data = event.data;
        if (data.isA<JSString>()) _onMessage((data! as JSString).toDart);
      }).toJS;
      socket.onerror = ((web.Event _) {
        // A refused console and an unreachable host look the same here: the
        // bridge answers 403 for a wrong code, the browser hides the reason.
        _fail(
          'the bridge refused the connection: check the address and the '
          'code it displays',
        );
      }).toJS;
      socket.onclose = ((web.CloseEvent _) {
        if (_socket != null) _fail('the bridge closed the console');
      }).toJS;
    } catch (e) {
      _fail('$e');
    }
    _notify();
  }

  void _onMessage(String data) {
    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    switch (decoded['type']) {
      case 'welcome':
        final Object? state = decoded['state'];
        if (state is Map<String, Object?> && state.isNotEmpty) {
          _states.add(state);
        }
        _notify();
      case 'state':
        _states.add(decoded);
        _notify();
      case 'action':
        // The bridge echoes the actions it applies, including the ones of the
        // physical controller: the page shows them, no need to reply.
        break;
    }
  }

  void _fail(String message) {
    final web.WebSocket? socket = _socket;
    _socket = null;
    _error = message;
    try {
      socket?.close();
    } catch (_) {
      // A socket that never opened has nothing to close.
    }
    _notify();
  }

  @override
  Future<void> disconnectConsole() async {
    final web.WebSocket? socket = _socket;
    _socket = null;
    _address = null;
    _error = null;
    try {
      socket?.close();
    } catch (_) {
      // Same: closing twice is not an error worth reporting.
    }
    _notify();
  }

  @override
  Future<void> dispose() async {
    await disconnectConsole();
    await _states.close();
  }
}

/// Builds the publication of the current host.
PublisherPort createPublisher({
  bool advertise = true,
  int port = WebPublisher.defaultPort,
}) => WebPublisher(advertise: advertise, port: port);
