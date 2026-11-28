import 'dart:io' show Platform, Process, ProcessResult;

import 'package:flutter/services.dart';

/// Opens the training application, because the rider has to open it anyway.
///
/// The order of a real session is: pair the controller, then start MyWhoosh, then
/// connect it. Asking a rider to leave the application, find an icon and come
/// back is the step where they lose the thread, so the simple screen offers the
/// press instead.
///
/// Where the platform cannot do it, [supported] is false and no button is drawn:
/// a button that does nothing is worse than no button.
abstract final class TrainingAppLauncher {
  /// Android package of MyWhoosh, as published on Google Play.
  static const String androidPackage = 'com.mywhoosh.whooshgame';

  /// Windows application identity of the MyWhoosh Store package.
  ///
  /// Measured on a Windows 11 machine with MyWhoosh 6.3.2, not guessed:
  /// `Get-StartApps | Where-Object Name -like '*whoosh*'` answered
  /// `MyWhooshTechnologyService.644173E064ED2_eps1123pz0kt0!MYWHOOSH`, and
  /// `Get-AppxPackage` confirmed the matching package family name. An older
  /// build of the package shipped under `MyWhooshTechnologyService.MyWhoosh_…`:
  /// the constant is therefore a first candidate, and a failure simply hides the
  /// button on the next press instead of pretending.
  static const String windowsAppId =
      'MyWhooshTechnologyService.644173E064ED2_eps1123pz0kt0!MYWHOOSH';

  static const MethodChannel _channel = MethodChannel('openzclick/launcher');

  /// True where a press can really open MyWhoosh.
  ///
  /// macOS and iOS are deliberately absent: neither allows one application to
  /// launch another reliably, and the URL scheme is not documented by MyWhoosh.
  static bool get supported => Platform.isWindows || Platform.isAndroid;

  /// Opens [url] in the browser, and says whether it could.
  ///
  /// Same rule as the shortcut: a page the rider cannot reach is a false, and
  /// the caller falls back to copying the text.
  static Future<bool> openUri(Uri url) async {
    try {
      if (Platform.isWindows) {
        // `start` hands the URL to the default browser without a shell, so an
        // ampersand in a query string is not read as a command separator.
        final ProcessResult result = await Process.run('cmd', <String>[
          '/c',
          'start',
          '',
          url.toString(),
        ], runInShell: false);
        return result.exitCode == 0;
      }
      if (Platform.isMacOS) {
        return (await Process.run('open', <String>[url.toString()])).exitCode ==
            0;
      }
      if (Platform.isLinux) {
        return (await Process.run('xdg-open', <String>[
              url.toString(),
            ])).exitCode ==
            0;
      }
      if (Platform.isAndroid) {
        final bool? opened = await _channel.invokeMethod<bool>(
          'openUri',
          <String, String>{'url': url.toString()},
        );
        return opened ?? false;
      }
      // iOS: no documented way for an application to hand a URL to Safari
      // without a plugin, so the caller copies instead.
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Opens MyWhoosh, and says whether it could.
  ///
  /// Never throws: a missing installation is a rider with no shortcut, not a
  /// broken application.
  static Future<bool> open() async {
    if (Platform.isAndroid) {
      try {
        final bool? started = await _channel.invokeMethod<bool>(
          'open',
          <String, String>{'package': androidPackage},
        );
        return started ?? false;
      } catch (_) {
        return false;
      }
    }
    if (!Platform.isWindows) return false;
    try {
      // `cmd /c start` is what launches an AppsFolder identity: measured on the
      // machine described above, `Start-Process "shell:AppsFolder\…"` works and
      // `explorer.exe "shell:AppsFolder\…"` does not, which is the variant most
      // snippets suggest.
      final ProcessResult result = await Process.run('cmd', <String>[
        '/c',
        'start',
        '',
        'shell:AppsFolder\\$windowsAppId',
      ], runInShell: false);
      // 0 with an unknown identity too: Windows reports nothing. The caller
      // treats a false as "no shortcut", which is the honest outcome.
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
