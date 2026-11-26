import 'dart:async';

import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';

/// A Bluetooth stack that does exactly what a test tells it to.
///
/// The scan path of [ControllerConnection] talks to the plugin only through
/// `FlutterBluePlusPlatform`, so replacing that one object is enough to make a
/// refused scan, an adapter that is off or a radio that answers nothing happen
/// on a host with no radio at all.
/// The plugin reads the platform once per process, at its first call: a test
/// that wants a fake must install it before anything touches FlutterBluePlus,
/// which is what `warmUpBluetooth` does in `main()`. This constructor is that
/// call.
final class FakeBluetoothPlatform extends FlutterBluePlusPlatform {
  /// Creates the fake, [adapter] being the state the radio reports.
  FakeBluetoothPlatform({this.adapter = BmAdapterStateEnum.on}) {
    FlutterBluePlusPlatform.instance = this;
  }

  /// What getAdapterState answers.
  BmAdapterStateEnum adapter;

  /// What startScan does: return normally, or throw [scanError].
  Object? scanError;

  /// Adapter states pushed on the change stream while a scan runs, which is how
  /// a radio switched off mid-scan reaches Dart.
  final List<BmAdapterStateEnum> stateChanges = <BmAdapterStateEnum>[];

  /// How many scans were asked for, so a test can tell "never started" from
  /// "started and failed".
  int startScanCalls = 0;

  final StreamController<BmBluetoothAdapterState> _states =
      StreamController<BmBluetoothAdapterState>.broadcast();
  final StreamController<BmScanResponse> _scanResponses =
      StreamController<BmScanResponse>.broadcast();

  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged => _states.stream;

  @override
  Stream<BmScanResponse> get onScanResponse => _scanResponses.stream;

  @override
  Future<BmBluetoothAdapterState> getAdapterState(
    BmBluetoothAdapterStateRequest request,
  ) async => BmBluetoothAdapterState(adapterState: adapter);

  @override
  Future<bool> startScan(BmScanSettings request) async {
    startScanCalls++;
    // The real plugin answers the scan request after its native side reacted,
    // so a state pushed during the scan must be able to land before the answer.
    for (final BmAdapterStateEnum state in stateChanges) {
      _states.add(BmBluetoothAdapterState(adapterState: state));
    }
    await Future<void>.delayed(Duration.zero);
    final Object? failure = scanError;
    if (failure != null) throw failure;
    return true;
  }

  @override
  Future<bool> stopScan(BmStopScanRequest request) async => true;

  /// Pushes [response] as what the radio reported, for a test that plays the
  /// platform side of an asynchronous failure.
  void push(BmScanResponse response) => _scanResponses.add(response);

  /// Switches the radio, as the operating system would.
  void switchAdapter(BmAdapterStateEnum state) {
    adapter = state;
    _states.add(BmBluetoothAdapterState(adapterState: state));
  }

  Future<void> close() async {
    await _states.close();
    await _scanResponses.close();
  }
}
