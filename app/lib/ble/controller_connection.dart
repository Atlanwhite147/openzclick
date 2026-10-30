import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:openzclick_core/openzclick_core.dart';

/// State of the connection to a physical controller.
enum ControllerStatus {
  /// Not connected.
  idle,

  /// Scanning for advertisments.
  scanning,

  /// Connecting and discovering services.
  connecting,

  /// Connected, handshake sent, frames expected.
  ready,

  /// Something went wrong; [ControllerConnection.error] holds the reason.
  failed,
}

/// A bridge between the Bluetooth stack and the core protocol.
///
/// The class owns one BLE connection at a time. It performs the plain
/// handshake, decodes frames with [ControllerCodec] and republishes button
/// states as a stream of [ClickButtons].
class ControllerConnection {
  /// Bluetooth device currently targeted, if any.
  BluetoothDevice? device;

  /// Last known status.
  ControllerStatus status = ControllerStatus.idle;

  /// Last error message, cleared on a successful connect.
  String? error;

  /// Battery level reported by the controller, if received.
  int? batteryPercent;

  final StreamController<ClickButtons> _buttons =
      StreamController<ClickButtons>.broadcast();

  /// True once the handshake completed with encryption enabled.
  bool encrypted = false;

  ControllerKeyPair? _keyPair;
  ControllerCrypto? _crypto;
  BluetoothCharacteristic? _tx;
  bool _handshakeSeen = false;

  StreamSubscription<List<int>>? _frameSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final List<ScanResult> _found = <ScanResult>[];

  /// Button states, emitted on every change.
  Stream<ClickButtons> get buttons => _buttons.stream;

  /// Devices discovered during the last scan.
  List<ScanResult> get found => List<ScanResult>.unmodifiable(_found);

  /// Callback invoked whenever the status or the device list changes.
  void Function()? onChanged;

  void _notify() => onChanged?.call();

  /// Scans for controllers advertising the expected service.
  ///
  /// Stops by itself after [timeout]; results accumulate in [found].
  Future<void> scan({Duration timeout = const Duration(seconds: 8)}) async {
    await _scanSubscription?.cancel();
    _found.clear();
    status = ControllerStatus.scanning;
    error = null;
    _notify();

    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      (List<ScanResult> results) {
        for (final ScanResult result in results) {
          if (_found.every((ScanResult r) => r.device.remoteId != result.device.remoteId)) {
            _found.add(result);
          }
        }
        _notify();
      },
      onError: (Object e) {
        status = ControllerStatus.failed;
        error = e.toString();
        _notify();
      },
    );

    try {
      await FlutterBluePlus.startScan(
        withServices: <Guid>[Guid(ControllerUuids.service)],
        timeout: timeout,
      );
    } catch (e) {
      status = ControllerStatus.failed;
      error = e.toString();
      _notify();
      return;
    }

    await Future<void>.delayed(timeout);
    status = ControllerStatus.idle;
    _notify();
  }

  /// Connects to [target], discovers the service and performs the handshake.
  Future<void> connect(BluetoothDevice target) async {
    status = ControllerStatus.connecting;
    error = null;
    _notify();
    device = target;

    try {
      await FlutterBluePlus.stopScan();
      await target.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      final List<BluetoothService> services = await target.discoverServices();

      BluetoothCharacteristic? rx;
      BluetoothCharacteristic? tx;
      for (final BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() != ControllerUuids.service) {
          continue;
        }
        for (final BluetoothCharacteristic characteristic
            in service.characteristics) {
          final String uuid = characteristic.uuid.toString().toLowerCase();
          if (uuid == ControllerUuids.syncRx) rx = characteristic;
          if (uuid == ControllerUuids.syncTx) tx = characteristic;
        }
      }

      if (rx == null || tx == null) {
        throw StateError('controller service found but channels are missing');
      }
      _tx = tx;

      await rx.setNotifyValue(true);
      _frameSubscription = rx.onValueReceived.listen(_onFrame);

      // Ask for an encrypted session first; some firmware only answers the
      // plain handshake, so the plain request is sent as a fallback below.
      _keyPair = ControllerCrypto.generateKeyPair();
      _crypto = null;
      encrypted = false;
      _handshakeSeen = false;
      await tx.write(
        ControllerHandshake.encryptedRequest(_keyPair!.publicKeyBytes),
      );

      Future<void>.delayed(const Duration(seconds: 3), () async {
        if (!_handshakeSeen) {
          try {
            await _tx?.write(ControllerHandshake.plainRequest());
          } catch (_) {
            // The link may already be gone; the status reflects it.
          }
        }
      });

      status = ControllerStatus.ready;
      _notify();
    } catch (e) {
      status = ControllerStatus.failed;
      error = e.toString();
      _notify();
    }
  }

  void _onFrame(List<int> frame) {
    if (frame.isEmpty) return;

    // Handshake acknowledgement: RideOn, optionally followed by a public key.
    if (frame.length >= ControllerHandshake.rideOn.length) {
      bool startsWithRideOn = true;
      for (int i = 0; i < ControllerHandshake.rideOn.length; i++) {
        if (frame[i] != ControllerHandshake.rideOn[i]) {
          startsWithRideOn = false;
          break;
        }
      }
      if (startsWithRideOn) {
        _handshakeSeen = true;
        final List<int>? deviceKey =
            ControllerHandshake.parseDevicePublicKey(frame);
        if (deviceKey != null && _keyPair != null) {
          _crypto = ControllerCrypto.derive(
            devicePublicKeyBytes: deviceKey,
            localKeyPair: _keyPair!,
          );
          encrypted = true;
        }
        status = ControllerStatus.ready;
        _notify();
        return;
      }
    }

    List<int> payload = frame;
    if (_crypto != null) {
      final List<int>? decrypted = _crypto!.decryptFrame(frame);
      if (decrypted == null) return;
      payload = decrypted;
    }

    final ControllerMessage? message = ControllerCodec.decode(payload);
    if (message is ClickMessage) {
      _buttons.add(message.buttons);
    } else if (message is BatteryMessage) {
      batteryPercent = message.percent;
      _notify();
    }
  }

  /// Closes the connection and releases the subscriptions.
  Future<void> disconnect() async {
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await device?.disconnect();
    } catch (_) {
      // The device may already be gone; nothing to repair.
    }
    device = null;
    _crypto = null;
    _keyPair = null;
    _tx = null;
    encrypted = false;
    status = ControllerStatus.idle;
    batteryPercent = null;
    _notify();
  }

  /// Releases every resource.
  Future<void> dispose() async {
    await disconnect();
    await _buttons.close();
  }
}
