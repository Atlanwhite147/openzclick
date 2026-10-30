import 'dart:io';

import 'package:openzclick_transports/openzclick_transports.dart';
import 'package:test/test.dart';

void main() {
  group('DnsWire names', () {
    test('encodes labels with a length prefix and a terminator', () {
      expect(DnsWire.encodeName('a.bc'), <int>[1, 97, 2, 98, 99, 0]);
    });

    test('round-trips a dotted name', () {
      const String name = '_openbikecontrol._tcp.local';
      final List<int> encoded = DnsWire.encodeName(name);
      final ({String name, int next}) decoded = DnsWire.decodeName(encoded, 0);
      expect(decoded.name, name);
      expect(decoded.next, encoded.length);
    });

    test('decodes a compression pointer', () {
      // 12-byte header, then "sub" followed by a pointer to "local".
      final List<int> packet = <int>[
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        3, 115, 117, 98, 0xC0, 0x12, // "sub" + pointer to offset 18
        5, 108, 111, 99, 97, 108, 0, // "local"
      ];
      final ({String name, int next}) decoded = DnsWire.decodeName(packet, 12);
      expect(decoded.name, 'sub.local');
      expect(decoded.next, 18);
    });

    test('rejects a label longer than 63 bytes', () {
      expect(() => DnsWire.encodeName('a' * 64), throwsArgumentError);
    });
  });

  group('DnsWire questions', () {
    test('parses a PTR question', () {
      final List<int> query = DnsWire.buildQuery('_openbikecontrol._tcp.local');
      final List<({String name, int type})> questions =
          DnsWire.parseQuestions(query);
      expect(questions, hasLength(1));
      expect(questions.first.name, '_openbikecontrol._tcp.local');
      expect(questions.first.type, DnsType.ptr);
    });

    test('returns no question for a short packet', () {
      expect(DnsWire.parseQuestions(<int>[1, 2, 3]), isEmpty);
    });
  });

  group('DartMdnsAdvertiser', () {
    test('announces the service type, instance, TXT and port', () async {
      final DartMdnsAdvertiser advertiser = DartMdnsAdvertiser(
        addresses: <String>['192.0.2.10'],
        hostName: 'openzclick-test',
      );
      await advertiser.register(
        MdnsService(
          instanceName: 'openzclick',
          serviceType: '_openbikecontrol._tcp',
          port: 43210,
          txt: <String, String>{'v': '1', 'name': 'openzclick'},
        ),
      );

      expect(advertiser.announcedPort, 43210);
      await advertiser.unregister();
      expect(advertiser.announcedPort, isNull);
    });

    test('can be registered twice without leaking the socket', () async {
      final DartMdnsAdvertiser advertiser = DartMdnsAdvertiser(
        addresses: <String>['192.0.2.10'],
      );
      final MdnsService service = MdnsService(
        instanceName: 'openzclick',
        serviceType: '_openbikecontrol._tcp',
        port: 12345,
      );
      await advertiser.register(service);
      await advertiser.register(service);
      await advertiser.unregister();
    },
        skip: Platform.isLinux
            ? false
            : 'multicast binding is platform dependent');
  });
}
