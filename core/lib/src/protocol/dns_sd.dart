/// DNS-SD wire format, shared by every host that announces the bridge.
///
/// The same bytes have to be produced twice now: by the native responder, which
/// owns a socket and answers queries, and by the browser build, whose sockets are
/// granted by the web platform. Keeping the format here — pure data, no I/O — is
/// what stops the two from drifting, and it lets the packet be tested on the host
/// rather than in a browser.
library;

import 'dart:convert';
import 'dart:typed_data';

/// DNS record types used by DNS-SD.
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

/// Encodes dotted names into DNS label format.
abstract final class DnsName {
  /// Encodes [name], terminating with the root label.
  static List<int> encode(String name) {
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
}

/// Builds DNS-SD packets: a query, or an announcement carrying every record.
abstract final class DnsPacket {
  /// Builds a query for [name] of [type].
  static List<int> query(String name, {int type = DnsType.ptr}) {
    final List<int> out = <int>[
      0, 0, // identifier, 0 for mDNS
      0, 0, // flags: standard query
      0, 1, // one question
      0, 0, // no answer
      0, 0, // no authority
      0, 0, // no additional
      ...DnsName.encode(name),
      (type >> 8) & 0xFF,
      type & 0xFF,
      0, 1, // class IN
    ];
    return out;
  }

  /// Builds the announcement of one service instance.
  ///
  /// [instance] and [serviceType] form the DNS-SD names
  /// (`name._type._tcp.local`, `_type._tcp.local`); [host] is the target name,
  /// [port] the TCP port, [txt] the key/value pairs of the specification and
  /// [addresses] the IPv4 addresses the host answers on. [questions] are echoed
  /// back, which is what a responder does when it answers a query.
  static List<int> announcement({
    required String instance,
    required String serviceType,
    required String host,
    required int port,
    required Map<String, String> txt,
    required List<String> addresses,
    List<({String name, int type})> questions = const [],
    int ttl = 120,
  }) {
    final _Writer writer = _Writer()..header(questionCount: questions.length);
    for (final ({String name, int type}) question in questions) {
      writer.bytes
        ..addAll(DnsName.encode(question.name))
        ..add((question.type >> 8) & 0xFF)
        ..add(question.type & 0xFF)
        ..add(0)
        ..add(1);
    }

    final String service = serviceType;
    final String fullInstance = '$instance.$service';
    final String hostName = host.endsWith('.local') ? host : '$host.local';

    writer.answer(
      name: service,
      type: DnsType.ptr,
      ttl: ttl,
      rdata: DnsName.encode(fullInstance),
    );

    writer.answer(
      name: fullInstance,
      type: DnsType.srv,
      ttl: ttl,
      rdata: <int>[
        0, 0, // priority
        0, 0, // weight
        (port >> 8) & 0xFF,
        port & 0xFF,
        ...DnsName.encode(hostName),
      ],
    );

    final List<int> entries = <int>[];
    txt.forEach((String key, String value) {
      final List<int> entry = utf8.encode('$key=$value');
      entries
        ..add(entry.length)
        ..addAll(entry);
    });
    if (entries.isEmpty) entries.add(0);
    writer.answer(
      name: fullInstance,
      type: DnsType.txt,
      ttl: ttl,
      rdata: entries,
    );

    for (final String address in addresses) {
      final List<int> parts =
          address.split('.').map(int.tryParse).whereType<int>().toList();
      if (parts.length != 4) continue;
      if (parts.any((int part) => part < 0 || part > 255)) continue;
      writer.answer(
        name: hostName,
        type: DnsType.a,
        ttl: ttl,
        rdata: parts,
      );
    }

    writer.patchAnswerCount();
    return writer.bytes;
  }
}

/// Byte writer for DNS packets, with the answer count patched at the end.
class _Writer {
  final List<int> bytes = <int>[];
  int _answers = 0;

  void header({required int questionCount}) {
    bytes.addAll(<int>[
      0, 0, // identifier
      0x84, 0x00, // response, authoritative
      (questionCount >> 8) & 0xFF,
      questionCount & 0xFF,
      0, 0, // answer count, patched later
      0, 0, // authority
      0, 0, // additional
    ]);
  }

  void answer({
    required String name,
    required int type,
    required int ttl,
    required List<int> rdata,
  }) {
    bytes
      ..addAll(DnsName.encode(name))
      ..add((type >> 8) & 0xFF)
      ..add(type & 0xFF)
      ..add(0)
      ..add(1) // class IN
      ..add((ttl >> 24) & 0xFF)
      ..add((ttl >> 16) & 0xFF)
      ..add((ttl >> 8) & 0xFF)
      ..add(ttl & 0xFF)
      ..add((rdata.length >> 8) & 0xFF)
      ..add(rdata.length & 0xFF)
      ..addAll(rdata);
    _answers++;
  }

  void patchAnswerCount() {
    bytes[6] = (_answers >> 8) & 0xFF;
    bytes[7] = _answers & 0xFF;
  }
}

/// Reads back a packet, used by the tests of both hosts.
///
/// Compression is tolerated on input: responders compress, our encoder does not.
abstract final class DnsReader {
  /// Lists the answers of [data] as `name/type/rdata`.
  static List<({String name, int type, List<int> rdata})> answers(
    Uint8List data,
  ) {
    final int questionCount = (data[4] << 8) | data[5];
    final int answerCount = (data[6] << 8) | data[7];
    int offset = 12;
    for (int index = 0; index < questionCount; index++) {
      final ({String name, int next}) question = _name(data, offset);
      offset = question.next + 4;
    }
    final List<({String name, int type, List<int> rdata})> out =
        <({String name, int type, List<int> rdata})>[];
    for (int index = 0; index < answerCount; index++) {
      final ({String name, int next}) answer = _name(data, offset);
      offset = answer.next;
      final int type = (data[offset] << 8) | data[offset + 1];
      final int length = (data[offset + 8] << 8) | data[offset + 9];
      offset += 10;
      out.add((
        name: answer.name,
        type: type,
        rdata: data.sublist(offset, offset + length),
      ));
      offset += length;
    }
    return out;
  }

  static ({String name, int next}) _name(Uint8List data, int offset) {
    final StringBuffer buffer = StringBuffer();
    int index = offset;
    while (true) {
      final int length = data[index];
      if (length == 0) {
        index += 1;
        break;
      }
      if (length & 0xC0 == 0xC0) {
        // Compression pointer: not produced here, but tolerated.
        index += 2;
        break;
      }
      buffer.write(utf8.decode(data.sublist(index + 1, index + 1 + length)));
      buffer.write('.');
      index += 1 + length;
    }
    final String name = buffer.toString();
    return (
      name: name.endsWith('.') ? name.substring(0, name.length - 1) : name,
      next: index,
    );
  }
}
