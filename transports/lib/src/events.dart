/// Events published by transports towards the application layer.
///
/// A transport is an event source: it never returns business values, everything
/// goes through the [Transport.events] stream. This layer knows nothing about
/// the user interface or about the injection technique: it only describes what
/// happens (peer connected, button press received, protocol message, fault) so
/// that the application can decide.
library;

import 'package:openzclick_core/openzclick_core.dart';

/// Event emitted by a transport.
///
/// Every event carries the identifier of the transport that produced it, which
/// makes it possible to merge several transports into a single diagnostic
/// stream without losing the origin.
sealed class TransportEvent {
  /// Builds an event attributed to [transportId].
  const TransportEvent({required this.transportId});

  /// Identifier of the emitting transport (see [Transport.id]).
  final String transportId;
}

/// A peer (network client, Bluetooth central, target application) just
/// connected to the transport.
class TransportConnected extends TransportEvent {
  /// Builds a connection event.
  const TransportConnected({
    required super.transportId,
    required this.peerId,
    this.label,
  });

  /// Peer identifier, stable for the whole lifetime of the connection.
  final String peerId;

  /// Human readable description of the peer (remote address, advertised name),
  /// when known.
  final String? label;

  @override
  String toString() =>
      'TransportConnected($transportId, $peerId${label == null ? '' : ', $label'})';
}

/// A peer disconnected, either on purpose or after a fault.
class TransportDisconnected extends TransportEvent {
  /// Builds a disconnection event.
  const TransportDisconnected({
    required super.transportId,
    required this.peerId,
    this.reason,
  });

  /// Identifier of the peer that disconnected.
  final String peerId;

  /// Readable cause of the disconnection, `null` when it was intentional.
  final String? reason;

  @override
  String toString() => 'TransportDisconnected($transportId, $peerId, '
      '${reason ?? 'requested close'})';
}

/// A non fatal fault occurred: invalid frame, unmapped action, failed write.
///
/// The transport stays usable after such an event; fatal conditions (port
/// already taken, missing backend) are raised by [Transport.start].
class TransportError extends TransportEvent {
  /// Builds a fault event.
  const TransportError({
    required super.transportId,
    required this.message,
    this.peerId,
    this.cause,
  });

  /// Human readable message, meant for logging or a diagnostic screen.
  final String message;

  /// Concerned peer, `null` when the fault is global to the transport.
  final String? peerId;

  /// Original exception, kept for in-depth diagnosis.
  final Object? cause;

  @override
  String toString() => 'TransportError($transportId, '
      '${peerId == null ? '' : '$peerId: '}$message)';
}

/// A normalized action was received and must be applied to the target
/// application.
class TransportActionReceived extends TransportEvent {
  /// Builds an action event.
  const TransportActionReceived({
    required super.transportId,
    required this.action,
    this.peerId,
    this.value = 1,
  });

  /// Normalized action resolved from the transport binding table.
  final Action action;

  /// Peer that produced the press, `null` when the transport has no notion of
  /// peer (local injection).
  final String? peerId;

  /// Raw button value: `1` for a binary press, `2..255` for an analog
  /// component.
  final int value;

  @override
  String toString() => 'TransportActionReceived($transportId, ${action.name}, '
      'value $value${peerId == null ? '' : ', $peerId'})';
}

/// A protocol message was decoded as is.
///
/// Published for every received frame, including the ones that also yield a
/// [TransportActionReceived]: the diagnostic screen can therefore show the raw
/// traffic without translating it into actions.
class TransportMessageReceived extends TransportEvent {
  /// Builds a message event.
  const TransportMessageReceived({
    required super.transportId,
    required this.message,
    this.peerId,
  });

  /// Message decoded by the core protocol layer.
  final ObcMessage message;

  /// Emitting peer, `null` when the message originates from the local layer.
  final String? peerId;

  @override
  String toString() =>
      'TransportMessageReceived($transportId, $message, ${peerId ?? 'local'})';
}

/// The grade simulated by the home trainer changed.
///
/// Event specific to the home trainer proxy: other transports never produce it.
class TransportGradeUpdate extends TransportEvent {
  /// Builds a grade event.
  const TransportGradeUpdate({
    required super.transportId,
    required this.gradePercent,
  });

  /// Grade in percent, positive uphill.
  final double gradePercent;

  @override
  String toString() => 'TransportGradeUpdate($transportId, '
      '${gradePercent.toStringAsFixed(1)} %)';
}
