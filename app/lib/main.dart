import 'dart:async';

import 'package:flutter/material.dart' hide Action;

import 'settings/settings_store.dart';
import 'state/app_state.dart';
import 'ui/design.dart';
import 'ui/shell.dart';
import 'net/console_endpoint.dart';

class OpenZclickApp extends StatefulWidget {
  /// Creates the application.
  ///
  /// [state] exists for tests, which start the application in a known state —
  /// past the first-start guide, or with a publisher that is not a socket.
  const OpenZclickApp({this.state, super.key});

  /// State to run with, `null` on a real launch.
  final AppState? state;

  @override
  State<OpenZclickApp> createState() => _OpenZclickAppState();
}

class _OpenZclickAppState extends State<OpenZclickApp> {
  late final AppState _state = widget.state ?? AppState();

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  /// Restores the settings, then dials the bridge a QR code pointed at.
  ///
  /// A scanned code opens the page with `?bridge=…&code=…`: nothing is typed, and
  /// the console connects before the rider sees the screen.
  Future<void> _start() async {
    await _state.restore(PrefsSettingsStore());
    final ({String host, String code})? target = ConsoleEndpoint.fromQuery(
      Uri.base.queryParameters,
    );
    if (target == null) return;
    await _state.connectConsole(target.host, target.code);
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'openzclick',
      debugShowCheckedModeBanner: false,
      // One visual language for every platform: the instrument described in
      // `ui/design.dart`, not Material's default card kit with a generic blue.
      theme: openzclickTheme(),
      home: HomeShell(state: _state),
    );
  }
}
