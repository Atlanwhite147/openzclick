/// Turns raw button states of a controller into higher level actions, so that a
/// handful of buttons drives the gears, the direction choices offered at an
/// intersection, and whatever the rider configured for a long press.
///
/// ## Two modes, and why the fast one is the default
///
/// A double tap needs a window to be recognised, and the naive way to get one is
/// to delay **every** tap by that window. That costs a third of a second on each
/// gear change, which is exactly the gesture a rider repeats most.
///
/// [GestureMode.immediate] therefore acts on the press, and a second press inside
/// the window adds the double-tap action. The trade: a double tap also performs
/// its single action once, which for a direction choice at an intersection means
/// an unwanted gear change. [GestureMode.deferred] therefore stays the default:
/// the single action waits for the window so that a double tap produces only the
/// direction choice. The fast mode is offered for a setup where no double tap is
/// bound.
///
/// ## Long press
///
/// A button held past [longPressAfter] produces its long-press action once, and
/// nothing else: the tap that would have followed a release is suppressed. The
/// default is [Action.none], so an unconfigured detector behaves as it did.
library;

import 'dart:async';

import '../protocol/controller_protocol.dart';
import 'action.dart';

/// When the single-tap action of a button is produced.
enum GestureMode {
  /// Act on the press. A second press inside the window adds the double action.
  immediate,

  /// Wait for the window, then act. A second press replaces the single action.
  deferred,
}

/// What one button does, for each gesture it supports.
class GestureBindings {
  /// Builds a binding set.
  const GestureBindings({
    required this.tap,
    required this.doubleTap,
    this.longPress = Action.none,
  });

  /// Action produced by a single press.
  final Action tap;

  /// Action produced when a second press lands inside the window.
  final Action doubleTap;

  /// Action produced when the button is held past the long-press delay.
  final Action longPress;

  /// A copy with another long-press action.
  GestureBindings withLongPress(Action action) => GestureBindings(
        tap: tap,
        doubleTap: doubleTap,
        longPress: action,
      );
}

/// Default bindings: gears on a tap, directions on a double tap.
const GestureBindings defaultUpBindings = GestureBindings(
  tap: Action.shiftUp,
  doubleTap: Action.steerLeft,
);

/// Default bindings for the second button.
const GestureBindings defaultDownBindings = GestureBindings(
  tap: Action.shiftDown,
  doubleTap: Action.steerRight,
);

/// Converts button states into actions, with double tap and long press.
class ButtonGestureDetector {
  /// Creates a detector.
  ///
  /// [doubleTapWindow] is the maximum delay between two presses of the same
  /// button for the second one to be a double tap. [longPressAfter] is how long a
  /// button must stay down to produce its long-press action. Durations are
  /// injectable, which keeps the detector testable without hardware.
  ButtonGestureDetector({
    required this.onAction,
    this.doubleTapWindow = const Duration(milliseconds: 320),
    this.longPressAfter = const Duration(milliseconds: 650),
    this.mode = GestureMode.deferred,
    this.up = defaultUpBindings,
    this.down = defaultDownBindings,
  }) {
    if (longPressAfter <= doubleTapWindow) {
      throw ArgumentError(
        'a long press must last longer than the double-tap window',
      );
    }
  }

  /// Receives every action produced by the detector.
  final void Function(Action action) onAction;

  /// Maximum delay between two presses of the same button.
  final Duration doubleTapWindow;

  /// Delay after which a held button produces its long-press action.
  final Duration longPressAfter;

  /// When the single-tap action is produced.
  final GestureMode mode;

  /// What the first button does.
  final GestureBindings up;

  /// What the second button does.
  final GestureBindings down;

  final _ButtonState _upState = _ButtonState();
  final _ButtonState _downState = _ButtonState();

  /// True when a single tap of the up button is waiting for its window.
  bool get pendingUp => _upState.pending;

  /// True when a single tap of the down button is waiting for its window.
  bool get pendingDown => _downState.pending;

  /// Feeds the latest button state.
  void feed(ClickButtonMask buttons) {
    _apply(buttons.up, _upState, up);
    _apply(buttons.down, _downState, down);
  }

  void _apply(bool pressed, _ButtonState state, GestureBindings bindings) {
    if (pressed == state.pressed) return;
    state.pressed = pressed;
    if (pressed) {
      _onPressed(state, bindings);
    } else {
      _onReleased(state);
    }
  }

  void _onPressed(_ButtonState state, GestureBindings bindings) {
    final DateTime now = DateTime.now();
    final bool second = state.lastPressAt != null &&
        now.difference(state.lastPressAt!) <= doubleTapWindow;

    state.longTimer?.cancel();
    if (bindings.longPress != Action.none) {
      state.longTimer = Timer(longPressAfter, () {
        state.longTimer = null;
        state.longFired = true;
        // A hold replaces the tap: drop the pending decision instead of letting
        // it fire at the end of its own delay.
        state.pendingTimer?.cancel();
        state.pendingTimer = null;
        state.pending = false;
        state.lastPressAt = null;
        _emit(bindings.longPress);
      });
    }

    if (second) {
      // The second press is the gesture, whatever the first one did.
      state.pendingTimer?.cancel();
      state.pendingTimer = null;
      state.pending = false;
      state.lastPressAt = null;
      _emit(bindings.doubleTap);
      return;
    }

    state.lastPressAt = now;
    if (mode == GestureMode.immediate) {
      _emit(bindings.tap);
      return;
    }
    // Deferred: wait, so that a second press — or a hold — can replace this
    // action. A button that owns a long press must wait for that delay, not for
    // the double-tap window, or the tap would leave before the hold is known.
    final Duration delay =
        bindings.longPress == Action.none ? doubleTapWindow : longPressAfter;
    state.pending = true;
    state.pendingTimer = Timer(delay, () {
      state.pendingTimer = null;
      state.pending = false;
      state.lastPressAt = null;
      _emit(bindings.tap);
    });
  }

  void _onReleased(_ButtonState state) {
    state.longTimer?.cancel();
    state.longTimer = null;
    if (state.longFired) {
      // The hold already spoke for this press: no tap follows.
      state.longFired = false;
      state.lastPressAt = null;
      state.pendingTimer?.cancel();
      state.pendingTimer = null;
      state.pending = false;
    }
  }

  void _emit(Action action) {
    if (action == Action.none) return;
    onAction(action);
  }

  /// Cancels pending timers.
  void dispose() {
    _upState.dispose();
    _downState.dispose();
  }
}

/// Everything one button remembers between two frames.
class _ButtonState {
  bool pressed = false;
  bool pending = false;
  bool longFired = false;
  DateTime? lastPressAt;
  Timer? pendingTimer;
  Timer? longTimer;

  void dispose() {
    pendingTimer?.cancel();
    longTimer?.cancel();
    pendingTimer = null;
    longTimer = null;
    pending = false;
    longFired = false;
  }
}
