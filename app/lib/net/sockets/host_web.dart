/// Direct Sockets, as Chromium exposes them to an Isolated Web App.
///
/// The shapes here are the ones a real Chrome 145 produced when probed:
/// `TCPServerSocket.prototype` carries `opened`, `closed` and `close`, and the
/// open information holds `localAddress`, `localPort` and a `readable` stream of
/// accepted `TCPSocket`s. A `TCPSocket` hands out `readable` and `writable` the
/// same way. `UDPSocket` in connected mode also exposes `writable`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'host.dart';

/// True when the page can open sockets.
bool get directSocketsAvailable => globalContext.has('TCPServerSocket');

/// Local IPv4 address, discovered through WebRTC host candidates.
///
/// The page cannot ask the operating system for its interfaces; an ICE candidate
/// carries the host address, which is the address a training application on the
/// same network has to dial.
Future<String?> discoverLocalAddress() async {
  final _RTCPeerConnection connection = _RTCPeerConnection();
  try {
    connection.createDataChannel('probe'.toJS);
    final JSPromise<JSObject> offer = connection.createOffer();
    await connection.setLocalDescription(await offer.toDart).toDart;
    // 1.5 s is enough for host candidates; STUN servers are never used.
    for (int attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final String description = connection.localDescription?.sdp?.toDart ?? '';
      final String? address = _firstIPv4(description);
      if (address != null) return address;
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    connection.close();
  }
}

String? _firstIPv4(String sdp) {
  for (final RegExpMatch match in RegExp(
    r'c=IN IP4 ([0-9.]+)',
  ).allMatches(sdp)) {
    final String address = match.group(1)!;
    if (address != '0.0.0.0') return address;
  }
  return null;
}

/// Builds the host of this page, `null` when sockets are not granted.
DirectSocketsHost? createDirectSocketsHost() =>
    directSocketsAvailable ? _ChromeDirectSockets() : null;

class _ChromeDirectSockets implements DirectSocketsHost {
  @override
  Future<SocketServer> listen(int port) async {
    final _TCPServerSocket server = _TCPServerSocket(
      '0.0.0.0'.toJS,
      _tcpOptions(port),
    );
    final _TCPServerSocketOpenInfo info = await server.opened.toDart;
    return _ChromeSocketServer(server, info);
  }

  @override
  Future<MulticastSender> announceSender() async {
    final _UDPSocket socket = _UDPSocket(_udpOptions());
    final _UDPSocketOpenInfo info = await socket.opened.toDart;
    return _ChromeMulticastSender(socket, info);
  }

  @override
  Future<String?> localAddress() => discoverLocalAddress();
}

class _ChromeSocketServer implements SocketServer {
  _ChromeSocketServer(this._server, this._info) {
    _accepted = _readAccepted(_info.readable);
  }

  final _TCPServerSocket _server;
  final _TCPServerSocketOpenInfo _info;
  final StreamController<SocketPeer> _peers =
      StreamController<SocketPeer>.broadcast();
  final List<_ChromeSocketPeer> _open = <_ChromeSocketPeer>[];
  late final Future<void> _accepted;
  int _counter = 0;

  Future<void> _readAccepted(_ReadableStream<JSAny?> readable) async {
    final _ReadableStreamDefaultReader<JSAny?> reader = readable.getReader();
    try {
      while (true) {
        final _ReadResult<JSAny?> result = await reader.read().toDart;
        if (result.done == true) return;
        final _TCPSocket socket = result.value! as _TCPSocket;
        final _TCPSocketOpenInfo openInfo = await socket.opened.toDart;
        _counter += 1;
        final _ChromeSocketPeer peer = _ChromeSocketPeer(
          'peer-$_counter',
          socket,
          openInfo,
        );
        _open.add(peer);
        unawaited(peer.closed.then((_) => _open.remove(peer)));
        if (!_peers.isClosed) _peers.add(peer);
      }
    } catch (_) {
      // The server was closed while a connection was pending.
    }
  }

  @override
  int get port => _info.localPort.toDartInt;

  @override
  Stream<SocketPeer> get peers => _peers.stream;

  @override
  int get peerCount => _open.length;

  @override
  Future<void> close() async {
    for (final _ChromeSocketPeer peer in _open.toList(growable: false)) {
      await peer.close();
    }
    await _server.close().toDart;
    await _accepted;
    await _peers.close();
  }
}

class _ChromeSocketPeer implements SocketPeer {
  _ChromeSocketPeer(this.id, this._socket, this._info) {
    _reading = _pump();
  }

  @override
  final String id;

  final _TCPSocket _socket;
  final _TCPSocketOpenInfo _info;
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final Completer<void> _closed = Completer<void>();
  late final Future<void> _reading;

  /// One writer for the whole connection: closing it after each frame would
  /// close the socket, which is exactly the bug this keeps out.
  late final _WritableStreamDefaultWriter<JSAny?> _writer = _info.writable
      .getWriter();

  Future<void> get closed => _closed.future;

  Future<void> _pump() async {
    final _ReadableStreamDefaultReader<JSAny?> reader = _info.readable
        .getReader();
    try {
      while (true) {
        final _ReadResult<JSAny?> result = await reader.read().toDart;
        if (result.done == true) break;
        final JSAny? value = result.value;
        if (value == null) continue;
        final JSUint8Array bytes = value as JSUint8Array;
        if (!_incoming.isClosed) _incoming.add(bytes.toDart);
      }
    } catch (_) {
      // A peer that disappears mid-read is a disconnection.
    } finally {
      if (!_incoming.isClosed) await _incoming.close();
      if (!_closed.isCompleted) _closed.complete();
    }
  }

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  String get label => 'peer';

  @override
  Future<void> send(List<int> bytes) {
    // Writes are chained, never concurrent: a second write issued while the
    // first is still pending is dropped by the socket's writable stream, which
    // is how the release of a shift vanished while its press arrived. The writer
    // stays open for the lifetime of the connection, because closing it ends the
    // connection rather than the frame.
    final Uint8List data = Uint8List.fromList(bytes);
    final Future<void> next = _writing.catchError((Object _) {}).then<void>((
      void _,
    ) async {
      await _writer.write(data.toJS).toDart;
    });
    _writing = next;
    return next;
  }

  Future<void> _writing = Future<void>.value();

  @override
  Future<void> close() async {
    unawaited(_writer.close().toDart);
    await _socket.close().toDart;
    await _reading;
  }
}

class _ChromeMulticastSender implements MulticastSender {
  _ChromeMulticastSender(this._socket, this._info) {
    _writer = _info.writable.getWriter();
  }

  final _UDPSocket _socket;
  final _UDPSocketOpenInfo _info;
  late final _WritableStreamDefaultWriter<JSAny?> _writer;

  @override
  int get localPort => _info.localPort.toDartInt;

  @override
  void send(List<int> bytes) {
    // The socket is already connected to the group: a write carries data only.
    // Adding remoteAddress here is refused by Chrome, silently for an unawaited
    // future, which is how the announcement used to vanish.
    final JSObject message = JSObject()
      ..setProperty('data'.toJS, Uint8List.fromList(bytes).toJS);
    unawaited(_writer.write(message).toDart);
  }

  @override
  Future<void> close() async {
    unawaited(_writer.close().toDart);
    await _socket.close().toDart;
  }
}

JSObject _tcpOptions(int port) => JSObject()
  ..setProperty('localPort'.toJS, port.toJS)
  ..setProperty('backlog'.toJS, 8.toJS);

JSObject _udpOptions() => JSObject()
  ..setProperty('remoteAddress'.toJS, '224.0.0.251'.toJS)
  ..setProperty('remotePort'.toJS, 5353.toJS)
  ..setProperty('multicastTimeToLive'.toJS, 1.toJS)
  ..setProperty('multicastLoopback'.toJS, true.toJS);

@JS('TCPServerSocket')
extension type _TCPServerSocket._(JSObject _) implements JSObject {
  external factory _TCPServerSocket(JSString localAddress, JSObject options);
  external JSPromise<_TCPServerSocketOpenInfo> get opened;
  external JSPromise<JSAny?> close();
}

extension type _TCPServerSocketOpenInfo._(JSObject _) implements JSObject {
  external JSString get localAddress;
  external JSNumber get localPort;
  external _ReadableStream<JSAny?> get readable;
}

@JS('TCPSocket')
extension type _TCPSocket._(JSObject _) implements JSObject {
  external JSPromise<_TCPSocketOpenInfo> get opened;
  external JSPromise<JSAny?> close();
}

extension type _TCPSocketOpenInfo._(JSObject _) implements JSObject {
  external _ReadableStream<JSAny?> get readable;
  external _WritableStream<JSAny?> get writable;
}

@JS('UDPSocket')
extension type _UDPSocket._(JSObject _) implements JSObject {
  external factory _UDPSocket(JSObject options);
  external JSPromise<_UDPSocketOpenInfo> get opened;
  external JSPromise<JSAny?> close();
}

extension type _UDPSocketOpenInfo._(JSObject _) implements JSObject {
  external JSNumber get localPort;
  external _WritableStream<JSAny?> get writable;
}

extension type _ReadableStream<T extends JSAny?>._(JSObject _)
    implements JSObject {
  external _ReadableStreamDefaultReader<T> getReader();
}

extension type _ReadableStreamDefaultReader<T extends JSAny?>._(JSObject _)
    implements JSObject {
  external JSPromise<_ReadResult<T>> read();
}

extension type _ReadResult<T extends JSAny?>._(JSObject _) implements JSObject {
  external T? get value;
  external JSBoolean? get done;
}

extension type _WritableStream<T extends JSAny?>._(JSObject _)
    implements JSObject {
  external _WritableStreamDefaultWriter<T> getWriter();
}

extension type _WritableStreamDefaultWriter<T extends JSAny?>._(JSObject _)
    implements JSObject {
  external JSPromise<JSAny?> write(T chunk);
  external JSPromise<JSAny?> close();
}

extension type _RTCPeerConnection._(JSObject _) implements JSObject {
  external factory _RTCPeerConnection();
  external JSAny createDataChannel(JSString label);
  external JSPromise<JSObject> createOffer();
  external JSPromise<JSAny?> setLocalDescription(JSObject description);
  external _Sdp? get localDescription;
  external void close();
}

extension type _Sdp._(JSObject _) implements JSObject {
  external JSString? get sdp;
}
