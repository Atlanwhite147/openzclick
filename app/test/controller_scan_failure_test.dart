import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';

import 'package:openzclick/ble/controller_connection.dart';

import 'fake_bluetooth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The plugin listens to the platform it found at its first call, for the whole
  // process: one fake, kept alive, whose radio changes from test to test. A
  // second instance would be installed and never heard.
  late FakeBluetoothPlatform platform;
  late BluetoothAdapterState before;

  setUpAll(() async {
    platform = FakeBluetoothPlatform();
    before = await FlutterBluePlus.adapterState.first;
  });

  tearDownAll(() async {
    platform.switchAdapter(_toFbp(before));
  });

  test('the plugin talks to this fake, or the tests below prove nothing', () {
    expect(identical(FlutterBluePlusPlatform.instance, platform), isTrue);
  });

  /// Puts the fake radio in [state], as the operating system would.
  void radio(BmAdapterStateEnum state) {
    platform
      ..startScanCalls = 0
      ..scanError = null
      ..stateChanges.clear();
    platform.switchAdapter(state);
  }

  test('a scan the platform refuses fails the link instead of the app', () async {
    // What macOS does when the bundle has no NSBluetoothAlwaysUsageDescription
    // is kill the process, and no Dart code can catch that. Every other refusal
    // (radio off, permission denied, a scan already running) arrives as an
    // exception, and it has to end in the screen's error line: the app closes
    // for nobody.
    radio(BmAdapterStateEnum.on);
    platform.scanError = FlutterBluePlusException(
      ErrorPlatform.fbp,
      'startScan',
      2,
      'bluetooth must be turned on. (unauthorized)',
    );
    final ControllerConnection link = ControllerConnection();
    addTearDown(link.dispose);

    await link.scan(timeout: const Duration(milliseconds: 50));

    expect(platform.startScanCalls, 1);
    expect(link.status, ControllerStatus.failed);
    expect(link.error, contains('Permission to use Bluetooth'));
    // Not left saying "Looking for controllers...": the button stays pressable.
    expect(link.status, isNot(ControllerStatus.scanning));
  });

  test('a radio that is off is reported before the scan is attempted', () async {
    // Refusing the scan here costs one call and turns a plugin exception into a
    // sentence. It also keeps the plugin from building its native manager at a
    // moment nobody chose.
    radio(BmAdapterStateEnum.off);
    final ControllerConnection link = ControllerConnection();
    addTearDown(link.dispose);

    await link.scan(timeout: const Duration(milliseconds: 50));

    expect(platform.startScanCalls, 0);
    expect(link.status, ControllerStatus.failed);
    expect(link.error, contains('Bluetooth is off'));
  });

  test('an adapter that is unavailable says so', () async {
    radio(BmAdapterStateEnum.unavailable);
    final ControllerConnection link = ControllerConnection();
    addTearDown(link.dispose);

    await link.scan(timeout: const Duration(milliseconds: 50));

    expect(platform.startScanCalls, 0);
    expect(link.status, ControllerStatus.failed);
    expect(link.error, contains('no Bluetooth'));
  });

  test(
    'a scan that ends normally goes back to idle, saying nothing was found',
    () async {
      radio(BmAdapterStateEnum.on);
      final ControllerConnection link = ControllerConnection();
      addTearDown(link.dispose);

      await link.scan(timeout: const Duration(milliseconds: 50));

      expect(platform.startScanCalls, 1);
      expect(link.status, ControllerStatus.idle);
      expect(link.error, isNull);
      expect(link.scanFoundNothing, isTrue);
    },
  );

  test('macOS ships a purpose string for Bluetooth in the bundle', () {
    // Without this key the system kills the process the instant CoreBluetooth
    // is touched, with no dialog and no log line: the rider presses Scan and
    // the window is gone. The build copies this file into the bundle, so the
    // file is what can be tested here.
    final File plist = File('macos/Runner/Info.plist');
    expect(
      plist.existsSync(),
      isTrue,
      reason: 'run from the app directory: the macOS bundle is built from here',
    );
    final String text = plist.readAsStringSync();
    expect(
      text,
      contains('<key>NSBluetoothAlwaysUsageDescription</key>'),
      reason: 'without it TCC terminates openzclick at the first scan on macOS',
    );
    // A key with an empty string is refused the same way by the system.
    final String? value = RegExp(
      r'<key>NSBluetoothAlwaysUsageDescription</key>\s*<string>([^<]*)</string>',
    ).firstMatch(text)?.group(1);
    expect(value, isNotNull, reason: 'the key has no string value');
    expect(value!.trim(), isNotEmpty, reason: 'the purpose string is empty');
  });

  test('both macOS entitlement files grant Bluetooth to a sandboxed build', () {
    // The sandbox is on in both configurations: without the Bluetooth
    // entitlement a sandboxed build reaches no peripheral at all, and the
    // difference between the debug and release files is what has shipped a
    // broken bundle before.
    for (final String name in <String>[
      'DebugProfile.entitlements',
      'Release.entitlements',
    ]) {
      final File file = File('macos/Runner/$name');
      expect(file.existsSync(), isTrue, reason: name);
      final String text = file.readAsStringSync();
      expect(
        text,
        contains('<key>com.apple.security.device.bluetooth</key>'),
        reason: '$name does not grant com.apple.security.device.bluetooth',
      );
    }
  });
}

/// The platform enum matching [state], for putting the fake back.
BmAdapterStateEnum _toFbp(BluetoothAdapterState state) => switch (state) {
  BluetoothAdapterState.unknown => BmAdapterStateEnum.unknown,
  BluetoothAdapterState.unavailable => BmAdapterStateEnum.unavailable,
  BluetoothAdapterState.unauthorized => BmAdapterStateEnum.unauthorized,
  BluetoothAdapterState.turningOn => BmAdapterStateEnum.turningOn,
  BluetoothAdapterState.on => BmAdapterStateEnum.on,
  BluetoothAdapterState.turningOff => BmAdapterStateEnum.turningOff,
  BluetoothAdapterState.off => BmAdapterStateEnum.off,
};
