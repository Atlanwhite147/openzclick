/// The one button that turns a bad ride into a fixed bug.
///
/// A rider who hits a problem will not create an account, find a form and
/// describe an environment they cannot see. GitHub accepts the whole report in
/// the URL of its "new issue" page, so the press opens the browser already
/// filled in: no server, no form, no telemetry, which is what the README
/// promises and what this file must keep true.
///
/// The body is the device report, scrubbed by [DeviceReport.anonymized] first.
library;

import '../ble/device_report.dart';

/// Builds the issue URL from a report.
abstract final class BugReport {
  /// Repository that receives the reports.
  static const String issuesUrl =
      'https://github.com/Atlanwhite147/openzclick/issues/new';

  /// Label applied to every report, so they are found without a search.
  static const String label = 'bug';

  /// Longest title GitHub accepts before the form truncates it.
  static const int titleLimit = 120;

  /// URL that opens a new issue with [report] already in it.
  ///
  /// [summary] is the one line the rider typed, empty when the button is
  /// pressed without a description: the title then states the platform, so the
  /// issue is still searchable.
  static Uri issueUrl({required DeviceReport report, String summary = ''}) {
    final DeviceReport safe = report.anonymized();
    final String title = _title(summary, safe.host);
    final String body = _body(safe);
    return Uri.parse(issuesUrl).replace(
      queryParameters: <String, String>{
        'title': title,
        'body': body,
        'labels': label,
      },
    );
  }

  /// The title: what the rider said, or the platform when they said nothing.
  static String _title(String summary, String host) {
    final String trimmed = summary.trim().replaceAll(RegExp(r'\s+'), ' ');
    final String title = trimmed.isEmpty ? 'Bug report on $host' : trimmed;
    return title.length <= titleLimit
        ? title
        : '${title.substring(0, titleLimit - 3)}...';
  }

  /// The body: where to start typing, then the report.
  ///
  /// The instructions come first because a textarea scrolls from the top: a
  /// rider who is asked what they did types there, above a report they cannot
  /// read anyway.
  static String _body(DeviceReport report) {
    return <String>[
      'What happened:',
      '',
      '',
      'What you expected:',
      '',
      '',
      '---',
      // Said rather than done silently: the rider must know what they are
      // publishing.
      'This report was cleaned before opening: no machine name, no IP address,',
      'no controller identifier and no serial number. Read it, edit it, and close',
      'the page if you would rather not send it.',
      '',
      report.render(),
    ].join('\n');
  }
}
