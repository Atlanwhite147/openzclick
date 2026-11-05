import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:openzclick_core/openzclick_core.dart';

import 'injection_backend.dart';
import 'window_focus.dart';

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
  ///
  /// [readiness] is asked before starting: some platforms need a permission or
  /// a service that the user enables once.
  ///
  /// [keys] switches the publisher from taps to key presses: each action is
  /// then translated into the key listed here, which is how desktop hosts
  /// drive an application that listens to shortcuts.
  InjectionPublisher({
    required this.injector,
    this.readiness,
    this.availability,
    this.focuser,
    Map<Action, String>? keys,
    this.shiftsPerPress = 1,
  }) : _keys = keys == null ? null : Map<Action, String>.of(keys);

  /// Default desktop bindings, matching the shortcuts of common training
  /// applications.
  static const Map<Action, String> defaultKeys = <Action, String>{
    Action.shiftUp: 'k',
    Action.shiftDown: 'i',
    Action.steerLeft: 'Left',
    Action.steerRight: 'Right',
  };

  Map<Action, String>? _keys;

  /// Key bound to each action, null when the publisher injects taps.
  ///
  /// The direction is not obvious and the public sources contradict each
  /// other: in MyWhoosh, `k` shifts to a harder gear and `i` to an easier one,
  /// which two independent implementations agree on. The per-application tables
  /// live in `key_profiles.dart`, with the page each one was read from.
  Map<Action, String>? get keys => _keys;

  /// Replaces the table, rebuilding the backend on the next injection.
  set keys(Map<Action, String>? value) {
    if (value == null && _keys == null) return;
    if (value != null && _keys != null && _sameKeys(value, _keys!)) return;
    _keys = value == null ? null : Map<Action, String>.of(value);
    _dirty = true;
    _notify();
  }

  /// Keys sent per button press, 1 to 3.
  ///
  /// Some applications have no gear ratio, only a ladder: a rider who wants to
  /// cross three gears at once should not have to press three times.
  int shiftsPerPress;

  static bool _sameKeys(Map<Action, String> a, Map<Action, String> b) {
    if (a.length != b.length) return false;
    for (final MapEntry<Action, String> entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Optional check performed before the first injection.
  final Future<bool> Function()? readiness;

  /// Optional backend that brings the training application to the front before
  /// a key is injected, `null` where the platform cannot do it.
  final WindowFocuser? focuser;

  /// Title fragment of the window that must own the focus when a key goes out.
  ///
  /// Empty, the key goes to whatever window owns the focus, which is the plain
  /// keyboard behaviour. Set, the publisher brings that window forward first and
  /// refuses to type into anything else.
  String focusWindow = '';

  /// Optional synchronous test of the platform capability, used by the user
  /// interface to disable the switch instead of failing later.
  final bool Function()? availability;

  /// Injector supplied by the platform.
  final KeyInjector injector;

  /// True when the platform provides a working injector.
  bool get supported =>
      injector is! UnsupportedInjector && (availability?.call() ?? true);

  /// True when actions are sent as key presses rather than taps.
  bool get usesKeys => _keys != null;

  /// Default positions, roughly the lower right corner of a riding screen.
  static const Map<Action, List<double>> defaultPositions =
      <Action, List<double>>{
        Action.shiftUp: <double>[0.90, 0.62],
        Action.shiftDown: <double>[0.90, 0.78],
        Action.steerLeft: <double>[0.62, 0.34],
        Action.steerRight: <double>[0.72, 0.34],
      };

  /// Relative position of every action, mutable from the settings screen.
  final Map<Action, List<double>> positions = <Action, List<double>>{
    for (final MapEntry<Action, List<double>> entry in defaultPositions.entries)
      entry.key: List<double>.of(entry.value),
  };

  InjectionBackend? _backend;

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
    await _backend?.stop();
    _backend = null;
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
    final Future<bool> Function()? check = readiness;
    if (check != null && !await check()) {
      error = 'the injection service is not enabled yet';
      running = false;
      _notify();
      return;
    }
    try {
      final InjectionBackend? backend = createInjectionBackend(
        injector: injector,
        keys: _keys,
        positions: positions,
      );
      if (backend == null) {
        // A browser has no way to tap or type into another application: say it
        // here instead of pretending the switch did something.
        error = 'this host cannot inject input: no synthetic input API';
        running = false;
        _notify();
        return;
      }
      await backend.start();
      _backend = backend;
      running = true;
    } catch (e) {
      error = e.toString();
      running = false;
    }
    _notify();
  }

  /// Stops injecting.
  Future<void> stop() async {
    await _backend?.stop();
    _backend = null;
    running = false;
    _notify();
  }

  /// Injects [action], and records the outcome.
  Future<void> publish(Action action) async {
    if (!running) return;
    await _applyPositions();
    final InjectionBackend? backend = _backend;
    if (backend == null) return;
    final String? refused = await _focusTarget();
    if (refused != null) {
      error = refused;
      _notify();
      return;
    }
    try {
      for (int i = 0; i < shiftsPerPress; i++) {
        await backend.emit(action);
        // Two presses in one buffer are one press for an application that polls
        // the key state: leave a gap, like a human would.
        if (i + 1 < shiftsPerPress) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
      }
      error = null;
    } catch (e) {
      error = e.toString();
      debugPrint('openzclick: injection of ${action.name} failed: $e');
    }
    _notify();
  }

  /// Brings the configured window to the front, and says why it could not.
  ///
  /// A key inserted while another window owns the focus is a key nobody asked
  /// for: it lands in a chat window and the rider sees a shift that did nothing.
  /// So when a target is configured and the platform can act on it, the window
  /// is raised first, and a refusal is reported instead of typing blind.
  Future<String?> _focusTarget() async {
    final WindowFocuser? target = focuser;
    final String name = focusWindow.trim();
    if (target == null || name.isEmpty) return null;
    final bool focused = await target.focusWindow(name);
    if (focused) return null;
    return 'no window matching "$name": the key was not sent';
  }

  /// Sends a single tap at the position configured for [action].
  Future<void> test(Action action) => publish(action);
}
