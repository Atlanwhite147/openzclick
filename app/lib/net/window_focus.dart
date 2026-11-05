/// Bringing the training application forward before a key is injected.
///
/// A synthetic keystroke goes to whatever window owns the focus, and the window
/// that owns the focus is usually *not* the training application: the rider had
/// to look at this one to press a button, or another window stole it. The result
/// is a key that was inserted, reported as sent, and received by a chat window.
///
/// `zwiftboard` (MIT) solves this with a per-profile window name, brought to the
/// front before every keypress, and this is the same idea, kept small: a
/// case-insensitive substring of the window title, matched against every
/// top-level window, and the first match is restored and activated. When nothing
/// matches, the key is **not** sent — typing into an unrelated application is
/// worse than a shift that does not happen.
///
/// The matching rule is pure so it can be tested without Windows; the window
/// enumeration is behind [WindowFocuser] and only the Windows backend implements
/// it.
library;

/// A backend that can bring a window to the front.
abstract interface class WindowFocuser {
  /// Brings the first visible top-level window whose title contains [match] to
  /// the foreground, restoring it if it was minimised.
  ///
  /// Returns false when no window matches, or when Windows refuses the
  /// activation.
  Future<bool> focusWindow(String match);
}

/// True when [title] is the window a rider named in [match].
///
/// Case-insensitive and substring-based: a rider types `MyWhoosh` and the window
/// is called `MyWhooshHD` or `MyWhoosh - Free ride`. An empty match means "no
/// target", which never matches: a blank setting must not pull a random window
/// forward.
bool windowTitleMatches(String title, String match) {
  final String wanted = match.trim().toLowerCase();
  if (wanted.isEmpty) return false;
  return title.toLowerCase().contains(wanted);
}
