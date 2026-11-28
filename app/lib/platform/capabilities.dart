/// What the host running the application can actually do.
///
/// The interface asks these flags instead of `Platform` directly, which is why a
/// greyed out switch can say why.
library;

import 'package:flutter/foundation.dart';

/// Capabilities of the current host.
abstract final class Capabilities {
  /// True on Android.
  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// True on iOS.
  static bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// True on Linux.
  static bool get isLinux => defaultTargetPlatform == TargetPlatform.linux;

  /// True when the host can announce a service over mDNS.
  ///
  /// iOS needs an entitlement Apple grants by hand.
  static bool get canAnnounce => !isIOS;

  /// True when the host can listen on a TCP port and be reached by a training
  /// application.
  static bool get canPublish => true;

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

  /// Short name of the host, for diagnostics.
  static String get hostName => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.linux => 'linux',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}
