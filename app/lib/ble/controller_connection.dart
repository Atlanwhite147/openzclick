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
/// The class owns one BLE connection at a time. It performs the encrypted
/// handshake, falls back to the plain one when the firmware ignores it,
/// decodes frames with [ControllerCodec] and republishes button states as a
/// stream of [ClickButtons].
///
/// The three characteristics of the controller do not do the same job, and
/// swapping two of them produces a link that connects and then stays silent:
///
/// | Characteristic | UUID suffix | Direction | Used for |
/// |---|---|---|---|
/// | async | `0002` | controller to host, notify | the button stream |
/// | syncRx | `0003` | host to controller, write | handshake and commands |
/// | syncTx | `0004` | controller to host, indicate | handshake reply and answers |
///
/// A controller that has never been paired in the official application may
/// answer nothing at all: [needsUnlock] is then set and the interface must say
/// so, because no amount of reconnecting will change it.
class ControllerConnection {
  /// Bluetooth device currently targeted, if any.
  BluetoothDevice? device;

  /// Last known status.
  ControllerStatus status = ControllerStatus.idle;

  /// Last error message, cleared on a successful connect.
  String? error;

  /// Battery level reported by the controller, if received.
  int? batteryPercent;

  /// True when the controller stayed completely silent after the handshake,
  /// which almost always means it must be paired once in the official
  /// application before it accepts any other host.
  bool needsUnlock = false;

  final StreamController<ClickButtons> _buttons =
      StreamController<ClickButtons>.broadcast();

  /// True once the handshake completed with encryption enabled.
  bool encrypted = false;

  ControllerKeyPair? _keyPair;
  ControllerCrypto? _crypto;
  BluetoothCharacteristic? _writeTarget;
  final List<StreamSubscription<List<int>>> _frameSubscriptions =
      <StreamSubscription<List<int>>>[];
  Timer? _supervision;
  final ControllerLinkWatchdog _watchdog = ControllerLinkWatchdog();
  bool _reconnecting = false;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
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
          if (_found.every(
            (ScanResult r) => r.device.remoteId != result.device.remoteId,
          )) {
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
    needsUnlock = false;
    _notify();
    device = target;

    try {
      await FlutterBluePlus.stopScan();
      await target.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      final List<BluetoothService> services = await target.discoverServices();

      BluetoothCharacteristic? asyncChannel;
      BluetoothCharacteristic? writeTarget;
      BluetoothCharacteristic? syncReply;
      for (final BluetoothService service in services) {
        final String serviceUuid = service.uuid.toString().toLowerCase();
        if (serviceUuid != ControllerUuids.service) {
          continue;
        }
        for (final BluetoothCharacteristic characteristic
            in service.characteristics) {
          final String uuid = characteristic.uuid.toString().toLowerCase();
          if (uuid == ControllerUuids.asyncChannel) {
            asyncChannel = characteristic;
          }
          if (uuid == ControllerUuids.syncRx) writeTarget = characteristic;
          if (uuid == ControllerUuids.syncTx) syncReply = characteristic;
        }
      }

      if (asyncChannel == null || writeTarget == null) {
        throw StateError('controller service found but channels are missing');
      }
      _writeTarget = writeTarget;

      // Buttons arrive on the asynchronous channel, the handshake reply on the
      // synchronous one: listening to both is the difference between a link
      // that works and a link that connects and says nothing.
      await asyncChannel.setNotifyValue(true);
      _frameSubscriptions.add(asyncChannel.onValueReceived.listen(_onFrame));
      if (syncReply != null) {
        await syncReply.setNotifyValue(true);
        _frameSubscriptions.add(syncReply.onValueReceived.listen(_onFrame));
      }
      _connectionSubscription = target.connectionState.listen((
        BluetoothConnectionState state,
      ) {
        if (state == BluetoothConnectionState.disconnected &&
            status != ControllerStatus.idle) {
          status = ControllerStatus.idle;
          _notify();
        }
      });

      // Ask for an encrypted session first; some firmware only answers the
      // plain handshake, which the supervision below sends after a delay.
      _keyPair = ControllerCrypto.generateKeyPair();
      _crypto = null;
      encrypted = false;
      _watchdog.onConnected();
      await writeTarget.write(
        ControllerHandshake.encryptedRequest(_keyPair!.publicKeyBytes),
      );

      _supervision?.cancel();
      _supervision = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _supervise(),
      );

      status = ControllerStatus.ready;
      _notify();
    } catch (e) {
      status = ControllerStatus.failed;
      error = e.toString();
      _notify();
    }
  }

  /// Feeds the watchdog and carries out what it asks for.
  void _supervise() {
    final ControllerLinkAction? action = _watchdog.onElapsed(
      const Duration(seconds: 1),
    );
    switch (action) {
      case null:
        return;
      case ControllerLinkAction.sendPlainHandshake:
        unawaited(_write(ControllerHandshake.plainRequest()));
      case ControllerLinkAction.needsUnlock:
        needsUnlock = true;
        _notify();
      case ControllerLinkAction.reconnect:
        unawaited(_reconnect());
    }
  }

  Future<void> _write(List<int> frame) async {
    try {
      await _writeTarget?.write(frame);
    } catch (e) {
      error = e.toString();
      _notify();
    }
  }

  Future<void> _reconnect() async {
    final BluetoothDevice? target = device;
    if (target == null || _reconnecting) {
      return;
    }
    _reconnecting = true;
    error = 'controller went silent, reconnecting';
    _notify();
    try {
      await _clearLink();
      await connect(target);
    } finally {
      _reconnecting = false;
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
        _watchdog.onFrame();
        final List<int>? deviceKey = ControllerHandshake.parseDevicePublicKey(
          frame,
        );
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

    _watchdog.onFrame();

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

  Future<void> _clearLink() async {
    _supervision?.cancel();
    _supervision = null;
    for (final StreamSubscription<List<int>> subscription
        in _frameSubscriptions) {
      await subscription.cancel();
    }
    _frameSubscriptions.clear();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _crypto = null;
    _keyPair = null;
    _writeTarget = null;
    encrypted = false;
  }

  /// Closes the connection and releases the subscriptions.
  Future<void> disconnect() async {
    await _clearLink();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await device?.disconnect();
    } catch (_) {
      // The device may already be gone; nothing to repair.
    }
    device = null;
    status = ControllerStatus.idle;
    batteryPercent = null;
    needsUnlock = false;
    _notify();
  }

  /// Releases every resource.
  Future<void> dispose() async {
    await disconnect();
    await _buttons.close();
  }
}
