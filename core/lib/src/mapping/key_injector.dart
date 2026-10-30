/// Input injection port towards the target app.
///
/// The core cannot inject: it only describes here the contract that
/// implementations comply with (local transport, remote proxy, test bench). No
/// method of this interface performs I/O inside the `core` package.
library;

/// Input injection interface (taps and keys).
///
/// Implementations must be idempotent on cancellation and never block the
/// caller: each method returns a [Future] that completes once the injection is
/// effectively taken into account.
abstract interface class KeyInjector {
  /// Injects a single tap at screen coordinates ([x], [y]) expressed in the
  /// target app's coordinate system.
  Future<void> tapAt(double x, double y);

  /// Sends a key press then a release for the key named [key].
  ///
  /// The key name is the one used by the target app's system; the
  /// action -> key translation belongs to the implementation, not to the core.
  Future<void> pressKey(String key);
}
