import 'dart:async';

import 'package:openzclick_core/openzclick_core.dart';
import 'package:openzclick_transports/openzclick_transports.dart';

/// Injector used on platforms without a tap implementation.
class UnsupportedInjector implements KeyInjector {
  @override
  Future<void> pressKey(String key) async {
    throw UnsupportedError('key injection is not available on this platform');
  }

  @override
  Future<void> tapAt(double x, double y) async {
    throw UnsupportedError('tap injection is not available on this platform');
  }
}


/// Sends actions to the target application by tapping its own controls.
///
/// Used when the application does not speak the network protocol: the bridge
/// drives the on-screen gear buttons instead. Positions are stored as relative
/// coordinates, so a single configuration survives a change of screen.
class InjectionPublisher {
  /// Creates a publisher.
  InjectionPublisher({required this.injector});

  /// Injector supplied by the platform.
  final KeyInjector injector;

  /// True when the platform provides a working injector.
  bool get supported => injector is! UnsupportedInjector;

  /// Default positions, roughly the lower right corner of a riding screen.
  static const Map<Action, List<double>> defaultPositions =
      <Action, List<double>>{
    Action.shiftUp: <double>[0.90, 0.62],
    Action.shiftDown: <double>[0.90, 0.78],
    Action.steerLeft: <double>[0.62, 0.34],
    Action.steerRight: <double>[0.72, 0.34],
  };

  /// Relative position of every action, mutable from the settings screen.
  final Map<Action, List<double>> positions =
      <Action, List<double>>{
    for (final MapEntry<Action, List<double>> entry in defaultPositions.entries)
      entry.key: List<double>.of(entry.value),
  };

  LocalInjectionTransport? _transport;

  /// True when taps are being injected.
  bool running = false;

  /// Last error, null when the last injection succeeded.
  String? error;

  /// Called whenever [running] or [error] changes.
  void Function()? onChanged;

  void _notify() => onChanged?.call();

  /// Sets the position of [action], in relative coordinates.
  bool _dirty = false;

  void setPosition(Action action, double x, double y) {
    positions[action] = <double>[x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)];
    // The target table is copied when the transport is built, so the next
    // injection rebuilds it.
    _dirty = true;
    _notify();
  }

  /// Rebuilds the transport so that the current positions apply.
  Future<void> _applyPositions() async {
    if (!_dirty) return;
    final bool wasRunning = running;
    await _transport?.stop();
    _transport = null;
    running = false;
    _dirty = false;
    if (wasRunning) {
      await start();
    }
  }

  /// Starts injecting taps.
  Future<void> start() async {
    error = null;
    _dirty = false;
    try {
      final LocalInjectionTransport transport = LocalInjectionTransport(
        injector: injector,
        targets: <Action, InjectionTarget>{
          for (final MapEntry<Action, List<double>> entry in positions.entries)
            entry.key: PointTarget(entry.value[0], entry.value[1]),
        },
      );
      await transport.start();
      _transport = transport;
      running = true;
    } catch (e) {
      error = e.toString();
      running = false;
    }
    _notify();
  }

  /// Stops injecting.
  Future<void> stop() async {
    await _transport?.stop();
    _transport = null;
    running = false;
    _notify();
  }

  /// Injects [action], and records the outcome.
  Future<void> publish(Action action) async {
    if (!running) return;
    await _applyPositions();
    final LocalInjectionTransport? transport = _transport;
    if (transport == null) return;
    try {
      await transport.emit(action);
      error = null;
    } catch (e) {
      error = e.toString();
    }
    _notify();
  }

  /// Sends a single tap at the position configured for [action].
  Future<void> test(Action action) => publish(action);
}
