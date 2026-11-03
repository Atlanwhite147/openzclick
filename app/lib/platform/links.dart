/// Web addresses the interface shows to a rider.
///
/// They live outside the widgets so a screen can name one without importing
/// another screen, and so a test can assert on the address a novice is expected
/// to reach without depending on the layout that shows it.
library;

/// Where a rider downloads the native application.
///
/// The start screen told a novice to "install openzclick" without saying that a
/// downloadable file existed, let alone where. Anyone who had not read the
/// README stopped on that line, which is the first place the journey broke.
const String downloadsUrl =
    'https://github.com/Atlanwhite147/openzclick/releases/latest';
