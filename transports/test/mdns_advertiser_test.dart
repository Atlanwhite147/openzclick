/// Tests for the mDNS abstractions: service description, TXT records and the
/// in-memory / neutral / unwired implementations.
library;

import 'package:openzclick_transports/src/openzclick_transports.dart';
import 'package:test/test.dart';

void main() {
  group('MdnsService', () {
    test('accepts a well formed description', () {
      final MdnsService service = MdnsService(
        instanceName: 'bridge',
        serviceType: '_openbikecontrol._tcp',
        port: 4242,
        txt: <String, String>{'v': '1'},
      );

      expect(service.instanceName, 'bridge');
      expect(service.port, 4242);
      expect(service.txt, <String, String>{'v': '1'});
    });

    test('rejects an empty name, a bad type and a bad port', () {
      expect(
        () => MdnsService(
          instanceName: ' ',
          serviceType: '_openbikecontrol._tcp',
          port: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => MdnsService(
          instanceName: 'bridge',
          serviceType: 'openbikecontrol',
          port: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => MdnsService(
          instanceName: 'bridge',
          serviceType: '_openbikecontrol._udp',
          port: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => MdnsService(
          instanceName: 'bridge',
          serviceType: '_openbikecontrol._tcp',
          port: 70000,
        ),
        throwsArgumentError,
      );
    });

    test('exposes an unmodifiable TXT map', () {
      final MdnsService service = MdnsService(
        instanceName: 'bridge',
        serviceType: '_openbikecontrol._tcp',
        port: 1,
        txt: <String, String>{'v': '1'},
      );
      expect(
        () => service.txt['v'] = '2',
        throwsUnsupportedError,
      );
    });
  });

  group('MdnsTxt', () {
    test('builds the records of the mDNS specification', () {
      final Map<String, String> txt = MdnsTxt.build(name: 'bridge');

      expect(txt[MdnsTxt.versionKey], '1');
      expect(txt[MdnsTxt.nameKey], 'bridge');
      expect(txt[MdnsTxt.serviceUuidsKey], MdnsTxt.serviceUuid);
      expect(txt[MdnsTxt.manufacturerKey], 'openzclick');
      expect(txt[MdnsTxt.modelKey], 'bridge');
      expect(txt[MdnsTxt.idKey], isNotEmpty);
      MdnsTxt.validate(txt);
    });

    test('the identifier only depends on the announced name', () {
      expect(
        MdnsTxt.build(name: 'bridge')[MdnsTxt.idKey],
        MdnsTxt.build(name: 'bridge')[MdnsTxt.idKey],
      );
      expect(
        MdnsTxt.build(name: 'bridge')[MdnsTxt.idKey],
        isNot(MdnsTxt.build(name: 'other')[MdnsTxt.idKey]),
      );
      expect(
        MdnsTxt.build(name: 'bridge', id: 'aabbccddeeff')[MdnsTxt.idKey],
        'aabbccddeeff',
      );
    });

    test('uses exactly the keys of the specification', () {
      expect(
        MdnsTxt.build(name: 'bridge').keys.toSet(),
        <String>{
          'version',
          'id',
          'name',
          'service-uuids',
          'manufacturer',
          'model',
        },
      );
    });

    test('rejects an over long value, a long key and non ASCII text', () {
      expect(
        () => MdnsTxt.validate(<String, String>{
          'n': 'a' * (MdnsTxt.maxValueLength + 1),
        }),
        throwsArgumentError,
      );
      expect(
        () => MdnsTxt.validate(<String, String>{'a-key-that-is-too-long': 'v'}),
        throwsArgumentError,
      );
      expect(
        () => MdnsTxt.validate(<String, String>{'n': 'pont é'}),
        throwsArgumentError,
      );
      expect(
        () => MdnsTxt.validate(<String, String>{'': 'v'}),
        throwsArgumentError,
      );
    });

    test('accepts a value of exactly the maximum length', () {
      MdnsTxt.validate(<String, String>{'n': 'a' * MdnsTxt.maxValueLength});
    });
  });

  group('InMemoryMdnsAdvertiser', () {
    test('records registrations and forgets the current one', () async {
      final InMemoryMdnsAdvertiser advertiser = InMemoryMdnsAdvertiser();
      expect(advertiser.isAdvertising, isFalse);
      expect(advertiser.current, isNull);

      final MdnsService first = MdnsService(
        instanceName: 'one',
        serviceType: '_openbikecontrol._tcp',
        port: 1000,
        txt: MdnsTxt.build(name: 'one'),
      );
      final MdnsService second = MdnsService(
        instanceName: 'two',
        serviceType: '_openbikecontrol._tcp',
        port: 2000,
      );

      await advertiser.register(first);
      await advertiser.register(second);

      expect(advertiser.isAdvertising, isTrue);
      expect(advertiser.current, same(second));
      expect(advertiser.history, <MdnsService>[first, second]);
      expect(advertiser.registerCount, 2);

      await advertiser.unregister();
      expect(advertiser.isAdvertising, isFalse);
      expect(advertiser.current, isNull);
      // Unregistering twice is harmless.
      await advertiser.unregister();
      expect(advertiser.current, isNull);
    });

    test('validates the TXT records it receives', () async {
      final InMemoryMdnsAdvertiser advertiser = InMemoryMdnsAdvertiser();
      // MdnsService does not validate TXT: the advertiser must.
      final MdnsService bad = MdnsService(
        instanceName: 'bridge',
        serviceType: '_openbikecontrol._tcp',
        port: 1,
        txt: <String, String>{'n': 'a' * (MdnsTxt.maxValueLength + 1)},
      );

      await expectLater(advertiser.register(bad), throwsArgumentError);
      expect(advertiser.isAdvertising, isFalse);
    });
  });

  group('NoopMdnsAdvertiser', () {
    test('tracks the registered service without announcing it', () async {
      final NoopMdnsAdvertiser advertiser = NoopMdnsAdvertiser();
      expect(advertiser.isAdvertising, isFalse);

      await advertiser.register(
        MdnsService(
          instanceName: 'bridge',
          serviceType: '_openbikecontrol._tcp',
          port: 1,
        ),
      );
      expect(advertiser.isAdvertising, isTrue);

      await advertiser.unregister();
      expect(advertiser.isAdvertising, isFalse);
    });
  });

  group('PlatformMdnsAdvertiser', () {
    test('is explicitly unimplemented rather than silently inert', () async {
      const PlatformMdnsAdvertiser advertiser =
          PlatformMdnsAdvertiser(platformHint: 'android');

      await expectLater(
        advertiser.register(
          MdnsService(
            instanceName: 'bridge',
            serviceType: '_openbikecontrol._tcp',
            port: 1,
          ),
        ),
        throwsA(
          isA<UnimplementedError>().having(
            (UnimplementedError e) => e.message,
            'message',
            allOf(contains('android'), contains('NsdManager')),
          ),
        ),
      );
      // Nothing was announced, so removing is a no-op.
      await advertiser.unregister();
    });
  });
}
