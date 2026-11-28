/// The press that turns "it does not work" into an issue.
///
/// One widget, two doses: a quiet link at the bottom of the simple screen, and
/// the same link next to the device report of the advanced one. Neither asks a
/// rider for anything: the press opens the GitHub issue page with the report
/// already in it, and a rider who would rather not publish anything closes the
/// tab.
///
/// No form, no email, no server. What travels is what [BugReport] put in the
/// URL, and it is scrubbed before it leaves.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/device_report.dart';
import '../platform/bug_report.dart';
import '../platform/training_app_launcher.dart';
import '../platform/version.dart';
import '../state/app_state.dart';

/// Opens the issue page, or copies the report when it cannot.
class ReportBugButton extends StatefulWidget {
  /// Creates the button for [state].
  const ReportBugButton({required this.state, this.dense = false, super.key});

  /// Shared application state, which owns the link the report describes.
  final AppState state;

  /// True for the discreet form used at the bottom of the simple screen.
  final bool dense;

  @override
  State<ReportBugButton> createState() => _ReportBugButtonState();
}

class _ReportBugButtonState extends State<ReportBugButton> {
  bool _busy = false;

  /// The report as it will be published: taken now, not at the last press.
  DeviceReport get _snapshot =>
      widget.state.controller.buildReport(appVersion).anonymized();

  Future<void> _report() async {
    if (_busy) return;
    setState(() => _busy = true);
    final DeviceReport snapshot = _snapshot;
    final Uri url = BugReport.issueUrl(report: snapshot);
    final bool opened = await TrainingAppLauncher.openUri(url);
    if (!mounted) return;
    if (opened) {
      setState(() => _busy = false);
      return;
    }
    // The page did not open: give the rider the text instead of nothing. The
    // report is the same one, scrubbed the same way.
    await Clipboard.setData(ClipboardData(text: snapshot.render()));
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Report copied: paste it at github.com/Atlanwhite147/openzclick/issues',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String label = _busy ? 'Opening...' : 'Report a bug';
    if (widget.dense) {
      return TextButton.icon(
        onPressed: _report,
        icon: const Icon(Icons.bug_report_outlined, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );
    }
    return TextButton.icon(
      onPressed: _report,
      icon: const Icon(Icons.bug_report_outlined, size: 18),
      label: Text(label),
    );
  }
}
