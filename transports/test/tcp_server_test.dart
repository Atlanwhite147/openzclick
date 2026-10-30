/// Tests for the TCP framing server, with real sockets and no hardware.
library;

import 'dart:async';
import 'dart:io';

import 'package:openzclick_transports/src/openzclick_transports.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

import 'socket_client.dart';

void main() {
  group('FramedTcpServer', () {
    late FramedTcpServer server;
    late EventLog<ServerEvent> log;

    setUp(() async {
      server = FramedTcpServer(bindAddress: InternetAddress.loopbackIPv4);
      await server.start();
      log = EventLog<ServerEvent>(server.events);
    });

    tearDown(() async {
      await log.cancel();
      await server.dispose();
    });

    test('binds an ephemeral port and stops cleanly', () async {
      expect(server.isRunning, isTrue);
      expect(server.listeningPort, greaterThan(0));

      final int port = server.listeningPort;
      await server.stop();
      expect(server.isRunning, isFalse);
      expect(server.peerCount, 0);

      // The port is really released: a fresh server can take it over.
      final FramedTcpServer again = FramedTcpServer(
        bindAddress: InternetAddress.loopbackIPv4,
        port: port,
      );
      await again.start();
      expect(again.listeningPort, port);
      await again.dispose();
    });

    test('reports a connecting client with its remote address', () async {
      final SocketClient client =
          await SocketClient.connect(server.listeningPort);
      final PeerConnected event = await log.next<PeerConnected>();

      expect(event.peerId, 'peer-1');
      expect(event.address, '127.0.0.1');
      expect(event.port, greaterThan(0));
      expect(server.peerCount, 1);
      expect(server.peerIds, <String>['peer-1']);

      await client.close();
    });

    test('reassembles a frame split across two writes', () async {
      final SocketClient client =
          await SocketClient.connect(server.listeningPort);
      await log.next<PeerConnected>();

      final List<int> frame = ButtonStateMessage(<int, int>{0x10: 1}).encode();
      expect(frame, <int>[0x01, 0x02, 0x10, 0x01]);

      await client.send(frame.sublist(0, 1));
      await log.expectNone<PeerMessage>();

      await client.send(frame.sublist(1));
      final PeerMessage message = await log.next<PeerMessage>();
      final ObcMessage decoded = message.message;
      expect(decoded, isA<ButtonState>());
      expect((decoded as ButtonState).buttons, <int, int>{0x10: 1});

      await client.close();
    });

    test('splits several frames concatenated in one write', () async {
      final SocketClient client =
          await SocketClient.connect(server.listeningPort);
      await log.next<PeerConnected>();

      final List<int> buttons =
          ButtonStateMessage(<int, int>{0x01: 1}).encode();
      final List<int> status =
          DeviceStatusMessage(battery: 50, connected: true).encode();

      await client.send(<int>[...buttons, ...status]);

      final PeerMessage first = await log.next<PeerMessage>();
      final PeerMessage second = await log.next<PeerMessage>();
      expect(first.message, isA<ButtonState>());
      expect((first.message as ButtonState).buttons, <int, int>{0x01: 1});
      expect(second.message, isA<DeviceStatus>());
      expect((second.message as DeviceStatus).battery, 50);
      expect((second.message as DeviceStatus).connected, isTrue);

      await client.close();
    });

    test('skips unknown leading bytes and resynchronises', () async {
      final SocketClient client =
          await SocketClient.connect(server.listeningPort);
      await log.next<PeerConnected>();

      final List<int> frame = ButtonStateMessage(<int, int>{0x02: 1}).encode();
      await client.send(<int>[0x7F, 0x00, 0xEA, ...frame]);

      final PeerMessage message = await log.next<PeerMessage>();
      expect((message.message as ButtonState).buttons, <int, int>{0x02: 1});

      await client.close();
    });

    test('drops an oversized button frame and recovers on the next one',
        () async {
      final SocketClient client =
          await SocketClient.connect(server.listeningPort);
      await log.next<PeerConnected>();

      // 0x01 claiming a 48 byte body is aberrant (maximum frame is 20 bytes):
      // the declared length is authoritative, so the frame is skipped whole.
      await client.send(<int>[0x01, 0x30, 0x0A, 0x0B]);
      await log.expectNone<PeerMessage>();

      final List<int> frame = ButtonStateMessage(<int, int>{0x14: 1}).encode();
      await client.send(frame);

      final PeerMessage message = await log.next<PeerMessage>();
      expect((message.message as ButtonState).buttons, <int, int>{0x14: 1});
      expect(server.peerCount, 1);

      await client.close();
    });

    test('serves several clients and broadcasts to all of them', () async {
      final SocketClient first =
          await SocketClient.connect(server.listeningPort);
      await log.next<PeerConnected>();
      final SocketClient second =
          await SocketClient.connect(server.listeningPort);
      await log.next<PeerConnected>();

      expect(server.peerCount, 2);
      expect(server.peerIds, <String>['peer-1', 'peer-2']);

      final List<int> frame = ButtonStateMessage(<int, int>{0x18: 1}).encode();
      await server.broadcast(frame);

      expect(await first.take(frame.length), frame);
      expect(await second.take(frame.length), frame);

      await server.send('peer-1', frame);
      expect(await first.take(frame.length), frame);
      // The other peer did not receive the targeted write.
      await expectLater(
        second.take(frame.length, timeout: const Duration(milliseconds: 200)),
        throwsA(isA<TimeoutException>()),
      );

      await first.close();
      final PeerDisconnected gone = await log.next<PeerDisconnected>();
      expect(gone.peerId, 'peer-1');
      expect(server.peerCount, 1);

      await second.close();
    });

    test('isolates a malformed client from the others', () async {
      await server.stop();
      await log.cancel();

      final FramedTcpServer small = FramedTcpServer(
        bindAddress: InternetAddress.loopbackIPv4,
        maxBufferBytes: 64,
      );
      await small.start();
      final EventLog<ServerEvent> smallLog =
          EventLog<ServerEvent>(small.events);

      final SocketClient good = await SocketClient.connect(small.listeningPort);
      await smallLog.next<PeerConnected>();
      final SocketClient bad = await SocketClient.connect(small.listeningPort);
      await smallLog.next<PeerConnected>();

      // appInfo frames announcing a 255 byte body never complete: the buffer of
      // this client alone grows past its cap and the connection is cut.
      final List<int> junk = <int>[];
      for (int i = 0; i < 200; i++) {
        junk.addAll(<int>[0x04, 0xFF]);
      }
      await bad.send(junk);

      final PeerFault fault = await smallLog.next<PeerFault>();
      expect(fault.peerId, 'peer-2');
      final PeerDisconnected closed = await smallLog.next<PeerDisconnected>();
      expect(closed.peerId, 'peer-2');

      // The healthy client still works.
      final List<int> frame = ButtonStateMessage(<int, int>{0x10: 1}).encode();
      await good.send(frame);
      final PeerMessage message = await smallLog.next<PeerMessage>();
      expect(message.peerId, 'peer-1');

      await bad.close();
      await good.close();
      await smallLog.cancel();
      await small.dispose();
    });

    test('drops a peer whose buffer overflows', () async {
      await server.stop();
      await log.cancel();

      final FramedTcpServer small = FramedTcpServer(
        bindAddress: InternetAddress.loopbackIPv4,
        maxBufferBytes: 32,
      );
      await small.start();
      final EventLog<ServerEvent> smallLog =
          EventLog<ServerEvent>(small.events);

      final SocketClient client =
          await SocketClient.connect(small.listeningPort);
      await smallLog.next<PeerConnected>();

      // 0x04 claims a 255 byte body: the buffer keeps growing, never completes.
      for (int i = 0; i < 20; i++) {
        await client.send(<int>[0x04, 0xFF]);
      }

      final PeerFault fault = await smallLog.next<PeerFault>();
      expect(fault.message, contains('overflow'));
      await smallLog.next<PeerDisconnected>();
      expect(small.peerCount, 0);

      await client.close();
      await smallLog.cancel();
      await small.dispose();
    });

    test('closes connected peers when stopped', () async {
      final SocketClient client =
          await SocketClient.connect(server.listeningPort);
      await log.next<PeerConnected>();

      await server.stop();

      final PeerDisconnected closed = await log.next<PeerDisconnected>();
      expect(closed.peerId, 'peer-1');
      expect(closed.reason, 'server stopped');
      expect(server.peerCount, 0);
      await client.done.timeout(const Duration(seconds: 5));

      await client.close();
    });

    test('keeps running after an invalid frame', () async {
      final SocketClient client =
          await SocketClient.connect(server.listeningPort);
      await log.next<PeerConnected>();

      // 0x02 with an incoherent body: dropped, the stream stays alive.
      await client.send(<int>[0x02, 0x02, 0x01, 0x05]);
      await log.expectNone<PeerMessage>();

      final List<int> frame = ButtonStateMessage(<int, int>{0x10: 1}).encode();
      await client.send(frame);

      final PeerMessage message = await log.next<PeerMessage>();
      expect((message.message as ButtonState).buttons, <int, int>{0x10: 1});

      await client.close();
    });

    test('rejects double start and unknown peer writes', () async {
      await expectLater(server.start(), throwsA(isA<StateError>()));
      // Sending to a peer that does not exist is not an error.
      await server.send('peer-99', <int>[0x01, 0x00]);
      await server.closePeer('peer-99');
    });
  });
}
