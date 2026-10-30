import 'dart:async';
import 'dart:io';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';

import 'android_multicast.dart';

/// Publishes the bridge on the local network with the OpenBikeControl protocol.
///
/// One transport at a time: starting replaces the previous announcement, and
/// the same implementation runs on every platform because it only uses
/// `dart:io`.
class NetworkPublisher {
  /// Creates a publisher for [instanceName].
  NetworkPublisher({
    this.instanceName = 'openzclick',
    this.advertise = true,
    this.port = defaultPort,
  }) {
    _transport = MdnsTcpTransport(
      instanceName: instanceName,
      port: port,
      advertiser: advertise ? DartMdnsAdvertiser() : NoopMdnsAdvertiser(),
      keymap: Keymap.defaults('openzclick'),
    );
    _subscription = _transport.events.listen(_onEvent);
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
  final bool advertise;

  /// Requested TCP port, 0 for an ephemeral one.
  final int port;

  late final MdnsTcpTransport _transport;
  StreamSubscription<TransportEvent>? _subscription;

  /// True when the announcement and the TCP server are running.
  bool running = false;

  /// TCP port to connect to, null when stopped.
  int? listeningPort;

  /// Local address to type into an application that cannot discover the service.
  String? address;

  /// Number of connected applications.
  int peers = 0;

  /// Last error, cleared on a successful start.
  String? error;

  /// Called whenever [running], [port], [peers] or [error] changes.
  void Function()? onChanged;

  void _notify() => onChanged?.call();

  /// Starts the announcement and the TCP server.
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
    _notify();
  }

  /// Stops the server and withdraws the announcement.
  Future<void> stop() async {
    await _transport.stop();
    await AndroidMulticast.release();
    running = false;
    listeningPort = null;
    address = null;
    peers = 0;
    _notify();
  }

  /// Sends [action] to every connected application.
  Future<void> publish(Action action) async {
    if (!running) return;
    await _transport.emit(action);
  }

  /// First non-loopback IPv4 address, preferred over container bridges.
  static Future<String?> _localAddress() async {
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      const List<String> excluded = <String>[
        'docker',
        'br-',
        'veth',
        'virbr',
        'lxc',
        'waydroid',
        'tun',
        'tap',
        'tailscale',
      ];
      for (final NetworkInterface interface in interfaces) {
        if (excluded.any(interface.name.startsWith)) continue;
        for (final InternetAddress candidate in interface.addresses) {
          if (!candidate.isLoopback) return candidate.address;
        }
      }
    } catch (_) {
      // A host without interfaces still gets a listening socket.
    }
    return null;
  }

  void _onEvent(TransportEvent event) {
    if (event is TransportConnected) {
      peers += 1;
    } else if (event is TransportDisconnected) {
      peers = peers > 0 ? peers - 1 : 0;
    } else if (event is TransportError) {
      error = event.message;
    }
    _notify();
  }

  /// Releases the transport and the subscription.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    if (running) {
      await _transport.stop();
      running = false;
    }
  }
}
