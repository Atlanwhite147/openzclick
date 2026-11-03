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

  /// True when this host synthesises the resistance itself instead of passing
  /// button presses to an application that does its own virtual shifting.
  ///
  /// Two different routes reach the same trainer. In the first, MyWhoosh keeps
  /// its own gear model and applies the resistance, so the bridge only reports
  /// buttons and nothing about the bike matters to it. In the second, the bridge
  /// presents itself as the trainer and must translate a gear into a wheel size,
  /// which is what makes the parked gear load-bearing.
  ///
  /// That second route exists in `transports/` but is not wired to any screen
  /// yet, so nothing here drives the trainer. Keeping the answer in one place
  /// means the readiness verdict cannot silently disagree with it: until this
  /// returns true, asking a rider where the chain sits must not block them.
  static bool get drivesTrainerItself => false;

  /// True when Bluetooth pairing goes through the browser's device chooser
  /// rather than a list the application scans and filters itself.
  static bool get usesBluetoothChooser => isWeb;

  /// True when this page could use Web Bluetooth at all.
  ///
  /// The API only exists in a secure context: `https`, or `localhost`. A page
  /// served over plain `http` on a LAN address — which is exactly what a bridge
  /// serves so its console can reach it without mixed content — has no
  /// `navigator.bluetooth` at all. Saying so before the rider taps the button
  /// costs nothing and prevents the one reading nobody wants, "the application
  /// is broken".
  static bool get webBluetoothPossible {
    if (!isWeb) return true;
    final Uri base = Uri.base;
    if (base.scheme == 'https') return true;
    return base.host == 'localhost' || base.host == '127.0.0.1';
  }

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
