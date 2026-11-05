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
///    application.
///
/// The last case cannot be distinguished from a dead radio by looking at the
/// bytes: both are silence. This class turns that silence into an explicit
/// action, so the interface can tell the rider what to do instead of showing a
/// connection that is technically alive and functionally useless.
///
/// ## Silence is not a fault, a failed write is
///
/// An earlier version reconnected after 45 seconds without a button frame. That
/// is wrong on both counts: coasting for a minute is normal riding, and a pod
/// keeps its session alive from the host side, not from its buttons. The
/// measurement behind this comes from `zwiftboard` (MIT), which found that a
/// controller drops about 65 seconds after the last write, and that a `RideOn`
/// written every three seconds is what holds it. So the watchdog now asks for a
/// keepalive on a cadence, and never for a reconnection: the caller reconnects
/// when a write actually fails, which is the only observable sign that the
/// session ended.
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

  /// Write the plain `RideOn` again to hold the session open. A failure of that
  /// write, and not a silence, is the signal to reconnect.
  sendKeepalive,
}

/// Supervises one link from the handshake to the next reconnection.
class ControllerLinkWatchdog {
  /// Creates a watchdog.
  ///
  /// [plainFallbackAfter] is how long the host waits for an answer to the
  /// encrypted handshake before falling back to the plain one.
  /// [unlockHintAfter] is how long a completely silent link is tolerated before
  /// blaming the controller lock.
  /// [keepaliveInterval] is the cadence of the plain `RideOn` that holds the
  /// session open. Three seconds is what `zwiftboard` measured on a Click v2;
  /// the pod drops roughly a minute after the last write it received.
  ControllerLinkWatchdog({
    this.plainFallbackAfter = const Duration(seconds: 3),
    this.unlockHintAfter = const Duration(seconds: 10),
    this.keepaliveInterval = const Duration(seconds: 3),
  }) {
    if (plainFallbackAfter >= unlockHintAfter) {
      throw ArgumentError(
        'the plain fallback must come before the unlock hint',
      );
    }
    if (keepaliveInterval <= Duration.zero) {
      throw ArgumentError.value(
        keepaliveInterval,
        'keepaliveInterval',
        'must be positive',
      );
    }
  }

  /// Delay before falling back to the plain handshake.
  final Duration plainFallbackAfter;

  /// Delay before concluding that nothing will ever arrive.
  final Duration unlockHintAfter;

  /// Cadence of the keepalive once a plain session is open.
  final Duration keepaliveInterval;

  Duration _sinceConnect = Duration.zero;
  Duration _sinceKeepalive = Duration.zero;
  bool _frameSeen = false;
  bool _plainSent = false;
  bool _unlockHinted = false;

  /// True once any frame arrived since [onConnected].
  bool get frameSeen => _frameSeen;

  /// True once the plain handshake was requested.
  bool get plainSent => _plainSent;

  /// True once the link was declared locked.
  bool get unlockHinted => _unlockHinted;

  /// Resets the supervision for a new connection.
  void onConnected() {
    _sinceConnect = Duration.zero;
    _sinceKeepalive = Duration.zero;
    _frameSeen = false;
    _plainSent = false;
    _unlockHinted = false;
  }

  /// Records traffic from the controller.
  ///
  /// Any frame counts, handshake acknowledgement included: it proves the
  /// controller is listening, and a link that just spoke needs no keepalive.
  void onFrame() {
    _frameSeen = true;
    _sinceKeepalive = Duration.zero;
  }

  /// Records that the caller wrote the plain handshake, so that the keepalive
  /// cadence starts even when nothing ever answers.
  void onPlainHandshakeSent() {
    _plainSent = true;
    _sinceKeepalive = Duration.zero;
  }

  /// Advances the clocks by [elapsed] and returns what to do, if anything.
  ///
  /// Each action is returned once per cadence: asking for the plain handshake
  /// twice is the caller's bug to avoid, while the keepalive is meant to repeat.
  ControllerLinkAction? onElapsed(Duration elapsed) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must not be negative');
    }
    _sinceConnect += elapsed;
    _sinceKeepalive += elapsed;

    if (!_plainSent && !_frameSeen && _sinceConnect >= plainFallbackAfter) {
      _plainSent = true;
      _sinceKeepalive = Duration.zero;
      return ControllerLinkAction.sendPlainHandshake;
    }
    if (!_frameSeen && !_unlockHinted && _sinceConnect >= unlockHintAfter) {
      _unlockHinted = true;
      return ControllerLinkAction.needsUnlock;
    }
    // Only once a plain session has been opened: before that, the encrypted
    // handshake owns the link and a stray `RideOn` would be noise.
    if (_plainSent && _sinceKeepalive >= keepaliveInterval) {
      _sinceKeepalive = Duration.zero;
      return ControllerLinkAction.sendKeepalive;
    }
    return null;
  }
}
