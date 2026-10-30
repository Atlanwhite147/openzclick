/// Tests for the Bluetooth peripheral transport, driven by an in-memory backend.
library;

import 'dart:async';

import 'package:openzclick_transports/src/openzclick_transports.dart';
import 'package:openzclick_core/openzclick_core.dart';
import 'package:test/test.dart';

import 'socket_client.dart';

/// Backend double: records what would be published, never touches Bluetooth.
class FakeBleBackend implements BlePeripheralBackend {
  final StreamController<BleCentralEvent> _events =
      StreamController<BleCentralEvent>.broadcast();

  final List<
      ({
        String deviceName,
        String serviceUuid,
        Map<String, String> characteristics
      })> advertisements = <({
    String deviceName,
    String serviceUuid,
    Map<String, String> characteristics
  })>[];
  final List<({String uuid, List<int> value})> notifications =
      <({String uuid, List<int> value})>[];
  bool stopped = false;

  @override
  Future<void> advertise({
    required String deviceName,
    required String serviceUuid,
    required Map<String, String> characteristics,
  }) async {
    advertisements.add((
      deviceName: deviceName,
      serviceUuid: serviceUuid,
      characteristics: characteristics,
    ));
  }

  @override
  Future<void> notify(String characteristicUuid, List<int> value) async {
    notifications.add((uuid: characteristicUuid, value: List<int>.of(value)));
  }

  @override
  Stream<BleCentralEvent> get events => _events.stream;

  @override
  Future<void> stop() async {
    stopped = true;
  }

  void connect(String centralId) =>
      _events.add(BleCentralConnected(centralId: centralId));

  void disconnect(String centralId, {String? reason}) =>
      _events.add(BleCentralDisconnected(centralId: centralId, reason: reason));

  void write(String centralId, List<int> value) => _events.add(
        BleCentralWrite(
          centralId: centralId,
          characteristicUuid: BleGatt.hapticUuid,
          value: value,
        ),
      );

  Future<void> close() => _events.close();
}

void main() {
  group('BlePeripheralTransport', () {
    late FakeBleBackend backend;
    late BlePeripheralTransport transport;
    late EventLog<TransportEvent> log;

    setUp(() async {
      backend = FakeBleBackend();
      transport = BlePeripheralTransport(
        backend: backend,
        keymap: Keymap.defaults('test-app'),
        autoRelease: null,
      );
      log = EventLog<TransportEvent>(transport.events);
      await transport.start();
    });

    tearDown(() async {
      await log.cancel();
      await transport.dispose();
      await backend.close();
    });

    test('fails explicitly when no native backend is wired', () async {
      final BlePeripheralTransport unwired = BlePeripheralTransport();
      expect(unwired.hasBackend, isFalse);
      expect(unwired.centralIds, isEmpty);

      await expectLater(
        unwired.start(),
        throwsA(
          isA<UnimplementedError>().having(
            (UnimplementedError e) => e.message,
            'message',
            allOf(contains('BlePeripheralBackend'), contains('ble_peripheral')),
          ),
        ),
      );
      expect(unwired.isRunning, isFalse);
      await unwired.dispose();
    });

    test('advertises the GATT service and its characteristics', () {
      expect(transport.hasBackend, isTrue);
      expect(transport.isRunning, isTrue);
      expect(backend.advertisements, hasLength(1));

      final ({
        String deviceName,
        String serviceUuid,
        Map<String, String> characteristics
      }) advertisement = backend.advertisements.single;
      expect(advertisement.deviceName, 'openzclick');
      expect(advertisement.serviceUuid, BleGatt.serviceUuid);
      expect(
        advertisement.characteristics.keys,
        containsAll(
            <String>['buttonState', 'deviceStatus', 'haptic', 'appInfo']),
      );
      expect(advertisement.characteristics['buttonState'],
          BleGatt.buttonStateUuid);
    });

    test('notifies a button press when asked to emit', () async {
      await transport.emit(Action.shiftDown);

      expect(backend.notifications, hasLength(1));
      final ({String uuid, List<int> value}) first =
          backend.notifications.single;
      expect(first.uuid, BleGatt.buttonStateUuid);
      // 0x02 is the default button for Action.shiftDown.
      expect(first.value, <int>[0x01, 0x02, 0x02, 0x01]);

      await transport.release(Action.shiftDown);
      expect(backend.notifications.last.value, <int>[0x01, 0x02, 0x02, 0x00]);
    });

    test('releases a press automatically when configured', () async {
      await log.cancel();
      await transport.dispose();

      final FakeBleBackend fast = FakeBleBackend();
      final BlePeripheralTransport auto = BlePeripheralTransport(
        backend: fast,
        keymap: Keymap.defaults('test-app'),
        autoRelease: const Duration(milliseconds: 30),
      );
      log = EventLog<TransportEvent>(auto.events);
      await auto.start();

      await auto.emit(Action.menu);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(fast.notifications, hasLength(2));
      expect(fast.notifications.first.value.last, 1);
      expect(fast.notifications.last.value.last, 0);

      await auto.dispose();
      await fast.close();
    });

    test('publishes the device status on its own characteristic', () async {
      await transport.publishStatus(battery: 73, connected: true);
      final ({String uuid, List<int> value}) last =
          backend.notifications.single;
      expect(last.uuid, BleGatt.deviceStatusUuid);
      expect(last.value, <int>[0x02, 0x02, 73, 0x01]);
    });

    test('reports a connected central and reassembles split writes', () async {
      backend.connect('central-1');
      final TransportConnected connected = await log.next<TransportConnected>();
      expect(connected.peerId, 'central-1');
      expect(connected.transportId, 'ble_peripheral');
      expect(transport.centralIds, <String>['central-1']);

      final List<int> frame = ButtonStateMessage(<int, int>{0x10: 1}).encode();
      backend.write('central-1', frame.sublist(0, 1));
      await log.expectNone<TransportActionReceived>();

      backend.write('central-1', frame.sublist(1));
      final TransportActionReceived action =
          await log.next<TransportActionReceived>();
      expect(action.action, Action.navigateUp);
      expect(action.peerId, 'central-1');
    });

    test('decodes several writes concatenated in one notification', () async {
      backend.connect('central-1');
      await log.next<TransportConnected>();

      final List<int> haptic = HapticMessage(
        pattern: 2,
        duration10ms: 5,
        intensity: 200,
      ).encode();
      final List<int> info = AppInfoMessage(
        appId: 'target-app',
        appVersion: '1.0.0',
        supportedButtons: <int>[0x01],
      ).encode();

      backend.write('central-1', <int>[...haptic, ...info]);

      final TransportMessageReceived first =
          await log.next<TransportMessageReceived>();
      final TransportMessageReceived second =
          await log.next<TransportMessageReceived>();
      expect(first.message, isA<HapticCommand>());
      expect(second.message, isA<AppInfo>());
    });

    test('drops the buffer of a central that disconnects', () async {
      backend.connect('central-1');
      await log.next<TransportConnected>();

      final List<int> frame = ButtonStateMessage(<int, int>{0x10: 1}).encode();
      backend.write('central-1', frame.sublist(0, 1));

      backend.disconnect('central-1', reason: 'out of range');
      final TransportDisconnected gone =
          await log.next<TransportDisconnected>();
      expect(gone.reason, 'out of range');
      expect(transport.centralIds, isEmpty);

      // The partial frame is gone: reconnecting starts from a clean buffer.
      backend.connect('central-1');
      await log.next<TransportConnected>();
      backend.write('central-1', frame.sublist(1));
      await log.expectNone<TransportActionReceived>();
    });

    test('stops the backend and notes nothing else', () async {
      await transport.stop();
      expect(backend.stopped, isTrue);
      expect(transport.isRunning, isFalse);
      expect(transport.centralIds, isEmpty);
    });

    test('refuses to emit while stopped or without a binding', () async {
      final BlePeripheralTransport idle = BlePeripheralTransport(
        backend: FakeBleBackend(),
      );
      await expectLater(idle.emit(Action.shiftUp), throwsA(isA<StateError>()));
      await idle.dispose();

      final FakeBleBackend other = FakeBleBackend();
      final BlePeripheralTransport unbound = BlePeripheralTransport(
        backend: other,
        keymap: Keymap.empty('test-app'),
      );
      await unbound.start();
      await expectLater(
          unbound.emit(Action.shiftUp), throwsA(isA<ArgumentError>()));
      await unbound.dispose();
      await other.close();
    });
  });
}
