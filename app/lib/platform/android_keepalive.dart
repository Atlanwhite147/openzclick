import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Holds the process in a state Android does not suspend.
///
/// Riding means openzclick in the background and the training application in
/// front, and Android freezes a background application: the Bluetooth link and
/// the socket both stop with it. A foreground service is the only state that
/// survives that, so the link asks for one as soon as it exists.
///
/// Every other platform is a no-op — a desktop application is not suspended for
/// losing the focus, and iOS has its own rules.
class AndroidKeepAlive {
  static const MethodChannel _channel = MethodChannel('openzclick/keepalive');

  /// True when the host needs a foreground service.
  static bool get supported => Platform.isAndroid;

  /// Asks the host to hold the process. Repeated calls are harmless.
  static Future<void> start() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('start');
    } catch (_) {
      // A host without the service keeps the link for as long as it stays in
      // front: worse, but not a reason to refuse to connect.
    }
  }

  /// Lets the host suspend the process again.
  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }
}
