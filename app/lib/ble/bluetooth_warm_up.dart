import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Builds the Bluetooth plugin's native side once, at start-up.
///
/// It has to happen here and not at the first Scan. Two reasons, both measured:
///
/// - the plugin initialises itself against whatever `FlutterBluePlusPlatform`
///   is registered the first time it is spoken to, and it does that once per
///   process; a test that can only replace the platform before that moment is a
///   test that cannot exercise the scan at all;
/// - on macOS the state a bundle without `NSBluetoothAlwaysUsageDescription`
///   dies from is the creation of the CoreBluetooth manager, so it is better to
///   have that beside the rest of the start-up than in the middle of a press.
///
/// Nothing is awaited beyond the adapter state, and a failure is swallowed: this
/// is a warm-up, not a feature, and a host with no radio must still open.
Future<void> warmUpBluetooth() async {
  try {
    await FlutterBluePlus.adapterState
        .firstWhere((BluetoothAdapterState s) => s != BluetoothAdapterState.unknown)
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    // A host without a radio, or a plugin without a platform: Scan will say it.
  }
}
