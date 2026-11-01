/// Supervision of one controller link.
///
/// The controller family answers a host in three different ways depending on
/// its firmware and on whether the official application has unlocked it once:
///
/// 1. it answers the encrypted handshake and every following frame is a
///    ciphertext;
/// 2. it ignores the encrypted handshake and only accepts the plain `RideOn`
///    marker, sending button frames in the clear;
/// 3. it says nothing at all until it has been paired once in the official
///    application, which is what makes a Click disappear after a minute.
///
/// The last case cannot be distinguished from a dead radio by looking at the
/// bytes: both are silence. This class turns that silence into an explicit
/// action, so the interface can tell the rider what to do instead of showing a
/// connection that is technically alive and functionally useless.
///
/// Pure logic, no timer and no I/O: the caller feeds it elapsed time, which
/// keeps every rule testable without a radio.
library;

/// What the caller should do after a tick or a frame.
enum ControllerLinkAction {
  /// Send the plain `RideOn` marker: the controller never answered the
  /// encrypted handshake.
  sendPlainHandshake,

  /// Nothing arrived at all: the controller is probably locked and needs one
  /// pairing in the official application.
  needsUnlock,

  /// The link was carrying frames and went silent: reconnect.
  reconnect,
}

/// Supervises one link from the handshake to the next reconnection.
class ControllerLinkWatchdog {
  /// Creates a watchdog.
  ///
  /// [plainFallbackAfter] is how long the host waits for an answer to the
  /// encrypted handshake before falling back to the plain one.
  /// [unlockHintAfter] is how long a completely silent link is tolerated before
  /// blaming the controller lock.
  /// [silenceBeforeReconnect] is how long an established link may stay silent
  /// before it is considered broken.
  ControllerLinkWatchdog({
    this.plainFallbackAfter = const Duration(seconds: 3),
    this.unlockHintAfter = const Duration(seconds: 10),
    this.silenceBeforeReconnect = const Duration(seconds: 45),
  }) {
    if (plainFallbackAfter >= unlockHintAfter) {
      throw ArgumentError(
        'the plain fallback must come before the unlock hint',
      );
    }
  }

  /// Delay before falling back to the plain handshake.
  final Duration plainFallbackAfter;

  /// Delay before concluding that nothing will ever arrive.
  final Duration unlockHintAfter;

  /// Silence tolerated on an established link.
  final Duration silenceBeforeReconnect;

  Duration _sinceConnect = Duration.zero;
  Duration _sinceFrame = Duration.zero;
  bool _frameSeen = false;
  bool _plainSent = false;
  bool _unlockHinted = false;
  bool _reconnectAsked = false;

  /// True once any frame arrived since [onConnected].
  bool get frameSeen => _frameSeen;

  /// True once the plain handshake was requested.
  bool get plainSent => _plainSent;

  /// True once the link was declared locked.
  bool get unlockHinted => _unlockHinted;

  /// Resets the supervision for a new connection.
  void onConnected() {
    _sinceConnect = Duration.zero;
    _sinceFrame = Duration.zero;
    _frameSeen = false;
    _plainSent = false;
    _unlockHinted = false;
    _reconnectAsked = false;
  }

  /// Records traffic from the controller.
  ///
  /// Any frame counts, handshake acknowledgement included: it proves the
  /// controller is listening.
  void onFrame() {
    _frameSeen = true;
    _sinceFrame = Duration.zero;
    _reconnectAsked = false;
  }

  /// Advances the clocks by [elapsed] and returns what to do, if anything.
  ///
  /// Each action is returned once: asking for the plain handshake twice, or
  /// for the same reconnection in a loop, is the caller's bug to avoid.
  ControllerLinkAction? onElapsed(Duration elapsed) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must not be negative');
    }
    _sinceConnect += elapsed;
    _sinceFrame += elapsed;

    if (!_plainSent && !_frameSeen && _sinceConnect >= plainFallbackAfter) {
      _plainSent = true;
      return ControllerLinkAction.sendPlainHandshake;
    }
    if (!_frameSeen && !_unlockHinted && _sinceConnect >= unlockHintAfter) {
      _unlockHinted = true;
      return ControllerLinkAction.needsUnlock;
    }
    if (_frameSeen &&
        !_reconnectAsked &&
        _sinceFrame >= silenceBeforeReconnect) {
      _reconnectAsked = true;
      return ControllerLinkAction.reconnect;
    }
    return null;
  }
}
