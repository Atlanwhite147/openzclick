/// Sockets of a page, when the browser grants them.
///
/// A normal page has no TCP server, no mDNS announcement and no Bluetooth
/// peripheral role. An Isolated Web App does: Chrome gives it Direct Sockets,
/// gated by a `permissions_policy` in its manifest. This file is the seam
/// between that API and the rest of the application, so the bridge can be
/// written once against [DirectSocketsHost] and tested with a fake.
library;

import 'dart:typed_data';

/// A connection accepted by [SocketServer].
abstract interface class SocketPeer {
  /// Identifier, unique for the lifetime of the connection.
  String get id;

  /// Remote address, for logs.
  String get label;

  /// Bytes written by the peer.
  Stream<Uint8List> get incoming;

  /// Writes [bytes] to the peer.
  ///
  /// The returned future completes once the bytes have left for the socket, so a
  /// caller that sends twice in a row can await the first instead of racing it.
  Future<void> send(List<int> bytes);

  /// Closes the connection.
  Future<void> close();
}

/// A TCP server owned by the page.
abstract interface class SocketServer {
  /// Port actually bound, which may differ from the requested one.
  int get port;

  /// Connections, in arrival order.
  Stream<SocketPeer> get peers;

  /// Number of open connections.
  int get peerCount;

  /// Closes the server and every connection.
  Future<void> close();
}

/// A UDP socket able to send to a multicast group.
///
/// Bound mode is refused to a page by the local network permission; connected
/// mode is not, which is enough to announce a service. Answering a query needs
/// the bound mode, so the bridge announces on a timer instead.
abstract interface class MulticastSender {
  /// Local port the packets leave from.
  int get localPort;

  /// Sends [bytes] to the group.
  void send(List<int> bytes);

  /// Releases the socket.
  Future<void> close();
}

/// Everything the bridge needs from the host.
abstract interface class DirectSocketsHost {
  /// Listens on [port], on every interface.
  Future<SocketServer> listen(int port);

  /// Opens the sender used to announce the service on 224.0.0.251:5353.
  Future<MulticastSender> announceSender();

  /// Local IPv4 address of this host, `null` when it cannot be discovered.
  Future<String?> localAddress();
}
