/// What the host running the application can actually do.
///
/// A native host gets `dart:io`: sockets, multicast, synthetic input. A browser
/// is a sandbox: no listening socket, no mDNS announcement, no synthetic input,
/// and Bluetooth only through a device chooser. The interface asks these flags
/// instead of `Platform` directly, which is what lets the same widgets compile
/// and run in a browser, and why a greyed out switch can say why.
library;

import 'package:flutter/foundation.dart';

import '../net/sockets/sockets.dart';

/// Capabilities of the current host.
abstract final class Capabilities {
  /// True in a browser, where only Web Bluetooth and local storage exist.
  static bool get isWeb => kIsWeb;

  /// True on Android.
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True on iOS.
  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// True on Linux.
  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  /// True when the host can announce a service over mDNS.
  ///
  /// iOS needs an entitlement Apple grants by hand; a browser has no multicast
  /// at all.
  static bool get canAnnounce => !isWeb && !isIOS;

  /// True when the host can listen on a TCP port and be reached by a training
  /// application.
  ///
  /// Every native host can. A browser can only when the page is an Isolated Web
  /// App, because that is the one context where Chrome grants a TCP server; any
  /// other page is limited to dialling a bridge.
  static bool get canPublish => !isWeb || directSocketsAvailable;

  /// True when the host can synthesise input for another application.
  static bool get canInject => isAndroid || isLinux;

  /// True when Bluetooth pairing goes through the browser's device chooser
  /// rather than a list the application scans and filters itself.
  static bool get usesBluetoothChooser => isWeb;

  /// Short name of the host, for diagnostics.
  static String get hostName => isWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          TargetPlatform.linux => 'linux',
          TargetPlatform.macOS => 'macos',
          TargetPlatform.windows => 'windows',
          TargetPlatform.fuchsia => 'fuchsia',
        };
}
