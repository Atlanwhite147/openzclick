/// TCP server that splits a byte stream into protocol messages.
///
/// The protocol has no preamble: each frame starts with its type byte and
/// declares its length, which makes the stream self-delimiting. The server
/// therefore imposes no separation between frames: a client may write one frame
/// in several chunks, glue several frames into a single write, or send stray
/// bytes. Splitting is delegated to the core decoder ([ObcCodec]) and the
/// server only accumulates bytes per peer.
library;

import 'dart:async';
import 'dart:io';
import 'package:openzclick_core/openzclick_core.dart';

/// Event produced by [FramedTcpServer].
sealed class ServerEvent {
  /// Builds an event attributed to the peer [peerId].
  const ServerEvent({required this.peerId});

  /// Identifier of the concerned peer.
  final String peerId;
}

/// A client just opened a connection.
class PeerConnected extends ServerEvent {
  /// Builds a connection event.
  const PeerConnected({
    required super.peerId,
    required this.address,
    required this.port,
  });

  /// Remote IP address.
  final String address;

  /// Remote port.
  final int port;

  /// `address:port` label, usable in a log line.
  String get label => '$address:$port';
}

/// A client closed its connection, or the server closed it.
class PeerDisconnected extends ServerEvent {
  /// Builds a disconnection event.
  const PeerDisconnected({required super.peerId, this.reason});

  /// Readable cause of the close, `null` when it comes from the client.
  final String? reason;
}

/// A complete message was decoded for this peer.
class PeerMessage extends ServerEvent {
  /// Builds a message event.
  const PeerMessage({required super.peerId, required this.message});

  /// Message decoded by the core layer.
  final ObcMessage message;
}

/// The stream of this peer produced something unusable.
///
/// The connection is kept: the server drops the offending bytes and resumes
/// splitting at the next valid type byte.
class PeerFault extends ServerEvent {
  /// Builds a fault event.
  const PeerFault({
    required super.peerId,
    required this.message,
    this.cause,
  });

  /// Human readable message.
  final String message;

  /// Original exception, when there is one.
  final Object? cause;
}

/// Multi-client TCP server that publishes decoded messages.
///
/// Port `0` asks the system for an ephemeral port: this is the mode used by the
/// tests, which need neither hardware nor a reserved port. The effective port is
/// readable from [listeningPort] after [start].
class FramedTcpServer {
  /// Creates a server that will listen on [bindAddress] and [port].
  ///
  /// [maxBufferBytes] bounds the memory used by a peer whose stream never
  /// contains a complete frame: beyond that limit the connection is dropped
  /// rather than letting the buffer grow forever.
  FramedTcpServer({
    InternetAddress? bindAddress,
    this.port = 0,
    this.maxBufferBytes = 8192,
  })  : assert(port >= 0 && port <= 65535, 'port out of range'),
        assert(maxBufferBytes > 0, 'maxBufferBytes must be positive'),
        bindAddress = bindAddress ?? InternetAddress.anyIPv4;

  /// Listening address.
  final InternetAddress bindAddress;

  /// Port requested at start; `0` for an ephemeral port.
  final int port;

  /// Maximum buffer size per peer, in bytes.
  final int maxBufferBytes;

  final StreamController<ServerEvent> _events =
      StreamController<ServerEvent>.broadcast();
  final Map<String, _Peer> _peers = <String, _Peer>{};

  ServerSocket? _socket;
  int _peerCounter = 0;
  bool _disposed = false;

  /// Broadcast stream of server events.
  Stream<ServerEvent> get events => _events.stream;

  /// True between [start] and [stop].
  bool get isRunning => _socket != null;

  /// Effective listening port.
  ///
  /// `0` before [start]; afterwards the port actually assigned by the system,
  /// which is how an ephemeral port is discovered.
  int get listeningPort => _socket?.port ?? 0;

  /// Identifiers of the currently connected peers, in arrival order.
  List<String> get peerIds => List<String>.unmodifiable(_peers.keys);

  /// Number of connected peers.
  int get peerCount => _peers.length;

  /// Opens the listening socket.
  ///
  /// Throws [StateError] when the server already runs, [SocketException] when
  /// the address or the port is unavailable.
  Future<void> start() async {
    if (_disposed) {
      throw StateError('server already disposed: create a new one');
    }
    if (_socket != null) {
      throw StateError('server already started on port $listeningPort');
    }
    final ServerSocket socket =
        await ServerSocket.bind(bindAddress, port, shared: false);
    _socket = socket;
    socket.listen(_accept, onError: _onSocketError);
  }

  /// Closes the open connections, then the listening socket.
  ///
  /// Each closed peer produces a [PeerDisconnected] before the close. No effect
  /// when the server is already stopped.
  Future<void> stop() async {
    final ServerSocket? socket = _socket;
    _socket = null;
    final List<_Peer> peers = _peers.values.toList(growable: false);
    _peers.clear();
    for (final _Peer peer in peers) {
      peer.subscription.cancel();
      try {
        await peer.socket.close();
      } on SocketException {
        // Peer already gone: nothing to close.
      }
      _emit(PeerDisconnected(peerId: peer.id, reason: 'server stopped'));
    }
    await socket?.close();
  }

  /// Sends [bytes] to the peer [peerId].
  ///
  /// Does nothing when the peer disappeared in the meantime: sending to a peer
  /// that left is not an error. Throws [StateError] when the server is stopped.
  Future<void> send(String peerId, List<int> bytes) async {
    if (_socket == null) {
      throw StateError('server stopped: cannot send to $peerId');
    }
    final _Peer? peer = _peers[peerId];
    if (peer == null) {
      return;
    }
    try {
      peer.socket.add(bytes);
      await peer.socket.flush();
    } on SocketException catch (error) {
      _emit(PeerFault(
        peerId: peerId,
        message: 'write to $peerId failed',
        cause: error,
      ));
    }
  }

  /// Sends [bytes] to every connected peer.
  Future<void> broadcast(List<int> bytes) async {
    for (final String peerId in peerIds) {
      await send(peerId, bytes);
    }
  }

  /// Closes the [peerId] connection from the server side.
  Future<void> closePeer(String peerId, {String? reason}) async {
    final _Peer? peer = _peers.remove(peerId);
    if (peer == null) {
      return;
    }
    await peer.subscription.cancel();
    try {
      await peer.socket.close();
    } on SocketException {
      // Already closed by the client.
    }
    _emit(
        PeerDisconnected(peerId: peerId, reason: reason ?? 'closed by server'));
  }

  /// Stops the server and closes its event stream.
  Future<void> dispose() async {
    await stop();
    _disposed = true;
    if (!_events.isClosed) {
      await _events.close();
    }
  }

  void _accept(Socket socket) {
    if (_socket == null) {
      socket.destroy();
      return;
    }
    _peerCounter++;
    final String peerId = 'peer-$_peerCounter';
    final _Peer peer = _Peer(
      id: peerId,
      socket: socket,
      subscription: socket.listen(
        (List<int> chunk) => _onData(peerId, chunk),
        onError: (Object error) => _onPeerError(peerId, error),
        onDone: () => _onPeerDone(peerId),
        cancelOnError: true,
      ),
    );
    _peers[peerId] = peer;
    _emit(PeerConnected(
      peerId: peerId,
      address: socket.remoteAddress.address,
      port: socket.remotePort,
    ));
  }

  void _onData(String peerId, List<int> chunk) {
    final _Peer? peer = _peers[peerId];
    if (peer == null) {
      return;
    }
    if (chunk.length > maxBufferBytes) {
      // A single write larger than the cap cannot be a frame: no point
      // buffering it, the peer is not speaking the protocol.
      _emit(PeerFault(
        peerId: peerId,
        message: 'buffer for $peerId overflowed '
            '(${chunk.length} bytes in one write)',
      ));
      unawaited(closePeer(peerId, reason: 'buffer overflow'));
      return;
    }
    peer.buffer.addAll(chunk);
    while (true) {
      final ({ObcMessage message, int consumed})? decoded =
          ObcCodec.tryDecode(peer.buffer);
      if (decoded == null) {
        // Nothing complete yet: drop the definitely unusable leading bytes and
        // keep a possibly partial frame at the head of the buffer.
        final int discard = ObcCodec.discardCount(peer.buffer);
        if (discard > 0) {
          peer.buffer.removeRange(0, discard);
          peer.discardedBytes += discard;
        }
        break;
      }
      peer.buffer.removeRange(0, decoded.consumed);
      _emit(PeerMessage(peerId: peerId, message: decoded.message));
    }
    if (peer.buffer.length > maxBufferBytes) {
      _emit(PeerFault(
        peerId: peerId,
        message: 'buffer for $peerId overflowed '
            '(${peer.buffer.length} bytes without a complete frame)',
      ));
      // The stream is not speaking the protocol: cut it short.
      unawaited(closePeer(peerId, reason: 'buffer overflow'));
    }
  }

  void _onPeerError(String peerId, Object error) {
    if (_peers.remove(peerId) == null) {
      return;
    }
    _emit(PeerFault(
      peerId: peerId,
      message: 'read error on $peerId',
      cause: error,
    ));
    _emit(PeerDisconnected(peerId: peerId, reason: 'read error'));
  }

  void _onPeerDone(String peerId) {
    final _Peer? peer = _peers.remove(peerId);
    if (peer == null) {
      return;
    }
    peer.subscription.cancel();
    _emit(PeerDisconnected(peerId: peerId));
  }

  void _onSocketError(Object error) {
    _emit(PeerFault(
      peerId: 'server',
      message: 'listening socket error',
      cause: error,
    ));
  }

  void _emit(ServerEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }
}

/// Mutable state of one incoming connection.
class _Peer {
  _Peer({
    required this.id,
    required this.socket,
    required this.subscription,
  });

  final String id;
  final Socket socket;
  final StreamSubscription<List<int>> subscription;

  /// Received bytes not consumed yet by the decoder.
  final List<int> buffer = <int>[];

  /// Count of discarded bytes, useful for diagnostics.
  int discardedBytes = 0;
}
