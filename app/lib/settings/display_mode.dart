/// How much of the application the rider wants to see.
///
/// Two audiences, one build: a rider who wants to press a button and ride, and
/// one who wants to watch the link, the ladder and the bench. The old answer was
/// a tab bar where the settings outnumbered the ride, and it read as an
/// application to configure rather than one to use, so the choice is now explicit
/// and made once.
///
/// Simple is the default on a fresh install: assumption is the wrong thing to
/// make about a rider who has just downloaded the thing.
library;

/// The two presentations of the interface.
enum DisplayMode {
  /// One screen: pair, start, read the state, practical notes.
  simple,

  /// The full tab bar: gears, controllers, bridge, bench.
  advanced;

  /// Stored name, kept stable because it goes on disk.
  String get id => name;

  /// Reads a stored name, falling back to [DisplayMode.simple].
  static DisplayMode fromId(String? id) {
    for (final DisplayMode mode in DisplayMode.values) {
      if (mode.id == id) return mode;
    }
    return DisplayMode.simple;
  }
}
