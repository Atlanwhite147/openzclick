/// Tests for the mDNS/TCP transport: real loopback sockets, in-memory mDNS.
library;

import 'dart:io';

import 'package:openzclick_transports/src/openzclick_transports.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

import 'socket_client.dart';

void main() {
  group('MdnsTcpTransport', () {
    late InMemoryMdnsAdvertiser advertiser;
    late MdnsTcpTransport transport;
    late EventLog<TransportEvent> log;

    setUp(() async {
      advertiser = InMemoryMdnsAdvertiser();
      transport = MdnsTcpTransport(
        keymap: Keymap.defaults('test-app'),
        instanceName: 'bridge-test',
        advertiser: advertiser,
        bindAddress: InternetAddress.loopbackIPv4,
        autoRelease: null,
      );
      log = EventLog<TransportEvent>(transport.events);
      await transport.start();
    });

    tearDown(() async {
      await log.cancel();
      await transport.dispose();
    });

    test('advertises the TCP port with the required TXT records', () {
      expect(transport.isRunning, isTrue);
      expect(transport.listeningPort, greaterThan(0));

      final MdnsService? service = advertiser.current;
      expect(service, isNotNull);
      expect(service!.serviceType, MdnsTcpTransport.serviceType);
      expect(service.serviceType, '_openbikecontrol._tcp');
      expect(service.port, transport.listeningPort);
      expect(service.instanceName, 'bridge-test');
      expect(service.txt[MdnsTxt.versionKey], MdnsTxt.currentVersion);
      expect(service.txt[MdnsTxt.nameKey], 'bridge-test');
      expect(service.txt[MdnsTxt.roleKey], 'bridge');
      // Button identifiers are announced sorted, whatever the keymap order.
      expect(service.txt[MdnsTxt.buttonsKey], startsWith('01,'));
      expect(transport.isAdvertising, isTrue);
    });

    test('reports a connecting client', () async {
      final SocketClient client =
          await SocketClient.connect(transport.listeningPort);
      final TransportConnected connected = await log.next<TransportConnected>();

      expect(connected.transportId, 'mdns_tcp');
      expect(connected.peerId, 'peer-1');
      expect(connected.label, contains('127.0.0.1'));

      await client.close();
    });

    test('reassembles a button frame sent in two chunks', () async {
      final SocketClient client =
          await SocketClient.connect(transport.listeningPort);
      await log.next<TransportConnected>();

      final List<int> frame = ButtonStateMessage(<int, int>{0x01: 1}).encode();
      await client.send(frame.sublist(0, 2));
      await log.expectNone<TransportActionReceived>();

      await client.send(frame.sublist(2));

      final TransportActionReceived action =
          await log.next<TransportActionReceived>();
      expect(action.action, Action.shiftUp);
      expect(action.value, 1);
      expect(action.peerId, 'peer-1');

      await client.close();
    });

    test('decodes concatenated status and app info frames', () async {
      final SocketClient client =
          await SocketClient.connect(transport.listeningPort);
      await log.next<TransportConnected>();

      final List<int> status =
          DeviceStatusMessage(battery: 87, connected: true).encode();
      final List<int> info = AppInfoMessage(
        appId: 'target-app',
        appVersion: '2.1.0',
        supportedButtons: <int>[0x01, 0x02, 0x10],
      ).encode();
      await client.send(<int>[...status, ...info]);

      final TransportMessageReceived first =
          await log.next<TransportMessageReceived>();
      final TransportMessageReceived second =
          await log.next<TransportMessageReceived>();
      expect(first.message, isA<DeviceStatus>());
      expect(second.message, isA<AppInfo>());

      expect(transport.remoteStatus?.battery, 87);
      expect(transport.remoteAppInfo?.appId, 'target-app');
      expect(
          transport.remoteAppInfo?.supportedButtons, <int>[0x01, 0x02, 0x10]);

      await client.close();
    });

    test('emit pushes a button press to every client', () async {
      final SocketClient first =
          await SocketClient.connect(transport.listeningPort);
      await log.next<TransportConnected>();
      final SocketClient second =
          await SocketClient.connect(transport.listeningPort);
      await log.next<TransportConnected>();

      await transport.emit(Action.shiftUp);
      final List<int> press = <int>[0x01, 0x02, 0x01, 0x01];
      expect(await first.take(press.length), press);
      expect(await second.take(press.length), press);

      await transport.release(Action.shiftUp);
      final List<int> releaseFrame = <int>[0x01, 0x02, 0x01, 0x00];
      expect(await first.take(releaseFrame.length), releaseFrame);
      expect(await second.take(releaseFrame.length), releaseFrame);

      await first.close();
      await second.close();
    });

    test('publishStatus encodes a device status frame', () async {
      final SocketClient client =
          await SocketClient.connect(transport.listeningPort);
      await log.next<TransportConnected>();

      await transport.publishStatus(battery: 42, connected: false);
      final List<int> frame = await client.take(4);
      expect(frame, <int>[0x02, 0x02, 42, 0x00]);

      await client.close();
    });

    test('reports an error when emitting without any client', () async {
      await transport.emit(Action.shiftUp);
      final TransportError error = await log.next<TransportError>();
      expect(error.message, contains('no client'));

      await transport.release(Action.shiftUp);
      await log.next<TransportError>();
    });

    test('stop removes the announcement and closes the clients', () async {
      final SocketClient client =
          await SocketClient.connect(transport.listeningPort);
      await log.next<TransportConnected>();
      final int port = transport.listeningPort;

      await transport.stop();

      expect(transport.isRunning, isFalse);
      expect(advertiser.current, isNull);
      expect(transport.isAdvertising, isFalse);
      expect(transport.peerIds, isEmpty);

      final TransportDisconnected gone =
          await log.next<TransportDisconnected>();
      expect(gone.reason, 'server stopped');

      // The port is actually released.
      final ServerSocket probe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await probe.close();

      await client.close();
    });

    test('auto releases a press after the configured delay', () async {
      await log.cancel();
      await transport.dispose();

      advertiser = InMemoryMdnsAdvertiser();
      transport = MdnsTcpTransport(
        keymap: Keymap.defaults('test-app'),
        advertiser: advertiser,
        bindAddress: InternetAddress.loopbackIPv4,
        autoRelease: const Duration(milliseconds: 40),
      );
      log = EventLog<TransportEvent>(transport.events);
      await transport.start();

      final SocketClient client =
          await SocketClient.connect(transport.listeningPort);
      await log.next<TransportConnected>();

      await transport.emit(Action.confirm);
      // 0x14 is the default button for Action.confirm.
      expect(await client.take(4), <int>[0x01, 0x02, 0x14, 0x01]);
      expect(await client.take(4), <int>[0x01, 0x02, 0x14, 0x00]);

      await client.close();
    });

    test('refuses to emit an action that has no button', () async {
      await log.cancel();
      await transport.dispose();

      advertiser = InMemoryMdnsAdvertiser();
      transport = MdnsTcpTransport(
        keymap: Keymap.empty('test-app'),
        advertiser: advertiser,
        bindAddress: InternetAddress.loopbackIPv4,
      );
      log = EventLog<TransportEvent>(transport.events);
      await transport.start();

      await expectLater(
        transport.emit(Action.shiftUp),
        throwsA(isA<ArgumentError>()),
      );

      // Without any keymap, the same call is also refused.
      final MdnsTcpTransport bare = MdnsTcpTransport(
        advertiser: InMemoryMdnsAdvertiser(),
        bindAddress: InternetAddress.loopbackIPv4,
      );
      await bare.start();
      await expectLater(
          bare.emit(Action.shiftUp), throwsA(isA<ArgumentError>()));
      await bare.dispose();
    });

    test('refuses to emit before start', () async {
      final MdnsTcpTransport idle = MdnsTcpTransport(
        keymap: Keymap.defaults('test-app'),
        advertiser: InMemoryMdnsAdvertiser(),
        bindAddress: InternetAddress.loopbackIPv4,
      );
      await expectLater(idle.emit(Action.shiftUp), throwsA(isA<StateError>()));
      await idle.dispose();
    });

    test('fails explicitly with the unwired native advertiser', () async {
      final PlatformMdnsAdvertiser platform =
          PlatformMdnsAdvertiser(platformHint: 'linux');
      final MdnsTcpTransport native = MdnsTcpTransport(
        keymap: Keymap.defaults('test-app'),
        advertiser: platform,
        bindAddress: InternetAddress.loopbackIPv4,
      );

      await expectLater(
        native.start(),
        throwsA(
          isA<UnimplementedError>().having(
            (UnimplementedError e) => e.message,
            'message',
            allOf(contains('mDNS'), contains('linux')),
          ),
        ),
      );
      expect(native.isRunning, isFalse);
      // No half-started transport: a second start reaches the same error, and
      // the socket was released in between.
      await expectLater(native.start(), throwsA(isA<UnimplementedError>()));
      await native.dispose();
    });
  });
}
