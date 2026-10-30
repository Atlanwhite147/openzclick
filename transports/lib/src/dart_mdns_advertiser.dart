/// Pure Dart mDNS/DNS-SD responder used to publish the bridge on a local
/// network, with no platform-specific code.
///
/// It listens on `224.0.0.251:5353`, answers PTR/SRV/TXT/A queries for the
/// announced service and re-announces itself periodically. The DNS encoder is
/// deliberately simple (no name compression on output, compression tolerated on
/// input) so that the same code runs on Android, iOS, Windows, macOS and Linux.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mdns_advertiser.dart';

/// mDNS multicast address.
const String mdnsMulticastAddress = '224.0.0.251';

/// mDNS port.
const int mdnsPort = 5353;

/// DNS record types used by the responder.
abstract final class DnsType {
  /// IPv4 address.
  static const int a = 1;

  /// Pointer to a service instance.
  static const int ptr = 12;

  /// Service location.
  static const int srv = 33;

  /// Free-form key/value pairs.
  static const int txt = 16;
}

/// Encodes and decodes the subset of DNS used by DNS-SD.
abstract final class DnsWire {
  /// Encodes a dotted name into DNS label format.
  static List<int> encodeName(String name) {
    final List<int> out = <int>[];
    for (final String label in name.split('.')) {
      if (label.isEmpty) continue;
      final List<int> bytes = utf8.encode(label);
      if (bytes.length > 63) {
        throw ArgumentError.value(label, 'label', 'longer than 63 bytes');
      }
      out.add(bytes.length);
      out.addAll(bytes);
    }
    out.add(0);
    return out;
  }

  /// Decodes a possibly compressed name starting at [offset].
  ///
  /// Returns the name and the offset just after it in the original buffer.
  static ({String name, int next}) decodeName(List<int> data, int offset) {
    final StringBuffer result = StringBuffer();
    int index = offset;
    int? jumpTarget;
    int guard = 0;

    while (true) {
      if (index >= data.length) break;
      final int length = data[index];
      if (length == 0) {
        index++;
        break;
      }
      if ((length & 0xC0) == 0xC0) {
        if (index + 1 >= data.length) break;
        final int pointer = ((length & 0x3F) << 8) | data[index + 1];
        jumpTarget ??= index + 2;
        index = pointer;
        if (++guard > 16) break;
        continue;
      }
      final int end = index + 1 + length;
      if (end > data.length) break;
      if (result.isNotEmpty) result.write('.');
      result.write(utf8.decode(data.sublist(index + 1, end), allowMalformed: true));
      index = end;
      if (++guard > 128) break;
    }

    return (name: result.toString(), next: jumpTarget ?? index);
  }

  /// Builds a DNS query, used by the tests and the diagnostics screen.
  static List<int> buildQuery(String name, {int type = DnsType.ptr}) {
    final List<int> out = <int>[
      0, 0, // id
      0, 0, // flags: standard query
      0, 1, // questions
      0, 0, 0, 0, 0, 0, // no answers, authority or additional
    ];
    out.addAll(encodeName(name));
    out
      ..add((type >> 8) & 0xFF)
      ..add(type & 0xFF)
      ..add(0)
      ..add(1); // class IN
    return out;
  }

  /// Extracts the questions of a DNS query.
  static List<({String name, int type})> parseQuestions(List<int> data) {
    if (data.length < 12) return const <({String name, int type})>[];
    final int count = (data[4] << 8) | data[5];
    int offset = 12;
    final List<({String name, int type})> questions = <({String name, int type})>[];
    for (int i = 0; i < count && offset < data.length; i++) {
      final ({String name, int next}) decoded = decodeName(data, offset);
      offset = decoded.next;
      if (offset + 4 > data.length) break;
      final int type = (data[offset] << 8) | data[offset + 1];
      offset += 4;
      questions.add((name: decoded.name, type: type));
    }
    return questions;
  }
}

/// Writes DNS records into a response packet.
class _DnsWriter {
  final List<int> bytes = <int>[];
  int _answerCount = 0;

  void header({required int questionCount}) {
    bytes.addAll(<int>[
      0, 0, // id 0: mDNS responses carry no identifier
      0x84, 0x00, // response, authoritative
      0, questionCount,
      0, 0, // answers patched later
      0, 0, 0, 0,
    ]);
  }

  void patchAnswerCount() {
    bytes[6] = (_answerCount >> 8) & 0xFF;
    bytes[7] = _answerCount & 0xFF;
  }

  void answer({
    required String name,
    required int type,
    required int ttl,
    required List<int> rdata,
  }) {
    bytes.addAll(DnsWire.encodeName(name));
    bytes
      ..add((type >> 8) & 0xFF)
      ..add(type & 0xFF)
      ..add(0x80) // cache flush
      ..add(1) // class IN
      ..add((ttl >> 24) & 0xFF)
      ..add((ttl >> 16) & 0xFF)
      ..add((ttl >> 8) & 0xFF)
      ..add(ttl & 0xFF)
      ..add((rdata.length >> 8) & 0xFF)
      ..add(rdata.length & 0xFF)
      ..addAll(rdata);
    _answerCount++;
  }
}

/// Publishes one service on the local network with multicast DNS.
///
/// The responder answers PTR, SRV, TXT and A queries, announces twice on
/// registration and re-announces every [announceInterval]. Unregistering sends
/// a goodbye packet with a zero TTL.
class DartMdnsAdvertiser implements MdnsAdvertiser {
  /// Creates an advertiser.
  ///
  /// [hostName] defaults to the sanitised instance name; [addresses] is resolved
  /// at registration time when omitted.
  DartMdnsAdvertiser({
    this.hostName,
    this.addresses,
    this.announceInterval = const Duration(seconds: 60),
    this.ttl = 120,
  });

  /// Host name advertised in the A record, without the `.local` suffix.
  final String? hostName;

  /// IPv4 addresses advertised; resolved from the interfaces when null.
  final List<String>? addresses;

  /// Delay between two announcements.
  final Duration announceInterval;

  /// Record time to live, in seconds.
  final int ttl;

  RawDatagramSocket? _socket;
  MdnsService? _service;
  Timer? _timer;
  String _host = 'openzclick';
  String _serviceType = '_openbikecontrol._tcp.local';
  List<String> _resolved = const <String>[];

  /// Effective TCP port of the current announcement, null when idle.
  int? get announcedPort => _service?.port;

  @override
  Future<void> register(MdnsService service) async {
    // A second registration replaces the first one: releasing the previous
    // socket first keeps a single announcement alive.
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;

    _service = service;
    _host = (hostName ?? _sanitise(service.instanceName)).toLowerCase();
    // DNS-SD names always end with the local domain.
    final String type = service.serviceType.toLowerCase();
    _serviceType = type.endsWith('.local') ? type : '$type.local';

    _resolved = addresses ?? await _resolveAddresses();

    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        mdnsPort,
        reuseAddress: true,
        reusePort: true,
      );
    } on SocketException {
      // Some platforms refuse port sharing; a plain bind still serves queries.
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        mdnsPort,
        reuseAddress: true,
      );
    }
    _socket = socket;
    socket.joinMulticast(InternetAddress(mdnsMulticastAddress));
    socket.broadcastEnabled = true;
    socket.listen(_onPacket);

    // Announce twice, as recommended for UDP loss.
    _send(_buildResponse(questions: const <({String name, int type})>[]));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _send(_buildResponse(questions: const <({String name, int type})>[]));

    _timer?.cancel();
    _timer = Timer.periodic(announceInterval, (_) {
      _send(_buildResponse(questions: const <({String name, int type})>[]));
    });
  }

  @override
  Future<void> unregister() async {
    _timer?.cancel();
    _timer = null;
    final MdnsService? service = _service;
    if (service != null) {
      // Goodbye packet: same records, TTL 0.
      _send(_buildResponse(questions: const <({String name, int type})>[], goodbye: true));
    }
    _service = null;
    _socket?.close();
    _socket = null;
  }

  void _onPacket(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final Datagram? datagram = _socket?.receive();
    if (datagram == null) return;
    final List<({String name, int type})> questions =
        DnsWire.parseQuestions(datagram.data);
    if (questions.isEmpty) return;

    final List<({String name, int type})> matching = questions.where(_matches).toList();
    if (matching.isEmpty) return;

    final List<int> response = _buildResponse(questions: matching);
    // Answer both ways: to the source port (client asked for a unicast reply)
    // and on the multicast group, as classic DNS-SD responders do.
    _socket?.send(response, datagram.address, datagram.port);
    if (datagram.port != mdnsPort) {
      _socket?.send(response, InternetAddress(mdnsMulticastAddress), mdnsPort);
    }
  }

  bool _matches(({String name, int type}) question) {
    final MdnsService? service = _service;
    if (service == null) return false;
    final String q = question.name.toLowerCase();
    final String type = _serviceType;
    final String instance = '${service.instanceName}.$type'.toLowerCase();
    final String host = '$_host.local';
    return (question.type == DnsType.ptr &&
            (q == type || q == '_services._dns-sd._udp')) ||
        (question.type == DnsType.srv && q == instance) ||
        (question.type == DnsType.txt && q == instance) ||
        (question.type == DnsType.a && q == host);
  }

  List<int> _buildResponse({
    required List<({String name, int type})> questions,
    bool goodbye = false,
  }) {
    final MdnsService? service = _service;
    final _DnsWriter writer = _DnsWriter()..header(questionCount: questions.length);

    // Echo the questions so that caches match them.
    for (final ({String name, int type}) question in questions) {
      writer.bytes.addAll(DnsWire.encodeName(question.name));
      writer.bytes
        ..add((question.type >> 8) & 0xFF)
        ..add(question.type & 0xFF)
        ..add(0)
        ..add(1);
    }

    if (service == null) {
      writer.patchAnswerCount();
      return writer.bytes;
    }

    final int effectiveTtl = goodbye ? 0 : ttl;
    final String type = _serviceType;
    final String instance = '${service.instanceName}.$type';
    final String host = '$_host.local';

    // PTR: service type -> instance.
    writer.answer(
      name: type,
      type: DnsType.ptr,
      ttl: effectiveTtl,
      rdata: DnsWire.encodeName(instance),
    );

    // SRV: instance -> host + port.
    final List<int> srv = <int>[
      0, 0, // priority
      0, 0, // weight
      (service.port >> 8) & 0xFF,
      service.port & 0xFF,
      ...DnsWire.encodeName(host),
    ];
    writer.answer(name: instance, type: DnsType.srv, ttl: effectiveTtl, rdata: srv);

    // TXT: key=value pairs.
    final List<int> txt = <int>[];
    service.txt.forEach((String key, String value) {
      final List<int> entry = utf8.encode('$key=$value');
      txt.add(entry.length);
      txt.addAll(entry);
    });
    if (txt.isEmpty) txt.add(0);
    writer.answer(name: instance, type: DnsType.txt, ttl: effectiveTtl, rdata: txt);

    // A: host -> IPv4 addresses.
    for (final String address in _resolved) {
      final List<int> parts = address.split('.').map(int.parse).toList();
      if (parts.length != 4) continue;
      writer.answer(
        name: host,
        type: DnsType.a,
        ttl: effectiveTtl,
        rdata: <int>[...parts],
      );
    }

    writer.patchAnswerCount();
    return writer.bytes;
  }

  void _send(List<int> packet) {
    try {
      _socket?.send(packet, InternetAddress(mdnsMulticastAddress), mdnsPort);
    } catch (_) {
      // A closed socket during unregister is expected.
    }
  }

  static String _sanitise(String name) {
    final String cleaned = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'openzclick' : cleaned;
  }

  /// Every non-loopback IPv4 address of the machine.
  static Future<List<String>> _resolveAddresses() async {
    try {
      final List<NetworkInterface> interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      // Container bridges and tunnel interfaces are skipped: announcing them
      // only slows down the client's connection attempts.
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
      final List<String> found = <String>[
        for (final NetworkInterface interface in interfaces)
          if (!excluded.any(interface.name.startsWith))
            for (final InternetAddress address in interface.addresses)
              if (!address.isLoopback) address.address,
      ];
      return found.isEmpty ? <String>['127.0.0.1'] : found;
    } catch (_) {
      return <String>['127.0.0.1'];
    }
  }
}
