import 'dart:typed_data';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

void main() {
  test('an announcement carries PTR, SRV, TXT and A records', () {
    final Uint8List packet = Uint8List.fromList(
      DnsPacket.announcement(
        instance: 'openzclick',
        serviceType: '_openbikecontrol._tcp.local',
        host: 'bridge',
        port: 47123,
        txt: <String, String>{'version': '1', 'name': 'openzclick'},
        addresses: <String>['192.168.1.24'],
      ),
    );

    final List<({String name, int type, List<int> rdata})> answers =
        DnsReader.answers(packet);

    expect(answers.map((answer) => answer.type), <int>[
      DnsType.ptr,
      DnsType.srv,
      DnsType.txt,
      DnsType.a,
    ]);
    expect(answers.first.name, '_openbikecontrol._tcp.local');
    expect(answers[1].name, 'openzclick._openbikecontrol._tcp.local');

    final List<int> srv = answers[1].rdata;
    expect((srv[4] << 8) | srv[5], 47123, reason: 'port is big endian');
    expect(answers[3].rdata, <int>[192, 168, 1, 24]);
  });

  test('the TXT record is length-prefixed key=value pairs', () {
    final Uint8List packet = Uint8List.fromList(
      DnsPacket.announcement(
        instance: 'openzclick',
        serviceType: '_openbikecontrol._tcp.local',
        host: 'bridge',
        port: 47123,
        txt: <String, String>{'a': '1', 'bb': '22'},
        addresses: const <String>[],
      ),
    );
    final List<int> txt = DnsReader.answers(packet)[2].rdata;

    expect(txt, <int>[
      3, 0x61, 0x3D, 0x31, // "a=1", 3 bytes
      5, 0x62, 0x62, 0x3D, 0x32, 0x32, // "bb=22", 5 bytes
    ]);
  });

  test('an empty TXT record is still a record', () {
    final Uint8List packet = Uint8List.fromList(
      DnsPacket.announcement(
        instance: 'openzclick',
        serviceType: '_openbikecontrol._tcp.local',
        host: 'bridge',
        port: 47123,
        txt: const <String, String>{},
        addresses: const <String>[],
      ),
    );
    expect(DnsReader.answers(packet)[2].rdata, <int>[0]);
  });

  test('a malformed address is skipped, not emitted', () {
    final Uint8List packet = Uint8List.fromList(
      DnsPacket.announcement(
        instance: 'openzclick',
        serviceType: '_openbikecontrol._tcp.local',
        host: 'bridge',
        port: 47123,
        txt: const <String, String>{'version': '1'},
        addresses: <String>['192.168.1.24', 'not-an-address', '10.0.0.300'],
      ),
    );
    final List<({String name, int type, List<int> rdata})> answers =
        DnsReader.answers(packet);
    expect(answers.where((answer) => answer.type == DnsType.a), hasLength(1));
  });

  test('a question is echoed, as a responder does', () {
    final Uint8List packet = Uint8List.fromList(
      DnsPacket.announcement(
        instance: 'openzclick',
        serviceType: '_openbikecontrol._tcp.local',
        host: 'bridge',
        port: 47123,
        txt: const <String, String>{'version': '1'},
        addresses: const <String>['192.168.1.24'],
        questions: <({String name, int type})>[
          (name: '_openbikecontrol._tcp.local', type: DnsType.ptr),
        ],
      ),
    );
    // Header: one question, three answers (PTR, SRV, TXT) and the A record.
    expect(packet[4] << 8 | packet[5], 1);
    expect(packet[6] << 8 | packet[7], 4);
    expect(DnsReader.answers(packet), hasLength(4));
  });

  test('the host name gets the local suffix once', () {
    final Uint8List packet = Uint8List.fromList(
      DnsPacket.announcement(
        instance: 'openzclick',
        serviceType: '_openbikecontrol._tcp.local',
        host: 'bridge.local',
        port: 47123,
        txt: const <String, String>{'version': '1'},
        addresses: const <String>['10.0.0.2'],
      ),
    );
    expect(
      DnsReader.answers(packet).last.name,
      'bridge.local',
      reason: 'never bridge.local.local',
    );
  });

  test('a query asks for the service type', () {
    final Uint8List query = Uint8List.fromList(
      DnsPacket.query('_openbikecontrol._tcp.local'),
    );
    expect(query[4] << 8 | query[5], 1);
    expect(query[6] << 8 | query[7], 0);
    expect(query.sublist(query.length - 4), <int>[0, 12, 0, 1]);
  });
}
