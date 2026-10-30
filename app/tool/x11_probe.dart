// Checks the X11 keyboard injection without the application.
//
//   Xvfb :99 -screen 0 1280x720x24 &
//   DISPLAY=:99 xev -root -event keyboard > /tmp/xev.log &
//   DISPLAY=:99 dart run tool/x11_probe.dart i Left

import 'dart:io';

import 'package:openzclick/net/x11_injection.dart';

Future<void> main(List<String> args) async {
  final X11Injection injection = X11Injection();
  stdout.writeln('display: ${Platform.environment['DISPLAY']}');
  stdout.writeln('available: ${injection.available}');
  if (!injection.available) exit(1);

  for (final String key in args.isEmpty ? <String>['i', 'k'] : args) {
    await injection.pressKey(key);
    stdout.writeln('sent: $key');
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  injection.dispose();
}
