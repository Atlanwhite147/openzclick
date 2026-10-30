import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Android drops multicast traffic unless the application holds a multicast
/// lock. The lock lives in the Android host and is requested through a small
/// channel; every other platform is a no-op, so the shared code stays identical.
class AndroidMulticast {
  static const MethodChannel _channel = MethodChannel('openzclick/multicast');

  /// True when a lock must be acquired.
  static bool get supported => Platform.isAndroid;

  /// Acquires the multicast lock, ignoring hosts that do not implement it.
  static Future<void> acquire() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('acquire');
    } catch (_) {
      // Older hosts simply keep receiving what Android lets through.
    }
  }

  /// Releases the multicast lock.
  static Future<void> release() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('release');
    } catch (_) {}
  }
}
