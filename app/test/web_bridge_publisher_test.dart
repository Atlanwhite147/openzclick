import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick/net/sockets/sockets.dart';
import 'package:openzclick/net/web_bridge_publisher.dart';

/// A connection a test controls: what a training application would be.
class FakePeer implements SocketPeer {
  FakePeer(this.id);

  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final List<List<int>> sent = <List<int>>[];
  bool closed = false;

  @override
  final String id;

  @override
  String get label => 'fake';

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  /// Simulates bytes written by the application.
  void receive(List<int> bytes) => _incoming.add(Uint8List.fromList(bytes));

  @override
  Future<void> send(List<int> bytes) async => sent.add(List<int>.of(bytes));

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }
}

/// A host with no operating system: records what the publisher asks for.
class FakeHost implements DirectSocketsHost {
  FakeHost({this.localAddressValue = '192.168.1.24'});

  final String? localAddressValue;
  final StreamController<SocketPeer> peers =
      StreamController<SocketPeer>.broadcast();
  final List<List<int>> packets = <List<int>>[];
  int? boundPort;
  bool closed = false;
  String? failure;

  @override
  Future<SocketServer> listen(int port) async {
    if (failure != null) throw StateError(failure!);
    boundPort = port == 0 ? 47123 : port;
    return _FakeServer(boundPort!, peers);
  }

  @override
  Future<MulticastSender> announceSender() async => _FakeSender(packets);

  @override
  Future<String?> localAddress() async => localAddressValue;
}

class _FakeServer implements SocketServer {
  _FakeServer(this.port, this._peers);

  @override
  final int port;

  final StreamController<SocketPeer> _peers;
  final List<SocketPeer> _open = <SocketPeer>[];

  @override
  Stream<SocketPeer> get peers => _peers.stream;

  @override
  int get peerCount => _open.length;

  void add(SocketPeer peer) => _open.add(peer);

  @override
  Future<void> close() async {
    _open.clear();
    await _peers.close();
  }
}

class _FakeSender implements MulticastSender {
  _FakeSender(this.packets);

  final List<List<int>> packets;

  @override
  int get localPort => 5353;

  @override
  void send(List<int> bytes) => packets.add(List<int>.of(bytes));

  @override
  Future<void> close() async {}
}

void main() {
  test('the page announces the service the specification describes', () async {
    final FakeHost host = FakeHost();
    final WebBridgePublisher publisher = WebBridgePublisher(host: host);
    await publisher.start();
    addTearDown(publisher.dispose);
    // The address arrives asynchronously; the bridge does not wait for it.
    await Future<void>.delayed(Duration.zero);

    expect(publisher.running, isTrue);
    expect(publisher.listeningPort, 47123);
    expect(publisher.address, '192.168.1.24');
    expect(host.packets, isNotEmpty);

    final List<({String name, int type, List<int> rdata})> answers =
        DnsReader.answers(Uint8List.fromList(host.packets.last));
    expect(answers.map((answer) => answer.type), <int>[
      DnsType.ptr,
      DnsType.srv,
      DnsType.txt,
      DnsType.a,
    ]);
    expect(answers.first.name, '_openbikecontrol._tcp.local');
    expect(answers.last.rdata, <int>[192, 168, 1, 24]);
  });

  test('stopping says goodbye instead of leaving a stale instance', () async {
    final FakeHost host = FakeHost();
    final WebBridgePublisher publisher = WebBridgePublisher(host: host);
    await publisher.start();
    await Future<void>.delayed(Duration.zero);
    await publisher.stop();

    expect(publisher.running, isFalse);
    final List<int> goodbye = host.packets.last;
    final List<({String name, int type, List<int> rdata})> answers =
        DnsReader.answers(Uint8List.fromList(goodbye));
    // TTL zero: the cache forgets the instance; the A record is not repeated.
    expect(answers.where((answer) => answer.type == DnsType.a), isEmpty);
    expect(publisher.listeningPort, isNull);
  });

  test('a shift is published as a press then a release', () async {
    final FakeHost host = FakeHost();
    final WebBridgePublisher publisher = WebBridgePublisher(host: host);
    await publisher.start();
    addTearDown(publisher.dispose);

    final FakePeer peer = FakePeer('app');
    final _FakeServer server = _FakeServer(47123, host.peers)..add(peer);
    host.peers.add(peer);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await publisher.publish(Action.shiftUp);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(peer.sent, hasLength(2), reason: 'press, then release');
    final ({ObcMessage message, int consumed}) press = ObcCodec.tryDecode(
      peer.sent.first,
    )!;
    final ({ObcMessage message, int consumed}) release = ObcCodec.tryDecode(
      peer.sent.last,
    )!;
    expect(press.message, isA<ButtonState>());
    expect(
      (press.message as ButtonState).buttons.values.first,
      1,
      reason: 'press',
    );
    expect(
      (release.message as ButtonState).buttons.values.first,
      0,
      reason: 'release',
    );
    expect(server.port, 47123);
  });

  test('a refused port is reported, not swallowed', () async {
    final FakeHost host = FakeHost()..failure = 'port taken';
    final WebBridgePublisher publisher = WebBridgePublisher(host: host);
    await publisher.start();

    expect(publisher.running, isFalse);
    expect(publisher.error, contains('port taken'));
  });
}
