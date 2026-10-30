/// Common contract shared by every transport of the bridge.
///
/// A transport links controller presses to the target application, whatever the
/// medium: local network advertised through mDNS, Bluetooth peripheral, local
/// injection, or home trainer proxy. The application only knows this interface,
/// which allows swapping the medium without touching the rest of the code.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:openzclick_core/openzclick_core.dart';

import 'events.dart';

/// Medium through which actions travel between the bridge and an application.
///
/// Lifecycle: [start] makes the transport operational, [stop] makes it inert
/// and releases its resources. Both methods are idempotent.
abstract class Transport {
  /// Technical identifier of the transport: `mdns_tcp`, `ble_peripheral`,
  /// `local`, `proxy`.
  String get id;

  /// Starts the transport and begins publishing events.
  ///
  /// Throws [UnimplementedError] when the targeted platform is not wired yet
  /// (see the relevant implementation), [StateError] on invalid use (port
  /// already taken, double start).
  Future<void> start();

  /// Stops the transport, closes open connections and stops publishing traffic
  /// events.
  Future<void> stop();

  /// Transport event stream.
  ///
  /// Broadcast stream: several listeners may subscribe at the same time. Events
  /// emitted before a listener subscribes are lost, which is the expected
  /// behaviour for real time traffic.
  Stream<TransportEvent> get events;

  /// Sends [action] through the transport.
  ///
  /// For an uplink transport (network, Bluetooth peripheral), the action is
  /// encoded as a protocol frame and pushed to the peers. For a local
  /// transport, it is translated into a key or a tap. Throws [StateError] when
  /// the transport is stopped, [ArgumentError] when the action has no binding
  /// in the transport configuration.
  Future<void> emit(Action action);
}

/// Base class for transports that have a single event stream and a
/// running/stopped state.
///
/// Subclasses only implement [onStart] and [onStop]: stream controller handling,
/// state and idempotency stay here, so they do not get duplicated per medium.
abstract class ManagedTransport implements Transport {
  final StreamController<TransportEvent> _controller =
      StreamController<TransportEvent>.broadcast();

  bool _running = false;

  /// True between [start] and [stop].
  bool get isRunning => _running;

  @override
  Stream<TransportEvent> get events => _controller.stream;

  @override
  Future<void> start() async {
    if (_running) {
      return;
    }
    await onStart();
    _running = true;
  }

  @override
  Future<void> stop() async {
    if (!_running) {
      return;
    }
    try {
      await onStop();
    } finally {
      _running = false;
    }
  }

  /// Permanently releases the event stream.
  ///
  /// Call it when the transport will never be restarted; [stop] is enough for a
  /// simple pause.
  Future<void> dispose() async {
    await stop();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  /// Brings the transport up. Called at most once per lifecycle.
  @protected
  Future<void> onStart();

  /// Releases the transport resources. Called at most once per lifecycle, after
  /// [onStart].
  @protected
  Future<void> onStop();

  /// Publishes [event] when the stream is still open.
  @protected
  void publish(TransportEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Publishes a non fatal fault.
  @protected
  void publishError(
    String message, {
    String? peerId,
    Object? cause,
  }) {
    publish(
      TransportError(
        transportId: id,
        message: message,
        peerId: peerId,
        cause: cause,
      ),
    );
  }
}
