/// What the application needs from a publication towards a training app.
///
/// One output, one transport: the native implementation opens a TCP server and
/// announces it over mDNS, the browser one dials a bridge instead. The console
/// part lives here too, because the interface shows it in the same card on both
/// hosts: a native bridge *serves* consoles, a page *is* one.
library;

import 'package:openzclick_core/openzclick_core.dart';

/// Publication state read by the interface.
abstract interface class PublisherPort {
  /// Called whenever the state below changes.
  void Function()? onChanged;

  /// True when the publication runs.
  bool get running;

  /// True when the service is announced over mDNS.
  bool get advertise;

  /// Requested port, `0` for an ephemeral one.
  int get port;

  /// Port actually in use, `null` while stopped.
  int? get listeningPort;

  /// Address to type into an application that cannot discover the service.
  String? get address;

  /// Number of connected applications.
  int get peers;

  /// Last fault, `null` when the last operation succeeded.
  String? get error;

  /// Starts announcing and listening.
  Future<void> start();

  /// Stops both.
  Future<void> stop();

  /// Sends [action] to every connected application.
  Future<void> publish(Action action);

  /// Releases everything.
  Future<void> dispose();

  /// URL a browser console dials, `null` when this host serves no console.
  ///
  /// [host] is the address the rider can reach from the other device: the bridge
  /// cannot guess which of its interfaces the phone sees.
  String? consoleUrl(String host);

  /// Code a console must present, empty when there is no relay.
  String get consoleToken;

  /// Number of connected consoles.
  int get consoles;

  /// Port of the console relay, `null` when this host serves none.
  ///
  /// The address alone is not enough for a QR code: a phone also needs the port
  /// to dial, and it is not the one the training application uses.
  int? get consolePort;

  /// Actions typed in a console: applied exactly like a controller press.
  Stream<Action> get consoleActions;

  /// Publishes the state the consoles display.
  Future<void> publishConsoleState({
    required String profileId,
    required int gearIndex,
    required int gearCount,
    required String mode,
    required String lastAction,
  });
}

/// A publisher that is itself the console of a bridge running elsewhere.
///
/// A page cannot listen: it dials. Everything the interface needs to show the
/// connection lives here, so the target screen has one card to read.
abstract interface class ConsoleClient {
  /// True when the WebSocket to the bridge is open.
  bool get consoleConnected;

  /// Address of the bridge, `null` when not connected.
  String? get consoleAddress;

  /// Last connection fault, `null` when the last attempt succeeded.
  String? get consoleError;

  /// State published by the bridge, applied by the gear engine.
  Stream<Map<String, Object?>> get bridgeStates;

  /// Dials the console endpoint of a bridge.
  ///
  /// [host] accepts `192.168.1.24`, `192.168.1.24:47124` or a full `ws://` URL,
  /// because a rider copies whatever the bridge screen shows.
  Future<void> connectConsole(String host, String code);

  /// Closes the connection to the bridge.
  Future<void> disconnectConsole();
}
