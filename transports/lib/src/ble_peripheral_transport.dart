/// Bluetooth peripheral transport (the bridge impersonates a sensor).
///
/// This file ships the complete skeleton: the contract of a native backend
/// ([BlePeripheralBackend]), the GATT identifiers of the project, and a
/// transport implementation that works as soon as a backend is supplied.
///
/// **What is not wired**: the native backend itself. Publishing a GATT
/// peripheral requires a platform API (`BluetoothGattServer` on Android,
/// `CBPeripheralManager` on iOS), hence a plugin, and this package may only
/// depend on `openzclick_core`, `meta` and `test`. Without a backend,
/// [BlePeripheralTransport.start] throws [UnimplementedError] naming exactly
/// what is missing: no code path pretends to work.
library;

import 'dart:async';

import 'events.dart';
import 'transport.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// GATT identifiers of the project.
///
/// 128-bit UUIDs derived from the project name, outside the Bluetooth SIG space:
/// they belong to no commercial body and can be frozen as they are in the
/// protocol. The last digits distinguish the service and its characteristics.
abstract final class BleGatt {
  /// Main service exposed by the bridge.
  static const String serviceUuid = '526f7565-4c69-6272-6500-000000000001';

  /// Button state characteristic (`0x01`), notified by the bridge.
  static const String buttonStateUuid = '526f7565-4c69-6272-6500-000000000002';

  /// Device status characteristic (`0x02`), notified by the bridge.
  static const String deviceStatusUuid = '526f7565-4c69-6272-6500-000000000003';

  /// Haptic command characteristic (`0x03`), written by the central.
  static const String hapticUuid = '526f7565-4c69-6272-6500-000000000004';

  /// Application information characteristic (`0x04`), written by the central.
  static const String appInfoUuid = '526f7565-4c69-6272-6500-000000000005';

  /// Readable role to UUID map, in service order.
  static const Map<String, String> characteristics = <String, String>{
    'buttonState': buttonStateUuid,
    'deviceStatus': deviceStatusUuid,
    'haptic': hapticUuid,
    'appInfo': appInfoUuid,
  };
}

/// Event reported by a Bluetooth peripheral backend.
sealed class BleCentralEvent {
  /// Builds an event attributed to the central [centralId].
  const BleCentralEvent({required this.centralId});

  /// Central identifier (the device connected to the bridge).
  final String centralId;
}

/// A central subscribed to the bridge.
class BleCentralConnected extends BleCentralEvent {
  /// Builds a connection event.
  const BleCentralConnected({required super.centralId});
}

/// A central disconnected.
class BleCentralDisconnected extends BleCentralEvent {
  /// Builds a disconnection event.
  const BleCentralDisconnected({required super.centralId, this.reason});

  /// Readable cause, `null` when the disconnection is intentional.
  final String? reason;
}

/// A central wrote a value into a characteristic.
class BleCentralWrite extends BleCentralEvent {
  /// Builds a write event.
  const BleCentralWrite({
    required super.centralId,
    required this.characteristicUuid,
    required this.value,
  });

  /// Written characteristic.
  final String characteristicUuid;

  /// Received bytes, as is.
  final List<int> value;
}

/// Native backend to be supplied by the application.
///
/// A real implementation relies on a platform API; a test implementation may
/// stay in memory. The transport assumes nothing beyond this contract.
abstract interface class BlePeripheralBackend {
  /// Publishes the peripheral and its GATT service, and starts accepting
  /// centrals.
  Future<void> advertise({
    required String deviceName,
    required String serviceUuid,
    required Map<String, String> characteristics,
  });

  /// Notifies [value] on [characteristicUuid] to every subscribed central.
  Future<void> notify(String characteristicUuid, List<int> value);

  /// Central events (connection, disconnection, write).
  Stream<BleCentralEvent> get events;

  /// Removes the announcement, disconnects the centrals and releases the
  /// backend.
  Future<void> stop();
}

/// Bluetooth peripheral transport.
///
/// Works as soon as a [backend] is supplied; without one, [start] fails
/// explicitly.
class BlePeripheralTransport extends ManagedTransport {
  /// Creates the transport.
  ///
  /// [backend] is the native backend: `null` until the platform wiring exists,
  /// which makes [start] immediately explicit. [keymap] translates received
  /// `0x01` frames into actions; without a table, frames are published raw.
  /// [deviceName] is the advertised name.
  BlePeripheralTransport({
    this.backend,
    this.keymap,
    this.deviceName = 'openzclick',
    this.autoRelease = const Duration(milliseconds: 60),
  });

  /// Native backend, `null` when not wired.
  final BlePeripheralBackend? backend;

  /// Button to action table.
  final Keymap? keymap;

  /// Advertised peripheral name.
  final String deviceName;

  /// Automatic release delay for presses, `null` to disable it.
  final Duration? autoRelease;

  StreamSubscription<BleCentralEvent>? _subscription;
  final Map<String, List<int>> _buffers = <String, List<int>>{};
  final Set<Timer> _releaseTimers = <Timer>{};
  final List<String> _centrals = <String>[];

  /// Maximum buffered bytes per central before the buffer is considered bogus.
  static const int maxBufferBytes = 512;

  @override
  String get id => 'ble_peripheral';

  /// Identifiers of the connected centrals.
  List<String> get centralIds => List<String>.unmodifiable(_centrals);

  /// True when a backend was supplied (not necessarily started).
  bool get hasBackend => backend != null;

  @override
  Future<void> onStart() async {
    final BlePeripheralBackend? backend = this.backend;
    if (backend == null) {
      throw UnimplementedError(
        'Bluetooth peripheral not wired: supply a BlePeripheralBackend '
        '(BluetoothGattServer on Android, CBPeripheralManager on iOS) to the '
        'constructor of $id before start()',
      );
    }
    _subscription = backend.events.listen(_onCentralEvent);
    try {
      await backend.advertise(
        deviceName: deviceName,
        serviceUuid: BleGatt.serviceUuid,
        characteristics: BleGatt.characteristics,
      );
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      rethrow;
    }
  }

  @override
  Future<void> onStop() async {
    for (final Timer timer in _releaseTimers) {
      timer.cancel();
    }
    _releaseTimers.clear();
    await _subscription?.cancel();
    _subscription = null;
    _buffers.clear();
    _centrals.clear();
    await backend?.stop();
  }

  /// Notifies the press matching [action] to the subscribed centrals.
  @override
  Future<void> emit(Action action) async {
    if (!isRunning) {
      throw StateError(
          'transport $id stopped: start() is required before emit()');
    }
    final int buttonId = _buttonIdFor(action);
    await _notifyButton(buttonId, 1);
    final Duration? delay = autoRelease;
    if (delay != null) {
      late final Timer timer;
      timer = Timer(delay, () {
        _releaseTimers.remove(timer);
        if (isRunning) {
          unawaited(_notifyButton(buttonId, 0));
        }
      });
      _releaseTimers.add(timer);
    }
  }

  /// Explicitly notifies the release of [action].
  Future<void> release(Action action) async {
    if (!isRunning) {
      throw StateError(
          'transport $id stopped: start() is required before release()');
    }
    await _notifyButton(_buttonIdFor(action), 0);
  }

  /// Notifies the device status (`0x02`).
  Future<void> publishStatus({
    required int battery,
    required bool connected,
  }) async {
    if (!isRunning) {
      throw StateError(
        'transport $id stopped: start() is required before publishStatus()',
      );
    }
    await backend?.notify(
      BleGatt.deviceStatusUuid,
      DeviceStatusMessage(battery: battery, connected: connected).encode(),
    );
  }

  Future<void> _notifyButton(int buttonId, int value) async {
    await backend?.notify(
      BleGatt.buttonStateUuid,
      ButtonStateMessage(<int, int>{buttonId: value}).encode(),
    );
  }

  int _buttonIdFor(Action action) {
    final Keymap? table = keymap;
    if (table == null) {
      throw ArgumentError(
        'no binding table: cannot translate ${action.name} into a button '
        'identifier',
      );
    }
    final List<int> candidates = table.bindings.entries
        .where((MapEntry<int, Action> entry) => entry.value == action)
        .map((MapEntry<int, Action> entry) => entry.key)
        .toList()
      ..sort();
    if (candidates.isEmpty) {
      throw ArgumentError(
        'action ${action.name} is not bound to any button in the table',
      );
    }
    return candidates.first;
  }

  void _onCentralEvent(BleCentralEvent event) {
    switch (event) {
      case BleCentralConnected(:final String centralId):
        if (!_centrals.contains(centralId)) {
          _centrals.add(centralId);
        }
        publish(TransportConnected(transportId: id, peerId: centralId));
      case BleCentralDisconnected(
          :final String centralId,
          :final String? reason,
        ):
        _centrals.remove(centralId);
        _buffers.remove(centralId);
        publish(
          TransportDisconnected(
            transportId: id,
            peerId: centralId,
            reason: reason,
          ),
        );
      case BleCentralWrite(:final String centralId, :final List<int> value):
        _onWrite(centralId, value);
    }
  }

  void _onWrite(String centralId, List<int> value) {
    final List<int> buffer = _buffers.putIfAbsent(centralId, () => <int>[])
      ..addAll(value);
    while (true) {
      final ({ObcMessage message, int consumed})? decoded =
          ObcCodec.tryDecode(buffer);
      if (decoded == null) {
        final int discard = ObcCodec.discardCount(buffer);
        if (discard > 0) {
          buffer.removeRange(0, discard);
        }
        if (buffer.length > maxBufferBytes) {
          // Bogus write: start over from a clean buffer.
          publishError('BLE buffer overflow for $centralId', peerId: centralId);
          buffer.clear();
        }
        return;
      }
      buffer.removeRange(0, decoded.consumed);
      _publishMessage(centralId, decoded.message);
    }
  }

  void _publishMessage(String centralId, ObcMessage message) {
    if (message is ButtonState) {
      final Keymap? table = keymap;
      if (table != null) {
        for (final MapEntry<int, int> entry in message.buttons.entries) {
          if (entry.value == 0) {
            continue;
          }
          final Action action = table.actionFor(entry.key);
          if (action == Action.none) {
            continue;
          }
          publish(TransportActionReceived(
            transportId: id,
            action: action,
            peerId: centralId,
            value: entry.value,
          ));
        }
      }
    }
    publish(TransportMessageReceived(
      transportId: id,
      message: message,
      peerId: centralId,
    ));
  }
}
