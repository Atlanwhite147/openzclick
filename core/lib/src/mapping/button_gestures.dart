/// Turns raw button states of a two-button controller into higher level
/// actions, so that a handful of buttons can drive both the gears and the
/// direction choices offered at an intersection.
///
/// Mapping:
/// * single tap on the up button     -> [Action.shiftUp]
/// * single tap on the down button   -> [Action.shiftDown]
/// * double tap on the up button     -> [Action.steerLeft]
/// * double tap on the down button   -> [Action.steerRight]
///
/// A single tap is emitted after [doubleTapWindow] so that a second tap can
/// still turn it into a direction choice. Durations are injectable, which keeps
/// the detector testable without hardware.
library;

import 'dart:async';

import 'action.dart';
import '../protocol/controller_protocol.dart';

/// Converts button states into actions, with a double-tap gesture.
class ButtonGestureDetector {
  /// Creates a detector.
  ///
  /// [doubleTapWindow] is the maximum delay between two taps of the same button
  /// for them to be treated as a direction choice.
  ButtonGestureDetector({
    required this.onAction,
    this.doubleTapWindow = const Duration(milliseconds: 320),
  });

  /// Receives every action produced by the detector.
  final void Function(Action action) onAction;

  /// Maximum delay between two taps of the same button.
  final Duration doubleTapWindow;

  bool _upPressed = false;
  bool _downPressed = false;
  Timer? _upTimer;
  Timer? _downTimer;

  /// True when a single tap of the up button is pending confirmation.
  bool get pendingUp => _upTimer != null;

  /// True when a single tap of the down button is pending confirmation.
  bool get pendingDown => _downTimer != null;

  /// Feeds the latest button state.
  ///
  /// Press transitions start nothing by themselves: the action is decided when
  /// the button is released, so a held button never repeats.
  void feed(ClickButtons buttons) {
    if (buttons.up != _upPressed) {
      _upPressed = buttons.up;
      if (!buttons.up) _onReleased(up: true);
    }
    if (buttons.down != _downPressed) {
      _downPressed = buttons.down;
      if (!buttons.down) _onReleased(up: false);
    }
  }

  void _onReleased({required bool up}) {
    final Timer? pending = up ? _upTimer : _downTimer;
    if (pending != null) {
      // Second tap inside the window: it becomes a direction choice.
      pending.cancel();
      if (up) {
        _upTimer = null;
      } else {
        _downTimer = null;
      }
      onAction(up ? Action.steerLeft : Action.steerRight);
      return;
    }

    final Timer timer = Timer(doubleTapWindow, () {
      if (up) {
        _upTimer = null;
      } else {
        _downTimer = null;
      }
      onAction(up ? Action.shiftUp : Action.shiftDown);
    });

    if (up) {
      _upTimer = timer;
    } else {
      _downTimer = timer;
    }
  }

  /// Cancels pending timers.
  void dispose() {
    _upTimer?.cancel();
    _downTimer?.cancel();
    _upTimer = null;
    _downTimer = null;
  }
}
