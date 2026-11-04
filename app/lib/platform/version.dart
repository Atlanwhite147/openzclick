/// Version of the application, for the reports riders paste into an issue.
///
/// Kept as a constant rather than read from the platform: `package_info_plus`
/// would add a plugin to every host for one string that only a bug report reads.
/// The cost is that it can drift from `pubspec.yaml`, so a test reads the
/// pubspec and fails when the two disagree — a report stamped with the wrong
/// version sends a maintainer looking at the wrong commit.
library;

/// Version of this build, matching `version:` in `app/pubspec.yaml`.
const String appVersion = '0.3.0+3';
