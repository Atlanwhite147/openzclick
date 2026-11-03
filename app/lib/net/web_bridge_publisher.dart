/// Publication when the page itself can own sockets.
///
/// This is the browser answering the same question the native bridge answers: the
/// page announces `_openbikecontrol._tcp` over mDNS and serves the protocol on a
/// TCP port, so MyWhoosh discovers it exactly as it discovers the desktop build.
/// The only difference is who grants the sockets: Chrome, to an Isolated Web App.
///
/// Two limits are stated rather than hidden, because they come from the platform:
/// a page may send to a multicast group but not bind to it, so queries are never
/// answered — the announcement is repeated on a timer instead — and a page cannot
/// act as a Bluetooth peripheral, so this route is the network one.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:openzclick_core/openzclick_core.dart';

import 'publisher_port.dart';
import 'sockets/sockets.dart';

/// Publishes the bridge from a page that owns sockets.
class WebBridgePublisher implements PublisherPort {
  /// Creates the publisher for [instanceName].
  WebBridgePublisher({
    required this.host,
    this.instanceName = 'openzclick',
    this.port = defaultPort,
    this.announcementPeriod = const Duration(seconds: 2),
  });

  /// Preferred port, the same as the native bridge so an application that
  /// remembers an address keeps working.
  static const int defaultPort = 47123;

  /// How often the announcement is repeated.
  final Duration announcementPeriod;

  /// Sockets of the host.
  final DirectSocketsHost host;

  /// Name announced on the network.
  final String instanceName;

  /// Requested TCP port.
  @override
  final int port;

  /// True once the announcement runs and the port is open.
  @override
  bool running = false;

  /// True: an announcement leaves the page, even though queries go unanswered.
  @override
  bool get advertise => true;

  @override
  int? listeningPort;

  @override
  String? address;

  @override
  int get peers => _server?.peerCount ?? 0;

  @override
  int? get consolePort => null;

  /// No console: the page is the bridge, nothing dials it.
  @override
  int get consoles => 0;

  @override
  String get consoleToken => '';

  @override
  Stream<Action> get consoleActions => const Stream<Action>.empty();

  @override
  String? error;

  @override
  void Function()? onChanged;

  SocketServer? _server;
  MulticastSender? _sender;
  StreamSubscription<SocketPeer>? _peers;
  final Set<_Link> _links = <_Link>{};
  Timer? _announceTimer;
  final Keymap _keymap = Keymap.defaults('openzclick');

  /// TXT record of the specification, identical to the native announcement.
  ///
  /// Written here rather than imported: the transports package owns sockets and
  /// cannot be compiled for the web. `docs/spec.md` is the reference for the
  /// keys; the native responder builds the same map.
  static Map<String, String> txtRecord(String name) => <String, String>{
    'version': '1',
    'id': _deviceId(name),
    'name': name,
    'service-uuids': 'd273f680-d548-419d-b9d1-fa0472345229',
    'manufacturer': 'openzclick',
    'model': 'bridge',
  };

  /// Stable identifier of a bridge, the same FNV-1a digest as the native build.
  static String _deviceId(String name) {
    int hash = 0x811c9dc5;
    for (final int byte in name.codeUnits) {
      hash = (hash ^ byte) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  late final Map<String, String> _txt = txtRecord(instanceName);

  void _notify() {
    onChanged?.call();
  }

  @override
  Future<void> start() async {
    error = null;
    try {
      _server = await host.listen(port);
      listeningPort = _server!.port;
      // Subscribe before anything else is awaited: the connection stream is
      // broadcast and keeps no backlog, so a client that arrives while another
      // await is pending would be dropped for good.
      _peers = _server!.peers.listen(_onPeer);
      // ignore: avoid_print
      _sender = await host.announceSender();
      running = true;
      _announce();
      _announceTimer = Timer.periodic(announcementPeriod, (_) => _announce());
      // The A record needs the local address, but a host that cannot report one
      // must not hold the bridge back: the announcement goes out regardless.
      unawaited(
        host.localAddress().then((String? found) {
          // A stopped bridge must not announce: the address can resolve after
          // the goodbye, and a packet then would resurrect the instance.
          if (!running || found == null || found == address) return;
          address = found;
          _announce();
        }),
      );
    } catch (e) {
      error = e.toString();
      running = false;
      listeningPort = null;
      address = null;
      await _teardown();
    }
    _notify();
  }

  @override
  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    if (_sender != null) {
      // A goodbye: TTL zero asks caches to forget the instance at once.
      _announce(ttl: 0);
    }
    await _teardown();
    running = false;
    listeningPort = null;
    address = null;
    _notify();
  }

  Future<void> _teardown() async {
    await _peers?.cancel();
    _peers = null;
    for (final _Link link in _links.toList(growable: false)) {
      await link.close();
    }
    _links.clear();
    await _server?.close();
    _server = null;
    await _sender?.close();
    _sender = null;
  }

  void _announce({int ttl = 120}) {
    final MulticastSender? sender = _sender;
    if (sender == null) return;
    final String? hostAddress = address;
    sender.send(
      DnsPacket.announcement(
        instance: instanceName,
        serviceType: '_openbikecontrol._tcp.local',
        host: instanceName,
        port: listeningPort ?? port,
        txt: _txt,
        addresses: <String>[if (hostAddress != null && ttl > 0) hostAddress],
        ttl: ttl,
      ),
    );
  }

  void _onPeer(SocketPeer peer) {
    // ignore: avoid_print
    final _Link link = _Link(peer);
    _links.add(link);
    unawaited(
      link.closed.then((_) {
        _links.remove(link);
        _notify();
      }),
    );
    _notify();
  }

  /// Sends [action] to every connected application.
  @override
  Future<void> publish(Action action) async {
    if (!running) return;
    final int? buttonId = _buttonIdFor(action);
    if (buttonId == null) {
      error = 'action ${action.name} is not bound to any button';
      _notify();
      return;
    }
    _sendFrame(
      Uint8List.fromList(ButtonStateMessage(<int, int>{buttonId: 1}).encode()),
    );
    // A release after the same 60 ms the native transport uses, so no button
    // stays stuck on the application side.
    Timer(const Duration(milliseconds: 60), () {
      _sendFrame(
        Uint8List.fromList(
          ButtonStateMessage(<int, int>{buttonId: 0}).encode(),
        ),
      );
    });
  }

  void _sendFrame(Uint8List frame) {
    // ignore: avoid_print
    for (final _Link link in _links.toList(growable: false)) {
      link.send(frame);
    }
  }

  int? _buttonIdFor(Action action) {
    final List<int> candidates =
        _keymap.bindings.entries
            .where((MapEntry<int, Action> entry) => entry.value == action)
            .map((MapEntry<int, Action> entry) => entry.key)
            .toList()
          ..sort();
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Future<void> publishConsoleState({
    required String profileId,
    required int gearIndex,
    required int gearCount,
    required String mode,
    required String lastAction,
  }) async {
    // No console to feed: the page is the bridge here.
  }

  @override
  String? consoleUrl(String host) => null;

  @override
  Future<void> dispose() async {
    await stop();
  }
}

/// One accepted connection, with the frames read so far.
class _Link {
  _Link(this.peer) {
    _subscription = peer.incoming.listen(
      (Uint8List chunk) {
        _buffer.addAll(chunk);
        _drain();
      },
      onDone: () {
        if (!_closed.isCompleted) _closed.complete();
      },
      onError: (Object _) {
        if (!_closed.isCompleted) _closed.complete();
      },
    );
  }

  final SocketPeer peer;
  final List<int> _buffer = <int>[];
  final Completer<void> _closed = Completer<void>();
  StreamSubscription<Uint8List>? _subscription;

  Future<void> get closed => _closed.future;

  Future<void> send(List<int> frame) => peer.send(frame);

  /// Splits the buffer with the core decoder: one message per frame, no length
  /// prefix needed because the protocol is self-delimiting.
  void _drain() {
    while (_buffer.isNotEmpty) {
      final ({ObcMessage message, int consumed})? decoded = ObcCodec.tryDecode(
        _buffer,
      );
      if (decoded == null) {
        // Nothing usable yet; keep the bytes for the next read.
        return;
      }
      _buffer.removeRange(0, decoded.consumed);
      _onMessage(decoded.message);
    }
  }

  void _onMessage(ObcMessage message) {
    // The bridge publishes; it does not apply what an application sends back.
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await peer.close();
    if (!_closed.isCompleted) _closed.complete();
  }
}
