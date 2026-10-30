import 'dart:io' show Platform;

import 'package:openzclick_core/openzclick_core.dart';
import 'package:flutter/services.dart';

/// Injects taps through the Android accessibility service.
///
/// Coordinates are relative (0 to 1) so that the same configuration works on
/// any screen size. Key presses are not available on this platform: Android
/// exposes no authorised way to synthesise key events outside an input method.
class AndroidInjection implements KeyInjector {
  static const MethodChannel _channel = MethodChannel('openzclick/injection');

  /// True when the platform can inject taps.
  static bool get supported => Platform.isAndroid;

  /// True when the user has enabled the accessibility service.
  static Future<bool> isReady() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('ready') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system accessibility settings, where the service is enabled.
  static Future<void> openSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('settings');
    } catch (_) {}
  }

  @override
  Future<void> tapAt(double x, double y) async {
    if (!supported) {
      throw UnsupportedError('tap injection is only available on Android');
    }
    final bool? accepted = await _channel.invokeMethod<bool>(
      'tap',
      <String, double>{'x': x, 'y': y},
    );
    if (accepted != true) {
      throw StateError('the accessibility service refused the tap');
    }
  }

  @override
  Future<void> pressKey(String key) async {
    throw UnsupportedError('key injection is not available on Android');
  }
}
