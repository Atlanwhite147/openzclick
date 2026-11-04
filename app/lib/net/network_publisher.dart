import 'dart:async';
import 'dart:io';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';

import 'android_multicast.dart';
import 'local_address.dart';
import 'publisher_port.dart';

/// Publishes the bridge on the local network with the OpenBikeControl protocol.
///
/// One transport at a time: starting replaces the previous announcement, and
/// the same implementation runs on every native platform because it only uses
/// `dart:io`. A browser cannot do any of it; [WebPublisher] stands in there.
///
/// Two doors are opened, because a training application is not the only thing
/// that wants the actions: the TCP server an application connects to, and a
/// WebSocket relay a browser console dials. The relay is what makes the same
/// bridge usable from a page, including on an iPhone, where no browser exposes
/// Web Bluetooth.
class NetworkPublisher implements PublisherPort {
  /// Creates a publisher for [instanceName].
  ///
  /// [requestedConsolePort] is the WebSocket console; pass `0` for an ephemeral
  /// port, or a negative value to serve no console at all.
  NetworkPublisher({
    this.instanceName = 'openzclick',
    this.advertise = true,
    this.port = defaultPort,
    this.requestedConsolePort = WebSocketRelayTransport.defaultPort,
  }) {
    _transport = MdnsTcpTransport(
      instanceName: instanceName,
      port: port,
      advertiser: advertise ? DartMdnsAdvertiser() : NoopMdnsAdvertiser(),
      keymap: Keymap.defaults('openzclick'),
    );
    _subscription = _transport.events.listen(_onEvent);
    if (requestedConsolePort >= 0) {
      _relay = WebSocketRelayTransport(port: requestedConsolePort);
      _relaySubscription = _relay!.events.listen(_onRelayEvent);
    }
  }

  /// Preferred port: stable, so that an application can remember it.
  static const int defaultPort = 47123;

  /// Name announced on the network.
  final String instanceName;

  /// Whether the service is announced with mDNS.
  ///
  /// iOS refuses multicast without an entitlement granted by Apple: the server
  /// still listens, and the address is displayed so that a client can be
  /// configured by hand.
  @override
  final bool advertise;

  /// Requested TCP port, 0 for an ephemeral one.
  @override
  final int port;

  /// Requested console port; a negative value disables the console relay.
  final int requestedConsolePort;

  late final MdnsTcpTransport _transport;
  WebSocketRelayTransport? _relay;
  StreamSubscription<TransportEvent>? _subscription;
  StreamSubscription<TransportEvent>? _relaySubscription;
  final StreamController<Action> _consoleActions =
      StreamController<Action>.broadcast();

  /// True when the announcement and the TCP server are running.
  @override
  bool running = false;

  /// TCP port to connect to, null when stopped.
  @override
  int? listeningPort;

  /// Local address to type into an application that cannot discover the service.
  @override
  String? address;

  /// Number of connected applications.
  @override
  int peers = 0;

  /// Number of connected browser consoles.
  @override
  int get consoles => _relay?.consoleCount ?? 0;

  /// Port the console relay listens on, `null` when it is off.
  @override
  int? get consolePort {
    final WebSocketRelayTransport? relay = _relay;
    if (relay == null || !relay.isRunning) return null;
    return relay.listeningPort;
  }

  /// Last error, cleared on a successful start.
  @override
  String? error;

  /// Called whenever [running], [port], [peers] or [error] changes.
  @override
  void Function()? onChanged;

  /// Code a console must present, empty when the relay is disabled.
  @override
  String get consoleToken => _relay?.token ?? '';

  /// Actions typed in a console.
  @override
  Stream<Action> get consoleActions => _consoleActions.stream;

  void _notify() => onChanged?.call();

  /// URL a browser console dials, `null` when the relay is off or stopped.
  @override
  String? consoleUrl(String host) => _relay?.urlFor(host);

  /// Starts the announcement, the TCP server and the console relay.
  @override
  Future<void> start() async {
    error = null;
    try {
      await AndroidMulticast.acquire();
      await _transport.start();
      running = true;
      listeningPort = _transport.listeningPort;
      address = await _localAddress();
    } catch (e) {
      running = false;
      listeningPort = null;
      address = null;
      error = e.toString();
    }
    final WebSocketRelayTransport? relay = _relay;
    if (relay != null) {
      try {
        await relay.start();
      } catch (e) {
        // The application link works without the console: report it, do not
        // take the whole publication down.
        error ??= 'console relay: $e';
      }
    }
    _notify();
  }

  /// Stops the server, the relay and the announcement.
  @override
  Future<void> stop() async {
    await _relay?.stop();
    await _transport.stop();
    await AndroidMulticast.release();
    running = false;
    listeningPort = null;
    address = null;
    peers = 0;
    _notify();
  }

  /// Sends [action] to every connected application, and to every console so the
  /// page can show what the controller just did.
  @override
  Future<void> publish(Action action) async {
    if (!running) return;
    await _transport.emit(action);
    await _relay?.emit(action);
  }

  /// Publishes the state the consoles display.
  @override
  Future<void> publishConsoleState({
    required String profileId,
    required int gearIndex,
    required int gearCount,
    required String mode,
    required String lastAction,
  }) async {
    await _relay?.publishState(<String, Object?>{
      'profileId': profileId,
      'gearIndex': gearIndex,
      'gearCount': gearCount,
      'gearNumber': gearIndex + 1,
      'mode': mode,
      'lastAction': lastAction,
    });
  }

  /// Address a phone on the same network should type.
  ///
  /// `null` when nothing usable exists, which the screen shows as "this
  /// device" rather than as a plausible address that reaches nothing.
  static Future<String?> _localAddress() async {
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      return chooseLocalAddress(<LocalInterface>[
        for (final NetworkInterface interface in interfaces)
          LocalInterface(
            name: interface.name,
            addresses: <String>[
              for (final InternetAddress address in interface.addresses)
                if (!address.isLoopback) address.address,
            ],
          ),
      ]);
    } catch (_) {
      // A host without interfaces still gets a listening socket.
    }
    return null;
  }

  void _onEvent(TransportEvent event) {
    if (event is TransportConnected) {
      peers += 1;
      // A connection is the sign the publication works: whatever went wrong
      // before it (a frame sent before the application connected, a peer that
      // left mid-write) no longer describes the current state.
      error = null;
    } else if (event is TransportDisconnected) {
      peers = peers > 0 ? peers - 1 : 0;
    } else if (event is TransportActionReceived) {
      // A button pressed by a connected application is an input like any other:
      // it takes the same path as a message typed in a console, so the gear
      // engine and the local injection both see it. Dropping it here is the
      // worst kind of failure — the peer is counted, the frame is decoded, the
      // screen says a client is connected, and nothing moves.
      _consoleActions.add(event.action);
    } else if (event is TransportError) {
      // A fault attributed to no peer while nobody is connected is a transient
      // hint, not a state: storing "no client connected" would leave a
      // permanent error on screen after the application finally connects.
      if (event.peerId != null || peers > 0) {
        error = event.message;
      }
    }
    _notify();
  }

  void _onRelayEvent(TransportEvent event) {
    switch (event) {
      case TransportActionReceived(:final Action action):
        _consoleActions.add(action);
      case TransportError(:final String message):
        // A malformed console message must not hide the state of the link an
        // application uses: it is reported, not stored.
        if (consoles == 0) error ??= message;
      case TransportConnected():
      case TransportDisconnected():
        _notify();
      case TransportMessageReceived():
      case TransportGradeUpdate():
        break;
    }
    _notify();
  }

  /// Releases the transport and the subscription.
  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _relaySubscription?.cancel();
    _relaySubscription = null;
    if (running) {
      await stop();
    }
    await _relay?.dispose();
    await _consoleActions.close();
  }
}

/// Builds the publication of the current host.
PublisherPort createPublisher({
  bool advertise = true,
  int port = NetworkPublisher.defaultPort,
}) => NetworkPublisher(advertise: advertise, port: port);
