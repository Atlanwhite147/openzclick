import 'dart:async';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';

/// Publishes the bridge on the local network with the OpenBikeControl protocol.
///
/// One transport at a time: starting replaces the previous announcement, and
/// the same implementation runs on every platform because it only uses
/// `dart:io`.
class NetworkPublisher {
  /// Creates a publisher for [instanceName].
  NetworkPublisher({this.instanceName = 'openzclick'}) {
    _transport = MdnsTcpTransport(
      instanceName: instanceName,
      advertiser: DartMdnsAdvertiser(),
      keymap: Keymap.defaults('openzclick'),
    );
    _subscription = _transport.events.listen(_onEvent);
  }

  /// Name announced on the network.
  final String instanceName;

  late final MdnsTcpTransport _transport;
  StreamSubscription<TransportEvent>? _subscription;

  /// True when the announcement and the TCP server are running.
  bool running = false;

  /// TCP port to connect to, null when stopped.
  int? port;

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
      await _transport.start();
      running = true;
      port = _transport.listeningPort;
    } catch (e) {
      running = false;
      port = null;
      error = e.toString();
    }
    _notify();
  }

  /// Stops the server and withdraws the announcement.
  Future<void> stop() async {
    await _transport.stop();
    running = false;
    port = null;
    peers = 0;
    _notify();
  }

  /// Sends [action] to every connected application.
  Future<void> publish(Action action) async {
    if (!running) return;
    await _transport.emit(action);
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
